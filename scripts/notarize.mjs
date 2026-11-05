import {execFileSync} from 'node:child_process';
import {mkdtemp, rm, mkdir, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve, join} from 'node:path';
import {APPLE_TEAM_ID} from './distribution.mjs';

const target = resolve(process.argv[2] || 'output/native/Keep My Speakers Awake.app');
const profile = process.env.KMSA_NOTARY_PROFILE;
if (!profile) throw new Error('Set KMSA_NOTARY_PROFILE to an existing notarytool Keychain profile. Never put credentials in source.');
const run = (cmd,args) => execFileSync(cmd,args,{encoding:'utf8',stdio:['ignore','pipe','inherit']}).trim();
const staging = await mkdtemp(join(tmpdir(),'kmsa-notary-'));
try {
  const isApp = target.endsWith('.app');
  if (!isApp && !target.endsWith('.dmg')) throw new Error('Notarization accepts an .app or .dmg only.');
  if (isApp) run('codesign',['--verify','--deep','--strict','-R',`=anchor apple generic and certificate leaf[subject.OU] = "${APPLE_TEAM_ID}"`,target]);
  const upload = isApp ? join(staging,'KMSA.zip') : target;
  if (isApp) run('ditto',['-c','-k','--keepParent',target,upload]);
  const receipt = JSON.parse(run('xcrun',['notarytool','submit',upload,'--keychain-profile',profile,'--wait','--timeout','20m','--output-format','json']));
  const evidence = resolve('output/apple-distribution');
  await mkdir(evidence,{recursive:true});
  await writeFile(join(evidence,isApp?'app-notary-receipt.json':'dmg-notary-receipt.json'),JSON.stringify(receipt,null,2)+'\n');
  if (receipt.status !== 'Accepted') throw new Error(`Apple notarization not accepted: ${receipt.status}; submission ${receipt.id}`);
  run('xcrun',['stapler','staple',target]);
  run('xcrun',['stapler','validate',target]);
  run('spctl',['--assess','--type',isApp?'execute':'open',...(isApp?[]:['--context','context:primary-signature']),'-v',target]);
  console.log(`Apple accepted and stapled ${target}; submission ${receipt.id}.`);
} finally { await rm(staging,{recursive:true,force:true}); }
