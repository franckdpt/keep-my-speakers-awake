import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ASSET_NAME, LATEST_DOWNLOAD, readVersion, validateVersion, validateTag, compareVersions, validateManifest } from '../scripts/release-contract.mjs';
import { DOWNLOAD_URL } from '../landing/src/download.js';

test('only a matching stable tag may publish the built app', () => {
  validateTag('v1.6.5', '1.6.5');
  for (const tag of ['v1.6.4', 'v1.6.5-beta', '1.6.5', 'v1.6.5; echo unsafe']) {
    assert.throws(() => validateTag(tag, '1.6.5'));
  }
});

test('old releases never replace a newer latest version', () => {
  assert.equal(compareVersions('v1.6.5', 'v1.6.4'), 1);
  assert.equal(compareVersions('v1.6.9', 'v1.6.10'), -1);
  assert.equal(compareVersions('v1.6.5', '1.6.5'), 0);
  assert.equal(compareVersions('v2.0.0', 'v1.99.99'), 1);
  assert.throws(() => compareVersions('v1.6.5-beta', 'v1.6.5'));
});

test('the public download uses the stable GitHub latest-asset route', () => {
  assert.equal(LATEST_DOWNLOAD, `https://github.com/franckdpt/kmsa/releases/latest/download/${ASSET_NAME}`);
  assert.equal(DOWNLOAD_URL, LATEST_DOWNLOAD);
});

test('version metadata must be valid before a bundle is built', () => {
  const version = readVersion();
  assert.equal(validateVersion(version), version);
  for (const change of [{build: 0}, {build: '31'}, {version: '1.6.5-beta'}, {minimumMacOS: 'latest'}]) {
    assert.throws(() => validateVersion({...version, ...change}));
  }
});

test('a wrong architecture, version, commit, hash or filename blocks publication', () => {
  const version = readVersion();
  const revision = 'a'.repeat(40);
  const manifest = {...version, architecture:'arm64', asset:ASSET_NAME, sourceRevision:revision, sha256:'b'.repeat(64)};
  validateManifest(manifest, version, revision);
  for (const change of [{architecture:'x86_64'}, {version:'1.6.4'}, {build:30}, {asset:'other.dmg'}, {sourceRevision:'c'.repeat(40)}, {sha256:'bad'}]) {
    assert.throws(() => validateManifest({...manifest,...change}, version, revision));
  }
});
