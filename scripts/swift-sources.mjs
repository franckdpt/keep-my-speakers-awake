import {cp, mkdir, rm} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

// File Provider can change source mtimes during compilation in synced Documents.
// Compile a fresh byte-for-byte local snapshot outside that synchronized tree.
export async function prepareSwiftSources(channel) {
  const source = fileURLToPath(new URL('../native/', import.meta.url));
  const destination = join(homedir(),'Library/Caches/KMSA',`source-${channel}`);
  await rm(destination,{recursive:true,force:true});
  await mkdir(destination,{recursive:true});
  for (const item of ['Package.swift','Sources','Tests']) {
    await cp(join(source,item),join(destination,item),{recursive:true});
  }
  return destination;
}
