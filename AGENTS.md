# KMSA development

- Canonical repository: `franckdpt/keep-my-speakers-awake`, branch `main`. This is the standalone native app and landing, separate from the legacy browser extension repository.
- Preserve microphone/route/session/output-volume/presence protections. Hardware behavior is distinct from policy checks. Never emit audio during automated verification.
- `version.json` is the single version source. Increase version and build together; release tags must equal `v<version>`.
- Apple Silicon only for current releases. Preserve the bytes of `signals/sub2.wav` and the stable bundle identifier.
- Run `npm test`, `npm run check:native`, `npm run build`, then the built executable's `--self-check` for native changes.
- DMGs are release assets, not committed binaries. Only publish after checks, DMG verification and manifest validation pass. Never replace assets of a published release.
- Landing download always uses `https://github.com/franckdpt/keep-my-speakers-awake/releases/latest/download/Keep-My-Speakers-Awake-Apple-Silicon.dmg`. Asset name stays constant; an older version must not replace a newer latest release.
- Do not add Forge tokens, signing keys, certificates, local logs, private deployment evidence or user data to this public repository. No new API secrets are needed by the release workflow; use its scoped GITHUB_TOKEN.
- Keep the selected white single-screen landing, clean Focal/KRK frontal composition, small EN / FR control, readable secondary text and one download button. The user removed the app preview: do not reintroduce it.
- Keep a discreet GitHub link alongside the language switch and a short localized drag-to-Applications hint below the download. DMGs use the clean app → Applications Finder layout, bilingual instructions and Retina background; verify the mounted image's actual saved layout.
- Existing distribution is ad-hoc signed, not notarized. Do not claim Developer ID signing/notarization without actually configuring and verifying it.
- The native panel footer links to the GitHub repository for stars, issues and source code. The user removed the logs-access button; do not reintroduce it. Internal diagnostics remain separate from this UI choice.
- Landing SEO is pre-rendered at build time: English root and `/kmsa/fr/`. Preserve static localized metadata, canonical/hreflang, actual HTML content, WebPage JSON-LD and sitemap; do not regress to an empty app shell. OG image is 1200 × 630 at `landing/public/social/kmsa-og-v1.jpg`, separate from the visible hero. Run the landing build/SEO validator and check language navigation/hydration after changes.
