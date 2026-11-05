import {execFileSync} from 'node:child_process';
import {access, mkdir, mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {BUNDLE_ID,APPLE_TEAM_ID} from './distribution.mjs';
import {readVersion} from './release-contract.mjs';

const identity = process.env.KMSA_INSTALLER_IDENTITY;
if (!identity?.startsWith('3rd Party Mac Developer Installer:')) throw new Error('Set KMSA_INSTALLER_IDENTITY to the Mac Installer Distribution certificate.');
const run = (cmd,args) => execFileSync(cmd,args,{encoding:'utf8',stdio:['ignore','pipe','inherit']}).trim();
const staging = await mkdtemp(join(tmpdir(),'kmsa-store-package-'));
const app = join(staging,'Keep My Speakers Awake.app');
try {
run('ditto',['--noextattr','--norsrc',resolve('output/native-app-store/Keep My Speakers Awake.app'),app]);
run('xattr',['-cr',app]);
const plist = key => run('/usr/libexec/PlistBuddy',['-c',`Print :${key}`,join(app,'Contents/Info.plist')]);
const version = readVersion();
if (plist('KMSADistributionChannel')!=='app-store' || plist('CFBundleIdentifier')!==BUNDLE_ID ||
    plist('CFBundleShortVersionString')!==version.version || plist('CFBundleVersion')!==String(version.build)) throw new Error('Rebuild the matching App Store channel.');
run('codesign',['--verify','--deep','--strict','-R',`=anchor apple generic and certificate leaf[subject.OU] = "${APPLE_TEAM_ID}" and certificate leaf[field.1.2.840.113635.100.6.1.7] exists`,app]);
const parsePlist = xml => JSON.parse(execFileSync('plutil',['-convert','json','-o','-','-'],{input:xml,encoding:'utf8'}));
const entitlements = parsePlist(run('codesign',['-d','--entitlements',':-',app]));
// Provisioning plists contain dates and DER certificate data, which plutil cannot encode as JSON.
const profile = JSON.parse(execFileSync('python3',['-c',
  'import sys,plistlib,json,datetime; print(json.dumps(plistlib.loads(sys.stdin.buffer.read()), default=lambda v: v.isoformat()+"Z" if isinstance(v,datetime.datetime) else None))'],
  {encoding:'utf8',input:run('security',['cms','-D','-i',join(app,'Contents/embedded.provisionprofile')])}));
if (entitlements['com.apple.security.app-sandbox']!==true || entitlements['com.apple.security.get-task-allow']===true ||
    profile.TeamIdentifier?.[0]!==APPLE_TEAM_ID || new Date(profile.ExpirationDate)<=new Date() ||
    profile.Entitlements?.['com.apple.application-identifier']!==`${profile.ApplicationIdentifierPrefix?.[0]}.${BUNDLE_ID}` ||
    entitlements['com.apple.application-identifier']!==profile.Entitlements['com.apple.application-identifier'] ||
    entitlements['com.apple.developer.team-identifier']!==APPLE_TEAM_ID ||
    profile.ProvisionedDevices || profile.ProvisionsAllDevices) throw new Error('Invalid App Store provisioning profile or sandbox entitlements.');
if (await access(join(app,'Contents/Helpers/KMSAUpdateInstaller')).then(()=>true,()=>false)) throw new Error('An App Store app must not include the standalone updater.');
// Store-signed apps require Apple's distribution path to execute. Run the native
// checks on the sandboxed development build before signing; validate this package
// through Transporter/TestFlight rather than bypassing macOS's execution policy.
const directory = resolve('output/app-store');
await mkdir(directory,{recursive:true});
const pkg = join(directory,'Keep-My-Speakers-Awake.pkg');
run('productbuild',['--component',app,'/Applications','--sign',identity,pkg]);
run('pkgutil',['--check-signature',pkg]);
console.log(`Prepared ${pkg}. Upload and App Review acceptance are separate steps.`);
} finally { await rm(staging,{recursive:true,force:true}); }
