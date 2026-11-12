# Keep My Speakers Awake

A tiny Mac app that prevents speaker standby.

Native menu bar utility for **Apple Silicon**, **macOS 14.2+**, with automatic
French / English copy. Uses a low-frequency signal on the selected external audio
output (analog, USB, Bluetooth, HDMI/DisplayPort or AirPlay). The Mac's built-in
speakers need no wake-up and keep the controls unavailable. Microphone activity and other playback protections are checked
before signals. Speaker wake-up effectiveness depends on the hardware.

**[Download the latest DMG](https://github.com/franckdpt/keep-my-speakers-awake/releases/latest/download/Keep-My-Speakers-Awake-Apple-Silicon.dmg)** · [Website](https://franckdupont.com/kmsa/)

Open the DMG and drag **Keep My Speakers Awake.app** to Applications. New
public releases require a Developer ID signature and Apple notarization before
publication. Releases through **1.7.10** used a local ad-hoc signature and were
**not Apple notarized**.
The DMG opens in icon view with an app → Applications layout and bilingual
instructions. Then open the copied app from Applications.

### First launch on macOS

For unnotarized releases through 1.7.10, macOS can block the first launch with
“Apple could not verify this app is free of malware”. If you downloaded the
official release here and choose to open it:

1. Copy the app to Applications, try opening it, then dismiss the alert with **Done**.
2. Open **System Settings → Privacy & Security → Open Anyway** for Keep My Speakers Awake.
3. Confirm the request and open the app again.

In French: **Terminé**, puis **Réglages Système → Confidentialité et sécurité → Ouvrir quand même**.
See [Apple's first-launch instructions](https://support.apple.com/102445).
Signing with Developer ID and notarizing the app is required to remove this
unverified-app block for users. The drag-to-Applications layout alone does not do this.

## Build

Requires a Mac, Apple's Command Line Tools and Node.js 24+. No paid dependencies.

```sh
npm test
npm run check:native
npm run build
"output/native/Keep My Speakers Awake.app/Contents/MacOS/KMSA" --self-check
"output/native/Keep My Speakers Awake.app/Contents/MacOS/KMSA" --update-self-check
python3 -m venv output/dmg-tools
output/dmg-tools/bin/python -m pip install -r scripts/dmg-requirements.txt
export KMSA_DMG_PYTHON="$PWD/output/dmg-tools/bin/python"
npm run package:dmg
```

The checks do not play audio. Packaging verifies version/build, minimum macOS,
arm64-only architecture, signature, audio bytes, DMG integrity and the executable
mounted from the DMG, plus Finder's saved icon positions, background and
Applications shortcut. Outputs are in `output/releases/`.

## Publish a version

The app checks for updates at startup and every 12 hours. When an update is
available, a small menu-bar badge and an **Update to x.x.x** button appear.
Clicking the button downloads, verifies and installs the update with progress.
It uses the official GitHub release DMG and manifest, verifies their
SHA-256 digests and app contents, and retains a recovery copy of the previous app.
The update row stays hidden when no update is available; there is no manual
search button or up-to-date message.
Installation still requires a click. No extra update feed or credentials are needed.

1. Update **`version.json`** (version and build together), run the checks, then
   commit and push the source to `main`.
2. Build and notarize locally using the Developer ID workflow in
   [the distribution guide](app-store/DISTRIBUTION.md). Prepare a GitHub draft
   containing the verified DMG, checksum and manifest for that exact commit.
3. Push the matching `vX.Y.Z` tag. GitHub Actions rebuilds and checks the source,
   verifies the draft's Apple signatures, notarization, mounted app and layout,
   then publishes it. The latest download URL stays unchanged. Signing keys and
   Apple authentication credentials are never uploaded to GitHub.

The newest stable semantic version becomes `latest`; an older maintenance tag
cannot replace a newer version. Published assets are never overwritten by a rerun.
Draft failures can be retried. A tag without its prepared notarized draft fails
closed and cannot publish an ad-hoc build.

Every Release must include the fixed asset name:

```text
Keep-My-Speakers-Awake-Apple-Silicon.dmg
```

Also attached: **SHA256SUMS.txt** and **release-manifest.json**, including the
source commit, app version/build, architecture and DMG hash. The website uses
GitHub's `/releases/latest/download/...` link; no website deploy or manual copy is
needed for a new app release. Drafts and prereleases are not download targets.

## Apple distribution

Developer ID signing, Apple notarization and the sandboxed Mac App Store edition
are documented in [app-store/DISTRIBUTION.md](app-store/DISTRIBUTION.md).
The App Store edition excludes the standalone update client and helper.
New public releases require verified Apple signatures and stapled notarization
tickets. Signing keys stay on the release Mac; CI verifies a prepared draft
asset before publishing the matching tag.

## Repository layout

- `native/`: Swift app, playback policy, hardware observation and checks.
- `signals/sub2.wav`: the single active waveform; never regenerated during release.
- `scripts/`: release validation, packaging and publication.
- `version.json`: app version, build and minimum macOS.
- `landing/`: bilingual landing source. `npm ci && npm run build:kmsa` from that
  folder builds it for `/kmsa/`. Hosting stays on the existing website.

This repository is the standalone successor to the native part of
[`keep-my-monitors-awake`](https://github.com/franckdpt/keep-my-monitors-awake).
The legacy browser extension and archived waveform experiments remain there.
