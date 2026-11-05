import {execFileSync} from 'node:child_process';
import {homedir} from 'node:os';
import {join} from 'node:path';
import {prepareSwiftSources} from './swift-sources.mjs';
const source = await prepareSwiftSources('checks');
execFileSync('swift',['run','--scratch-path',join(homedir(),'Library/Caches/KMSA/swift-checks'),
  '--package-path',source,'KMSAChecks'],{stdio:'inherit'});
