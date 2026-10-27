# Keep My Speakers Awake

A tiny Mac app that prevents speaker standby.

Native menu bar utility for **Apple Silicon**, **macOS 14.2+**, with automatic
French / English copy. Uses a low-frequency signal on the Mac's built-in analog
jack output. Microphone activity and other playback protections are checked
before signals. Speaker wake-up effectiveness depends on the hardware.

**[Download the latest DMG](https://github.com/franckdpt/kmsa/releases/latest/download/Keep-My-Speakers-Awake-Apple-Silicon.dmg)** · [Website](https://franckdupont.com/kmsa/)

Open the DMG and drag **Keep My Speakers Awake.app** to Applications. Current
releases use a local ad-hoc signature and are **not Apple notarized**.

## Build

Requires a Mac, Apple's Command Line Tools and Node.js 24+. No paid dependencies.

```sh
npm test
npm run check:native
npm run build
"output/native/Keep My Speakers Awake.app/Contents/MacOS/KMSA" --self-check
npm run package:dmg
```

The checks do not play audio. Packaging verifies version/build, minimum macOS,
arm64-only architecture, signature, audio bytes, DMG integrity and the executable
mounted from the DMG. Outputs are in `output/releases/`.

## Publish a version

1. Update **`version.json`**: increase `version` and `build`. This is the source of
   truth for the app bundle and menu-bar version label.
2. Commit and push the app changes to `main`.
3. Push the matching tag, for example:

   ```sh
   git tag v1.6.6
   git push origin v1.6.6
   ```

GitHub Actions builds on an Apple Silicon runner, runs the checks and creates
the DMG. A draft Release is prepared, all verified assets are uploaded, then the
Release is published. The newest stable semantic version becomes `latest`; an
older maintenance tag cannot replace a newer version. Published assets are never
overwritten by a rerun. Draft failures can be retried.

Every Release must include the fixed asset name:

```text
Keep-My-Speakers-Awake-Apple-Silicon.dmg
```

Also attached: **SHA256SUMS.txt** and **release-manifest.json**, including the
source commit, app version/build, architecture and DMG hash. The website uses
GitHub's `/releases/latest/download/...` link; no website deploy or manual copy is
needed for a new app release. Drafts and prereleases are not download targets.

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
