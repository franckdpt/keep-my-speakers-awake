import {execFileSync} from 'node:child_process';
import {readFile, mkdir, mkdtemp, rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {ASSET_NAME,readVersion,validateTag,validateManifest} from './release-contract.mjs';
import {APPLE_TEAM_ID} from './distribution.mjs';

// CI verifies a locally signed draft asset. Private signing keys never leave the Mac.
const root = resolve('.');
const run = (cmd,args) => execFileSync(cmd,args,{encoding:'utf8',stdio:['ignore','pipe','inherit']}).trim();
const version = readVersion();
validateTag(process.env.KMSA_EXPECTED_TAG,version.version);
const manifest = JSON.parse(await readFile('output/releases/release-manifest.json','utf8'));
validateManifest(manifest,version,run('git',['rev-parse','HEAD']));
if (manifest.signature!=='developer-id' || manifest.notarized!==true || manifest.teamIdentifier!==APPLE_TEAM_ID) throw new Error('A notarized Developer ID draft is required before pushing a release tag.');
const hash = async file => createHash('sha256').update(await readFile(file)).digest('hex');
const dmg = resolve('output/releases',ASSET_NAME);
if (await hash(dmg)!==manifest.sha256) throw new Error('DMG digest mismatch.');
if ((await readFile('output/releases/SHA256SUMS.txt','utf8')).trim()!==`${manifest.sha256}  ${ASSET_NAME}`) throw new Error('Checksum file differs from the manifest.');
run('hdiutil',['verify',dmg]);
run('codesign',['--verify','--strict','-R',`=anchor apple generic and certificate leaf[subject.OU] = "${APPLE_TEAM_ID}"`,dmg]);
run('xcrun',['stapler','validate',dmg]);
run('spctl',['--assess','--type','open','--context','context:primary-signature','-v',dmg]);
const staging = await mkdtemp(join(tmpdir(),'kmsa-verify-release-'));
const mount = join(staging,'mount');
let mounted=false;
try {
  await mkdir(mount);
  run('hdiutil',['attach','-readonly','-nobrowse','-mountpoint',mount,dmg]); mounted=true;
  run(process.env.KMSA_DMG_PYTHON || 'python3',[join(root,'scripts/verify-dmg-layout.py'),mount]);
  const app = join(mount,'Keep My Speakers Awake.app');
  const plist = key => run('/usr/libexec/PlistBuddy',['-c',`Print :${key}`,join(app,'Contents/Info.plist')]);
  if (plist('CFBundleShortVersionString')!==version.version || plist('CFBundleVersion')!==String(version.build) ||
      plist('LSMinimumSystemVersion')!==version.minimumMacOS || plist('CFBundleIdentifier')!=='fr.franckdupont.kmma.native' ||
      plist('KMSADistributionChannel')!=='developer-id') throw new Error('The mounted app does not match the release.');
  run('codesign',['--verify','--deep','--strict','-R',`=anchor apple generic and certificate leaf[subject.OU] = "${APPLE_TEAM_ID}"`,app]);
  run('xcrun',['stapler','validate',app]);
  run('spctl',['--assess','--type','execute','-v',app]);
  const executable=join(app,'Contents/MacOS/KMSA');
  if (run('lipo',[executable,'-archs'])!=='arm64' || await hash(join(app,'Contents/Resources/Signals/sub2.wav'))!==await hash('signals/sub2.wav')) throw new Error('Architecture or signal mismatch.');
  run(executable,['--self-check']);
  run(executable,['--update-self-check']);
  console.log(`Verified notarized KMSA ${version.version} (${version.build}), Apple team ${APPLE_TEAM_ID}, source ${manifest.sourceRevision}. No audio played.`);
} finally {
  if(mounted) run('hdiutil',['detach',mount]);
  await rm(staging,{recursive:true,force:true});
}
