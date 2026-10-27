import { readFileSync } from 'node:fs';

export const ASSET_NAME = 'Keep-My-Speakers-Awake-Apple-Silicon.dmg';
export const REPOSITORY = 'franckdpt/kmsa';
export const LATEST_DOWNLOAD = `https://github.com/${REPOSITORY}/releases/latest/download/${ASSET_NAME}`;

export function validateVersion(value) {
  if (!value || !/^\d+\.\d+\.\d+$/.test(value.version) ||
      !Number.isSafeInteger(value.build) || value.build < 1 ||
      !/^\d+\.\d+(?:\.\d+)?$/.test(value.minimumMacOS)) {
    throw new Error('Invalid version.json: stable semantic version, positive build and macOS version required.');
  }
  return value;
}

export function readVersion() {
  return validateVersion(JSON.parse(readFileSync(new URL('../version.json', import.meta.url), 'utf8')));
}

export function validateTag(tag, version) {
  if (tag !== `v${version}`) throw new Error(`Release tag must be v${version}, got ${tag}.`);
}

export function compareVersions(left, right) {
  const pattern = /^v?(\d+)\.(\d+)\.(\d+)$/;
  const a = left.match(pattern), b = right.match(pattern);
  if (!a || !b) throw new Error('Only stable version tags are supported.');
  for (let i = 1; i <= 3; i++) {
    const difference = Number(a[i]) - Number(b[i]);
    if (difference) return Math.sign(difference);
  }
  return 0;
}

export function validateManifest(manifest, version, revision) {
  if (manifest.version !== version.version || manifest.build !== version.build ||
      manifest.minimumMacOS !== version.minimumMacOS || manifest.architecture !== 'arm64' ||
      manifest.asset !== ASSET_NAME || manifest.sourceRevision !== revision ||
      !/^[0-9a-f]{64}$/.test(manifest.sha256)) {
    throw new Error('Release manifest does not match this tag, commit, version or Apple Silicon asset.');
  }
}
