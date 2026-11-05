import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { ASSET_NAME, readVersion, validateTag } from './release-contract.mjs';
import { distributionConfig, APPLE_TEAM_ID } from './distribution.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const run = (cmd, args) => execFileSync(cmd, args, {cwd: root, encoding:'utf8'}).trim();
const version = readVersion();
const distribution = distributionConfig();
if (distribution.appStore) throw new Error('Use package:app-store for the Mac App Store edition.');
const dmgPython = process.env.KMSA_DMG_PYTHON || 'python3';
run(dmgPython, ['-c', 'import dmgbuild, ds_store']);
if (process.env.KMSA_EXPECTED_TAG) validateTag(process.env.KMSA_EXPECTED_TAG, version.version);
if (run('git', ['status','--porcelain','--untracked-files=normal'])) throw new Error('Commit source changes before packaging a release.');
const revision = run('git', ['rev-parse','HEAD']);
const destination = join(root, 'output/releases');
const staging = await mkdtemp(join(tmpdir(), 'kmsa-dmg-'));
const contents = join(staging, 'contents');
const appName = 'Keep My Speakers Awake.app';
const stagedApp = join(contents, appName);
const sourceApp = join(root, 'output/native', appName);
const sha256 = async path => createHash('sha256').update(await readFile(path)).digest('hex');
const plist = (app, key) => run('/usr/libexec/PlistBuddy',['-c',`Print :${key}`,join(app,'Contents/Info.plist')]);
let mounted = false;
const mount = join(staging,'verify-mount');

try {
  if (plist(sourceApp,'KMSADistributionChannel') !== distribution.channel) throw new Error('Build and package with the same KMSA_DISTRIBUTION.');
  await mkdir(contents);
  await mkdir(destination, {recursive:true});
  run('ditto',['--noextattr','--norsrc',sourceApp,stagedApp]);
  run('xattr',['-cr',stagedApp]);
  run('codesign',['--verify','--deep','--strict',stagedApp]);
  if (distribution.channel === 'developer-id') {
    run('codesign',['--verify','--deep','--strict','-R',`=anchor apple generic and certificate leaf[subject.OU] = "${APPLE_TEAM_ID}"`,stagedApp]);
    run('node',[join(root,'scripts/notarize.mjs'),stagedApp]);
  }
  if (plist(stagedApp,'CFBundleShortVersionString') !== version.version ||
      plist(stagedApp,'CFBundleVersion') !== String(version.build) ||
      plist(stagedApp,'LSMinimumSystemVersion') !== version.minimumMacOS) {
    throw new Error('App bundle version does not match version.json. Build again.');
  }
  const executable = join(stagedApp,'Contents/MacOS/KMSA');
  if (run('lipo',[executable,'-archs']) !== 'arm64') throw new Error('The release must contain an arm64-only executable.');
  const signal = join(stagedApp,'Contents/Resources/Signals/sub2.wav');
  if (await sha256(signal) !== await sha256(join(root,'signals/sub2.wav'))) throw new Error('Packaged audio differs from source.');
  const dmg = join(destination,ASSET_NAME);
  run('swift', [join(root,'scripts/dmg-background.swift'), staging]);
  await rm(dmg, {force:true});
  run(dmgPython, ['-m','dmgbuild','-s',join(root,'scripts/dmg-settings.py'),
    '-D',`app=${stagedApp}`,'-D',`background=${join(staging,'background.png')}`,
    'Keep My Speakers Awake',dmg]);
  if (distribution.channel === 'developer-id') {
    run('codesign',['--force','--timestamp','--sign',distribution.identity,dmg]);
    run('node',[join(root,'scripts/notarize.mjs'),dmg]);
  }
  run('hdiutil',['verify',dmg]);
  await mkdir(mount);
  run('hdiutil',['attach','-readonly','-nobrowse','-mountpoint',mount,dmg]);
  mounted = true;
  const mountedApp = join(mount,appName);
  run(dmgPython, [join(root,'scripts/verify-dmg-layout.py'), mount]);
  run('codesign',['--verify','--deep','--strict',mountedApp]);
  if (distribution.channel === 'developer-id') {
    run('xcrun',['stapler','validate',mountedApp]);
    run('spctl',['--assess','--type','execute','-v',mountedApp]);
  }
  if (plist(mountedApp,'CFBundleShortVersionString') !== version.version ||
      await sha256(join(mountedApp,'Contents/MacOS/KMSA')) !== await sha256(executable)) {
    throw new Error('Mounted DMG does not contain the verified app.');
  }
  run('hdiutil',['detach',mount]);
  mounted = false;
  const hash = await sha256(dmg);
  await writeFile(join(destination,'SHA256SUMS.txt'),`${hash}  ${ASSET_NAME}\n`);
  await writeFile(join(destination,'release-manifest.json'),JSON.stringify({
    ...version, architecture:'arm64', asset:ASSET_NAME, sourceRevision:revision,
    sha256:hash, signature:distribution.signed?'developer-id':'ad-hoc', notarized:distribution.signed,
    ...(distribution.signed ? {teamIdentifier:APPLE_TEAM_ID} : {}),
  },null,2)+'\n');
  console.log(`Verified KMSA ${version.version} (${version.build}), arm64, source ${revision}.\n${hash}  ${ASSET_NAME}`);
} finally {
  if (mounted) run('hdiutil',['detach',mount]);
  await rm(staging,{recursive:true,force:true});
}
