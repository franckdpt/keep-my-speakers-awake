# KMSA development

- Canonical repository: `franckdpt/kmsa`, branch `main`. This is the standalone native app and landing, separate from the legacy browser extension repository.
- Preserve microphone/route/session/output-volume/presence protections. Hardware behavior is distinct from policy checks. Never emit audio during automated verification.
- `version.json` is the single version source. Increase version and build together; release tags must equal `v<version>`.
- Apple Silicon only for current releases. Preserve the bytes of `signals/sub2.wav` and the stable bundle identifier.
- Run `npm test`, `npm run check:native`, `npm run build`, then the built executable's `--self-check` for native changes.
- DMGs are release assets, not committed binaries. Only publish after checks, DMG verification and manifest validation pass. Never replace assets of a published release.
- Landing download always uses `https://github.com/franckdpt/kmsa/releases/latest/download/Keep-My-Speakers-Awake-Apple-Silicon.dmg`. Asset name stays constant; an older version must not replace a newer latest release.
- Do not add Forge tokens, signing keys, certificates, local logs, private deployment evidence or user data to this public repository. No new API secrets are needed by the release workflow; use its scoped GITHUB_TOKEN.
- Keep the selected white single-screen landing, clean Focal/KRK frontal composition, small EN / FR control, readable secondary text and one download button. The user removed the app preview: do not reintroduce it.
- Existing distribution is ad-hoc signed, not notarized. Do not claim Developer ID signing/notarization without actually configuring and verifying it.
