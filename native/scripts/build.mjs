import { spawnSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, readFile, writeFile, readdir, rm } from "node:fs/promises";
import { dirname, resolve, join } from "node:path";
import { tmpdir, homedir } from "node:os";
import { fileURLToPath } from "node:url";
import { SIGNAL_PROFILES } from "../../lib/signal-profiles.js";
import { readVersion } from "../../scripts/release-contract.mjs";
import { distributionConfig, BUNDLE_ID, APPLE_TEAM_ID } from "../../scripts/distribution.mjs";
import { prepareSwiftSources } from "../../scripts/swift-sources.mjs";

const native = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const root = resolve(native, "..");
const version = readVersion();
const distribution = distributionConfig();
if (distribution.appStore && distribution.signed && !process.env.KMSA_PROVISIONING_PROFILE) {
  throw new Error('Signed App Store builds require KMSA_PROVISIONING_PROFILE.');
}
const swiftFlags = distribution.appStore ? ["-Xswiftc", "-DAPP_STORE"] : [];
const buildPath = process.env.KMSA_SWIFT_BUILD_PATH || join(homedir(), "Library/Caches/KMSA", distribution.appStore ? "swift-app-store" : "swift-direct");
const resources = join(native, "Sources/KMSA/Resources");
const destination = join(root, distribution.appStore ? "output/native-app-store" : "output/native");
// Sign outside synced Documents: macOS's file provider can continually add FinderInfo to .app folders there.
const staging = await mkdtemp(join(tmpdir(), "kmsa-build-"));
const app = join(staging, "Keep My Speakers Awake.app");
const publishedApp = join(destination, "Keep My Speakers Awake.app");

function run(command, args, capture = false) {
  const result = spawnSync(command, args, {
    cwd: root, encoding: "utf8", stdio: capture ? "pipe" : "inherit",
  });
  if (result.error || result.status !== 0) throw result.error ?? new Error(`${command} failed: ${result.stderr ?? result.status}`);
  return result.stdout?.trim();
}


function sign(target, entitlements = null) {
  run("codesign", ["--force", "--sign", distribution.identity,
    ...(distribution.signed ? ["--timestamp", "--options", "runtime"] : []),
    ...(entitlements ? ["--entitlements", entitlements] : []), target]);
}

await mkdir(resources, { recursive: true });
const activeProfiles = SIGNAL_PROFILES.filter(profile => profile.id === "sub2");
if (activeProfiles.length !== 1) throw new Error("Expected the single active 20 Hz ×2 signal.");
// These WAVs are generated copies. Original experiments remain under signals/.
for (const file of await readdir(resources)) {
  if (file.endsWith(".wav") && file !== "sub2.wav") await rm(join(resources, file));
}
const profiles = [];
for (const profile of activeProfiles) {
  const file = `${profile.id}.wav`;
  await copyFile(join(root, profile.path), join(resources, file));
  profiles.push({ id: profile.id, label: profile.label, file, hint: profile.hint ?? null });
}
await writeFile(join(resources, "profiles.json"), JSON.stringify(profiles, null, 2) + "\n");
const buildSource = await prepareSwiftSources(distribution.appStore ? 'app-store' : 'direct');
run("xcrun", ["swift", "build", "--scratch-path", buildPath, "--package-path", buildSource, "--arch", "arm64", "-c", "release", "--product", "KMSA", ...swiftFlags]);
if (!distribution.appStore) run("xcrun", ["swift", "build", "--scratch-path", buildPath, "--package-path", buildSource, "--arch", "arm64", "-c", "release", "--product", "KMSAUpdateInstaller"]);
const binaries = run("xcrun", ["swift", "build", "--scratch-path", buildPath, "--package-path", buildSource, "--arch", "arm64", "-c", "release", "--show-bin-path"], true);
const macOS = join(app, "Contents/MacOS");
const bundled = join(app, "Contents/Resources");
await mkdir(macOS, { recursive: true });
const helpers = join(app, "Contents/Helpers");
if (!distribution.appStore) {
await mkdir(helpers, { recursive: true });
await copyFile(join(binaries, "KMSAUpdateInstaller"), join(helpers, "KMSAUpdateInstaller"));
run("chmod", ["+x", join(helpers, "KMSAUpdateInstaller")]);
sign(join(helpers, "KMSAUpdateInstaller"));
}
await mkdir(join(bundled, "Signals"), { recursive: true });
await copyFile(join(binaries, "KMSA"), join(macOS, "KMSA"));
for (const file of await readdir(resources)) {
  if (file.endsWith(".wav") || file === "profiles.json") await copyFile(join(resources, file), join(bundled, "Signals", file));
}
await writeFile(join(app, "Contents/Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<!-- Stable identity preserves settings and login registration across the KMSA rename. -->
<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
<key>CFBundleName</key><string>Keep My Speakers Awake</string>
<key>CFBundleDisplayName</key><string>Keep My Speakers Awake</string>
<key>CFBundleExecutable</key><string>KMSA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${version.version}</string>
<key>CFBundleVersion</key><string>${version.build}</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>fr</string></array>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>LSMinimumSystemVersion</key><string>${version.minimumMacOS}</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>ITSAppUsesNonExemptEncryption</key><false/>
<key>KMSADistributionChannel</key><string>${distribution.channel}</string>
<key>LSUIElement</key><true/>
<key>LSMultipleInstancesProhibited</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticTermination</key><false/>
</dict></plist>
`);
const iconset = join(destination, "AppIcon.iconset");
await mkdir(iconset, { recursive: true });
for (const points of [16, 32, 128, 256, 512]) {
  for (const scale of [1, 2]) {
    const size = points * scale;
    run("sips", ["-z", String(size), String(size), join(root, "images/awake-logo-on128.png"), "--out",
      join(iconset, `icon_${points}x${points}${scale === 2 ? "@2x" : ""}.png`)], true);
  }
}
run("iconutil", ["-c", "icns", iconset, "-o", join(bundled, "AppIcon.icns")]);
run("chmod", ["+x", join(macOS, "KMSA")]);
// Finder/file-provider metadata on generated bundles can prevent local code signing.
run("xattr", ["-cr", app]);
await copyFile(join(native, "PrivacyInfo.xcprivacy"), join(bundled, "PrivacyInfo.xcprivacy"));
if (distribution.appStore && process.env.KMSA_PROVISIONING_PROFILE) {
  await copyFile(process.env.KMSA_PROVISIONING_PROFILE, join(app, "Contents/embedded.provisionprofile"));
}
let entitlementPath = distribution.appStore ? join(native, "AppStore.entitlements") : null;
if (distribution.appStore && distribution.signed) {
  const profileXML = run('security', ['cms', '-D', '-i', process.env.KMSA_PROVISIONING_PROFILE], true);
  const profilePath = join(staging, 'profile.plist');
  await writeFile(profilePath, profileXML);
  const profileTeam = run('/usr/libexec/PlistBuddy', ['-c', 'Print :TeamIdentifier:0', profilePath], true);
  const prefix = run('/usr/libexec/PlistBuddy', ['-c', 'Print :ApplicationIdentifierPrefix:0', profilePath], true);
  const identifier = run('/usr/libexec/PlistBuddy', ['-c', 'Print :Entitlements:com.apple.application-identifier', profilePath], true);
  if (profileTeam !== APPLE_TEAM_ID || identifier !== `${prefix}.${BUNDLE_ID}`) throw new Error('Provisioning profile is for a different team or app.');
  entitlementPath = join(staging, 'AppStore.entitlements');
  await copyFile(join(native, 'AppStore.entitlements'), entitlementPath);
  for (const [key, value] of [['com.apple.application-identifier', identifier], ['com.apple.developer.team-identifier', APPLE_TEAM_ID]]) {
    run('/usr/libexec/PlistBuddy', ['-c', `Add :${key} string ${value}`, entitlementPath]);
  }
}
sign(app, entitlementPath);
if (distribution.signed) {
  run("codesign", ["--verify", "--strict", "-R", `=anchor apple generic and certificate leaf[subject.OU] = "${APPLE_TEAM_ID}"`, app]);
}
run("codesign", ["--verify", "--deep", "--strict", app]);
run("plutil", ["-lint", join(app, "Contents/Info.plist")]);
// Check that packaging did not change the audio already tested in the extension.
for (const profile of activeProfiles) {
  const source = await readFile(join(root, profile.path));
  const packaged = await readFile(join(bundled, "Signals", `${profile.id}.wav`));
  if (!source.equals(packaged)) throw new Error(`Changed audio: ${profile.id}`);
}
await rm(publishedApp, { recursive: true, force: true });
run("ditto", ["--noextattr", "--norsrc", app, publishedApp]);
run("codesign", ["--verify", "--deep", "--strict", publishedApp]);
run("ditto", ["-c", "-k", "--keepParent", app, join(destination, "Keep My Speakers Awake-macOS.zip")]);
await rm(staging, { recursive: true, force: true });
console.log(`Built ${publishedApp}\nVerified ${profiles.length} byte-identical signal files.`);
