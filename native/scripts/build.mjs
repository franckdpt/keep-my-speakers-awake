import { spawnSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, readFile, writeFile, readdir, rm } from "node:fs/promises";
import { dirname, resolve, join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { SIGNAL_PROFILES } from "../../lib/signal-profiles.js";
import { readVersion } from "../../scripts/release-contract.mjs";

const native = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const root = resolve(native, "..");
const version = readVersion();
const resources = join(native, "Sources/KMSA/Resources");
const destination = join(root, "output/native");
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
run("xcrun", ["swift", "build", "--package-path", native, "--arch", "arm64", "-c", "release", "--product", "KMSA"]);
run("xcrun", ["swift", "build", "--package-path", native, "--arch", "arm64", "-c", "release", "--product", "KMSAUpdateInstaller"]);
const binaries = run("xcrun", ["swift", "build", "--package-path", native, "--arch", "arm64", "-c", "release", "--show-bin-path"], true);
const macOS = join(app, "Contents/MacOS");
const bundled = join(app, "Contents/Resources");
await mkdir(macOS, { recursive: true });
const helpers = join(app, "Contents/Helpers");
await mkdir(helpers, { recursive: true });
await copyFile(join(binaries, "KMSAUpdateInstaller"), join(helpers, "KMSAUpdateInstaller"));
run("chmod", ["+x", join(helpers, "KMSAUpdateInstaller")]);
run("codesign", ["--force", "--sign", "-", join(helpers, "KMSAUpdateInstaller")]);
await mkdir(join(bundled, "Signals"), { recursive: true });
await copyFile(join(binaries, "KMSA"), join(macOS, "KMSA"));
for (const file of await readdir(resources)) {
  if (file.endsWith(".wav") || file === "profiles.json") await copyFile(join(resources, file), join(bundled, "Signals", file));
}
await writeFile(join(app, "Contents/Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<!-- Stable identity preserves settings and login registration across the KMSA rename. -->
<key>CFBundleIdentifier</key><string>fr.franckdupont.kmma.native</string>
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
run("codesign", ["--force", "--sign", "-", app]);
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
