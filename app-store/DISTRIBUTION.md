# Apple distribution

The stable bundle identifier is `fr.franckdupont.kmma.native`, Apple team
`SRGS2S4PV9`. Public downloads remain at GitHub's fixed latest DMG URL.

## Developer ID release

Run on the release Mac with its private signing identity and a `notarytool`
Keychain profile named `KMSA`. Never put private keys, app-specific passwords,
provisioning profiles or notarization logs in this repository. Certificates and
private keys are kept outside the checkout in the Mac's Keychain and a protected
local signing directory. Creating an Apple app-specific password is a user step;
enter it in Apple's interactive `notarytool store-credentials` prompt.

1. Run `npm test` and `npm run check:native`.
2. Build and run the two no-audio checks:

```sh
export KMSA_DISTRIBUTION=developer-id
export KMSA_SIGN_IDENTITY='Developer ID Application: Franck Dupont (SRGS2S4PV9)'
export KMSA_NOTARY_PROFILE=KMSA
npm run build
"output/native/Keep My Speakers Awake.app/Contents/MacOS/KMSA" --self-check
"output/native/Keep My Speakers Awake.app/Contents/MacOS/KMSA" --update-self-check
```

3. Commit and push the verified source to `main`. Packaging requires a clean
   checkout so the manifest identifies the exact source commit.
4. Prepare the isolated Python environment described in the root README, then
   run `npm run package:dmg`. This notarizes a clean staging copy of the app,
   staples its ticket, creates and signs the DMG, notarizes and staples the DMG,
   and verifies Gatekeeper, the mounted app, signal bytes and saved Finder layout.
   The manifest and SHA-256 are written only after all these checks pass.
5. Verify and prepare the draft before pushing the tag:

```sh
export KMSA_EXPECTED_TAG="v$(node -p 'require("./version.json").version')"
node scripts/verify-release.mjs
GITHUB_REPOSITORY=franckdpt/keep-my-speakers-awake \
GITHUB_REF_NAME="$KMSA_EXPECTED_TAG" \
GITHUB_SHA="$(git rev-parse HEAD)" KMSA_DRAFT_ONLY=1 npm run publish:release
git tag "$KMSA_EXPECTED_TAG"
git push origin "$KMSA_EXPECTED_TAG"
```

The existing scoped `GITHUB_TOKEN` handles CI publication. No signing key or Apple
credential is stored in GitHub. CI downloads the draft, validates the source
revision, checksum, Apple signatures, tickets, mounted bundle and Finder layout,
then publishes. Missing or ad-hoc drafts fail closed. Existing published assets
are never replaced.

Apple acceptance, stapling and Gatekeeper assessment are separate required steps.
A valid Developer ID signature alone must never be described as notarized.

## Mac App Store edition

App Store Connect app ID: `6831124285`.

`npm run build:app-store` creates an ad-hoc, sandboxed development build in
`output/native-app-store/`. Run its `--self-check` and `--update-self-check` before
signing. `npm run screenshots:app-store` renders the same native controls without
audio and exports three opaque 2880 × 1800 JPEGs per locale.

For the upload build, set `KMSA_DISTRIBUTION=app-store`,
`KMSA_SIGN_IDENTITY` to the Mac App Distribution identity and
`KMSA_PROVISIONING_PROFILE` to the locally downloaded Mac App Store profile, then
run `npm run build`. Set `KMSA_INSTALLER_IDENTITY` to the Mac Installer
Distribution identity and run `npm run package:app-store`.

Packaging validates the Apple chain, team, store certificate type, version,
provisioning profile, sandbox entitlements and absence of the installer helper,
then produces the signed Apple installer package in `output/app-store/`.
Store-signed apps must be tested through Apple's distribution path (Transporter /
TestFlight / App Store); the script does not bypass macOS's execution policy.

For command-line uploads, use the official `altool` bundled with Transporter.
An App Store Connect team API key with the Developer role can validate and upload
the package. API activation, its terms and key creation require the account
holder's authorization. Team keys cover every app in the account. Keep the
private `.p8` outside the checkout, readable only by its owner, and include it
only in the separately encrypted off-Mac backup. Never add it to GitHub.

Set `KMSA_APPSTORE_KEY_ID`, `KMSA_APPSTORE_ISSUER_ID` and
`KMSA_APPSTORE_PRIVATE_KEY` locally, then run:

```sh
"/Applications/Transporter.app/Contents/Frameworks/ContentDelivery.framework/Versions/A/Resources/altool" \
  --validate-app output/app-store/Keep-My-Speakers-Awake.pkg \
  --api-key "$KMSA_APPSTORE_KEY_ID" --api-issuer "$KMSA_APPSTORE_ISSUER_ID" \
  --p8-file-path "$KMSA_APPSTORE_PRIVATE_KEY" --output-format json
"/Applications/Transporter.app/Contents/Frameworks/ContentDelivery.framework/Versions/A/Resources/altool" \
  --upload-package output/app-store/Keep-My-Speakers-Awake.pkg \
  --api-key "$KMSA_APPSTORE_KEY_ID" --api-issuer "$KMSA_APPSTORE_ISSUER_ID" \
  --p8-file-path "$KMSA_APPSTORE_PRIVATE_KEY" --wait --output-format json
```

Wait for successful Apple processing before selecting the build and submitting
the version for App Review. The API key is separate from the `KMSA` notarization
Keychain profile used for direct downloads.

The `APP_STORE` compilation flag excludes the standalone updater and installer
UI. No network or microphone/camera capture entitlement is requested. Audio
activity and idle observations remain local; unknown activity still blocks
signals. Physical jack, microphone, sleep/wake and opt-in login behavior require
device validation separately from the no-audio policy checks.

The source metadata is in `fr-FR.json`, `en-US.json`, `review-notes.txt` and
`PRIVACY.md`. Publish the privacy-policy URL before App Review submission.
Confirm review contact details and the user's EU trader status before filling
those personal/legal declarations. A prepared or uploaded package is not an
approved or published App Store app.
