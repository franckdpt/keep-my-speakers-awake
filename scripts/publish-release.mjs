import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { ASSET_NAME, REPOSITORY, readVersion, validateTag, validateManifest, compareVersions, findRelease } from './release-contract.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const version = readVersion();
const tag = process.env.GITHUB_REF_NAME;
const repository = process.env.GITHUB_REPOSITORY;
if (repository !== REPOSITORY) throw new Error(`Publishing is restricted to ${REPOSITORY}.`);
validateTag(tag, version.version);
const directory = join(root,'output/releases');
const manifest = JSON.parse(await readFile(join(directory,'release-manifest.json'),'utf8'));
validateManifest(manifest,version,process.env.GITHUB_SHA);
if (manifest.signature !== 'developer-id' || manifest.notarized !== true || manifest.teamIdentifier !== 'SRGS2S4PV9') {
  throw new Error('Publication requires the verified Developer ID-signed and Apple-notarized DMG.');
}
const hash = createHash('sha256').update(await readFile(join(directory,ASSET_NAME))).digest('hex');
if (hash !== manifest.sha256) throw new Error('DMG checksum differs from the verified build manifest.');

function gh(args, input) {
  const result = spawnSync('gh',args,{cwd:root,encoding:'utf8',input});
  if (result.status !== 0) throw new Error(result.stderr || `gh exited ${result.status}`);
  return result.stdout.trim();
}
function api(path, method = 'GET', body) {
  return JSON.parse(gh(['api',path,'--method',method,...(body ? ['--input','-'] : [])],body && JSON.stringify(body)));
}
function optionalGet(path) {
  const result = spawnSync('gh',['api',path],{cwd:root,encoding:'utf8'});
  if (result.status === 0) return JSON.parse(result.stdout);
  if (result.stderr.includes('HTTP 404')) return null;
  throw new Error(result.stderr);
}

const changes = await readFile(new URL(`../release-notes/${version.version}.md`, import.meta.url),'utf8').catch(error => {
  if (error.code === 'ENOENT') return '';
  throw error;
});
const notes = `${changes.trim()}\n\nNative menu bar app for Apple Silicon. Requires macOS ${version.minimumMacOS} or later.\n\nDownload **${ASSET_NAME}** below, open it and drag the app into Applications.\n\nSigned with Franck Dupont’s Apple Developer ID and notarized by Apple. The notarization tickets are stapled to the app and DMG.\n\nBuild ${version.build}; version and arm64 architecture verified from the app mounted from this DMG. SHA-256 and source revision are included in the attached manifest.\n`;
let release = optionalGet(`repos/${repository}/releases/tags/${tag}`);
if (!release) {
  const pages = JSON.parse(gh(['api',`repos/${repository}/releases?per_page=100`,'--paginate','--slurp']));
  release = findRelease(pages.flat(),tag);
}
if (release && !release.draft) throw new Error('This release is already published. Published assets are never replaced.');
if (!release) release = api(`repos/${repository}/releases`,'POST',{
  tag_name:tag, name:`KMSA ${version.version}`, body:notes, draft:true, prerelease:false, make_latest:'false',
});
const files = [ASSET_NAME,'SHA256SUMS.txt','release-manifest.json'];
gh(['release','upload',tag,...files.map(name=>join(directory,name)),'--repo',repository,'--clobber']);
const assets = api(`repos/${repository}/releases/${release.id}/assets`);
for (const name of files) {
  const asset = assets.find(asset=>asset.name===name);
  if (!asset || asset.state!=='uploaded' || asset.size<1) throw new Error(`Missing release asset: ${name}`);
  if (name===ASSET_NAME && asset.digest && asset.digest!==`sha256:${hash}`) throw new Error('Uploaded GitHub asset digest differs from the built DMG.');
}
const latest = optionalGet(`repos/${repository}/releases/latest`);
if (process.env.KMSA_DRAFT_ONLY === '1') {
  console.log(`Prepared draft ${release.html_url}. Push ${tag} to run Apple's artifact checks and publication in GitHub Actions.`);
  process.exit(0);
}
const promote = !latest || compareVersions(tag,latest.tag_name)>0;
const published = api(`repos/${repository}/releases/${release.id}`,'PATCH',{
  draft:false, prerelease:false, body:notes, make_latest:promote?'true':'false',
});
console.log(`Published ${published.html_url}. Latest promotion: ${promote}. Asset SHA-256: ${hash}`);
