# KMSA for macOS

A standalone menu bar app for macOS 14.2 or later. It does not need Chrome, a
browser extension, a server, a microphone recording permission, or an account.
It never changes the Mac's volume or chosen output. Speaker wake-ups work offline.
Update checks contact GitHub at app startup and every 12 hours while the app runs;
downloads/installations require a click. There is no account, telemetry or upload.

Version 1.1.0 adds camera-activity protection, blocks manual tests while smart
capture protection is active, and adds a persistent manual **Pause visio**.
Version 1.1.1 replaces the menu bar volume-horn symbol with a vertical hi-fi
speaker: outlined when paused, filled when automatic signals or playback are
active. The panel header uses the same speaker shape.
Version 1.1.2 adds a dot to the menu-bar icon when the current jack connection
needs an answer. Choose **Oui** or **Non** under **Ce sont des enceintes ?** to
clear it. Both choices remain visible and can be changed at any time; **Non**
blocks all signals, including Test.
Version 1.1.3 simplifies the panel: a jack icon and **Ce sont des enceintes ?**
replace the device label, routine status messages and signal descriptions are
removed, and Smart Mode details are available as a bulleted tooltip on its info
icon. The next-check countdown still updates every second.
Version 1.1.4 keeps automatic signals eligible while another app plays quietly:
output audio pauses them only when the Mac's jack volume is at least 50% (or
cannot be read). Microphone, camera, and meeting protections remain in place.
Version 1.1.5 refines the jack icon into an upright filled plug with a shaped tip,
two insulating rings, a rounded grip and a short cable.
Version 1.1.6 removes signal selection and ships only **20 Hz ×2 · expérimental**,
the signal Franck reports working on his speakers. Legacy selections are ignored.
Other waveforms and their parameters remain documented in [SIGNAL-ARCHIVE.md](SIGNAL-ARCHIVE.md)
and preserved in the repository for future experiments. The black jack icon is
traced directly from the supplied image and rotated upright without stretching.
Version 1.1.7 replaces the notification dot with a small question mark placed
closer to the speaker, shown only while an answer is pending.
Version 1.1.8 places the **Prochain dans…** countdown beside the automatic-signal
switch, reduces the jack icon, and moves the login toggle below meeting pause.
The divider now separates only the version/Quit footer.
Version 1.1.9 shows only minutes and seconds next to the automatic-signal switch.
Version 1.1.10 replaces the panel's jack with the supplied SVG, oriented horizontally.
Version 1.1.11 puts speaker confirmation first and reveals settings only after Yes.
The panel speaker is green after Yes, black otherwise. The menu-bar speaker is
crossed out while automatic signals are off or speakers remain unconfirmed.
Manual meeting pause is removed, including its saved value; microphone/camera
activity blocks signals only while active (or unknown). The two-minute grace
period now applies only to output audio at 50% or above (or unknown volume).

Version 1.1.12 keeps the app title and speaker above the question in every state.
Panel text, jack and the unconfirmed speaker use a softer anthracite (#48484A),
with a lighter equivalent in dark mode. A confirmed speaker remains green.

Version 1.1.13 uses microphone activity alone to block signals, including Test,
even with Smart Mode disabled. Camera activity does not affect playback.

Version 1.2.0 renames the app to **Keep My Speakers Awake (KMSA)**, including
its executable, Swift modules and distribution bundle. The bundle identifier
stays stable to preserve existing preferences and macOS permissions. The installed
app and its enabled login item move to `Keep My Speakers Awake.app`.

Version 1.2.1 replaces the speaker-question card with “no device detected”
when no eligible jack output is detected. The app header remains visible.

Version 1.3.0 pauses automatic signals after one minute without keyboard/mouse
input when no other process is playing on the selected jack. Passive listening
at low volume remains eligible. Yes and switching Auto from off to on request
one immediate signal; microphone, route/session, output-volume and activity
protections still apply. Yes may send this first signal while Auto is off.
Subsequent automatic signals follow the ten-minute interval. Verification and
previews use in-memory players and never emit these new immediate signals.

Version 1.4.0 extends inactivity to five minutes. The first keyboard/mouse input
after that idle period requests one immediate signal when Auto and Smart Mode
are enabled, even without output audio; all existing playback protections apply.
It then restarts the ten-minute schedule. Continuous input does not repeat this
return signal. A microphone-blocked return is discarded, never queued for later.

Version 1.4.1 disables and dims the Smart Mode control while Auto is off,
preserving its stored choice for the next Auto activation.

Version 1.4.2 keeps a single Test/Stop button in place: its label and action
switch to Stop during any signal playback, including automatic signals.

Version 1.5.0 removes the speaker question, Yes/No choices and menu-bar question
mark. A detected built-in jack makes the controls and Test available immediately.
When Auto is on, selecting or reconnecting the jack requests a signal on the next
check. Disconnecting stops playback and shows **Pas de connexion jack détectée**.
The saved Auto choice and existing microphone/Smart Mode protections still apply.

Version 1.5.1 moves the Auto switch to the right of the app title and removes
its visible label and countdown. The panel speaker is green only when Auto is
on and a jack is detected; otherwise it is anthracite. The **Tester le réveil**
button changes to **Arrêter le test** only during a manually started test.
Automatic playback, including the signal sent on activation, keeps the test
button available. Clicking it during automatic playback starts a manual test.

Version 1.5.2 renames the volume control to **Volume du réveil**, including its
accessibility label, and centers the menu-bar speaker and its paused-state slash
within the icon after removal of the question badge.

Version 1.5.3 removes the connected-jack row while retaining the disconnected
message. Smart Mode help uses wake terminology and opens immediately as a
popover when its info button is clicked; hover help remains available. The info
button remains usable when Auto is off and does not change Smart Mode.

Version 1.6.0 uses French when the Mac's primary preferred language is French
(including regional variants), and English for every other primary language.
Controls, help, accessibility labels, status and app error messages share the same
bilingual catalog. A secondary French preference does not override another primary
language. The app name stays **Keep My Speakers Awake**. Restart the app after
changing the Mac language; no language preference is written by the app.

Version 1.6.1 labels the Smart Mode option as recommended in both languages.

Version 1.6.2 makes the recommended suffix smaller and gray beside Smart Mode
in both languages, retaining the full accessible option label.

Version 1.6.3 places the info button between Smart Mode and its recommended
suffix, and renames the French login option to **Ouvrir avec la session**.

Version 1.6.4 gives the login option the same text size as Smart Mode.

Version 1.6.5 preserves absence through screen sleep and session locking, so the
first input after a long absence can request the return signal instead of waiting
ten minutes. Duplicate wake notifications do not repeat it. Existing playback
protections still apply; blocked return signals are discarded. Adds local rotating
diagnostics and a **Show logs / Afficher les logs** footer button.

Version 1.6.6 replaces the log-access button with a GitHub link for stars, issues
and source code, and follows the repository rename to `keep-my-speakers-awake`.

Version 1.6.8 renames the slider to **Puissance du réveil / Wake-up strength**,
places **• GitHub ↗** directly after the version, and rounds the menu-bar panel
to a continuous 20-point corner while retaining the native material and shadow.

Version 1.7.0 adds **Rechercher une mise à jour… / Check for Updates…**. When a
new stable GitHub release is available, **Installer et relancer / Install and
Relaunch** downloads, verifies and replaces the app in its current Applications
folder. Saved settings and the bundle identifier stay unchanged.

Version 1.7.1 checks for updates at startup (including login when Open at login is
enabled), then every 24 hours. A small menu-bar speaker badge indicates an
available update. The panel explicitly confirms when KMSA is up to date.

Version 1.7.2 uses one compact, fixed-height footer slot: **Chercher une mise à
jour / Check for Updates**, **Mettre à jour vers x.x.x / Update to x.x.x**, real
download progress, then **KMSA est à jour / KMSA is up to date**. Clicking the
versioned update button starts installation directly. Verification and restart
use an indeterminate bar. A recent successful-install receipt preserves the
completion message after relaunch and schedules the next check for 24 hours later.

Version 1.7.4 keeps a compact **Chercher une mise à jour / Check for Updates**
button beside the up-to-date status so a manual recheck is always accessible.

Version 1.7.5 shows **L’app est à jour / The app is up to date** only after a
successful check or installation. The version-specific confirmation expires after
24 hours, survives relaunches without extending the expiry, and is invalidated by
a failed check or detected update. The manual search button is slightly larger.

Version 1.7.6 shows the remaining manual-test seconds beside **Arrêter le test /
Stop test**, based on the player's actual position. The up-to-date checkmark is
green. Silent update checks run every 12 hours; the confirmation message still
has an independent 24-hour lifetime.

Version 1.7.7 keeps the panel's top six points below the menu bar when its
content height changes, including after disconnecting the jack. The panel uses
its content's natural height instead of retaining extra vertical space.

Version 1.7.8 shows the pointing-hand cursor over the panel's GitHub link.

Version 1.7.9 uses a native GitHub link button that owns both click and hover
events. It restores the hand cursor on mouse movement, including in an inactive
menu-bar panel, and resets the cursor when leaving or removing the link.

Version 1.7.10 renders the GitHub label with the same SwiftUI caption size and
secondary color as the adjacent KMSA version, retaining native hover and clicks.

## In-app updates

Update checks run at app startup and every 12 hours, with a manual check available
at any time. Sleep/session-return notifications run a due check; repeated
notifications do not duplicate requests. A failed check retries after one hour,
keeps any previously detected update badge and never claims the app is up to date.
The app owns the updater even while the panel is closed. Automatic checks show no
modal alerts and never install updates. The updater uses the public GitHub API without a token,
rejects drafts/prereleases/downgrades and requires both a newer semantic version
and a higher build. It validates the manifest and archive against GitHub's SHA-256
asset digests, then checks macOS compatibility, bundle identity, version/build,
ad-hoc code-signature integrity, arm64 architecture and the unchanged wake signal.
This trusts HTTPS and the official GitHub release account; the current release
format does not provide a separate developer signing key or Apple notarization.

The app must run from `/Applications/Keep My Speakers Awake.app` or the same name
under `~/Applications`, with write access to that folder. Read-only DMGs and
translocated apps are refused. No elevated helper or security-setting changes are
used. A bundled, signed helper waits for the app to exit, revalidates the candidate,
and replaces it using same-volume directory moves. It restores the previous app if
verification/replacement fails, then relaunches. The previous bundle remains in a
private `.kmsa-update-*` sibling folder as a recovery copy. The saved Auto, strength,
Smart Mode and login settings are never rewritten by the updater.

The existing tag/release workflow already supplies the required fixed-name DMG,
`release-manifest.json` and GitHub digests. No extra feed, signing secret or hosted
service is needed. Verify a real release without installing or playing audio:

```sh
"output/native/Keep My Speakers Awake.app/Contents/Helpers/KMSAUpdateInstaller" \
  --verify-latest signals/sub2.wav
```

## Build and open

From the repository root, with Apple's Command Line Tools and Node.js installed:

```sh
node native/scripts/build.mjs
xcrun swift run --package-path native KMSAChecks
```

The build creates `output/native/Keep My Speakers Awake.app` and a ZIP copy. It includes a local
ad-hoc signature, not an Apple Developer ID distribution signature. The script
checks the bundle signature and verifies that the single packaged WAV is
byte-identical to `signals/sub2.wav`.
The bundle targets the architecture of the Mac used to build it; this is not a
universal Intel/Apple Silicon distribution build.

Open the app from Finder. Its controls appear under the speaker icon in the menu
bar; there is no Dock icon or main window. For permanent use, copy the app to
Applications before enabling **Ouvrir à la connexion**.

## First use

1. The first launch is **paused**, with **20 Hz ×2** as the only signal and volume
   at 100%. Existing Chrome settings are not imported or modified.
2. Keep the Mac's current output volume. Connect the jack and select it as the
   Mac's audio output.
3. The app detects the jack automatically; no speaker confirmation is needed.
   Without an eligible jack output, it shows **Pas de connexion jack détectée**.
4. Pause the Chrome extension before testing or enabling the native app, to
   avoid two independent schedules sending signals.
5. Click **Tester le réveil** to try the existing six-second waveform. Check both
   Focal monitors, audibility, and wake-up from standby on the actual hardware.
6. Enable the switch to the right of the app title to request a signal immediately. The next
   automatic signal is due ten minutes after a successful playback. A blocked
   scheduled signal waits for eligibility instead of postponing another ten minutes.

The signal volume and Auto choice are saved locally. The waveform is fixed to
`sub2`; older profile preferences are ignored. Any device on the selected analog
jack is eligible, including headphones. Detection does not establish whether the
connected device is a speaker or whether it is powered on. Reconnecting or changing
to the jack requests a signal when Auto is enabled, subject to playback protections.

## Output and session protection

Only an available built-in analog headphone/line output can qualify. The driver
must identify it by transport and audio-stream terminal type or selected analog
data source (including Apple's legacy IOAudio types); labels alone are
never used to authorize playback. An explicitly disconnected jack is rejected.
If the driver does not expose a jack control, its built-in analog stream identity
is used instead. USB, Bluetooth, AirPlay, HDMI, aggregate devices, and internal
speakers are not authorized in this first version.

Before playback the app checks the active route and session again, binds the
player to that device UID, and verifies the binding. Routing notifications stop
playback and refresh jack detection. Fresh checks every second also catch
missed notifications. This reduces the risk of fallback playback; physical
unplug/replug and route-change behavior still need testing on the real Mac.
The tests verify the decision policy, not the driver's timing during hot unplug.

The app pauses on session deactivation, screen sleep, system sleep, or lock
notifications. It checks the console-session state before playing as well.
Sleep/resume discards delayed timers rather than playing missed signals.
After 300 seconds without keyboard/mouse input and no output audio, Smart Mode
pauses automatic signals. Output audio at low volume keeps passive listening eligible.
The app queries elapsed input time without reading keys or mouse coordinates.
The first input after a known five-minute idle period requests an immediate
signal with Auto and Smart Mode enabled. It is detected by the one-second polling
loop. Unknown input readings do not establish a return. A known idle state survives
screen sleep/locking. A session unavailable for at least five minutes also
establishes absence; the next available session with recent input requests one
return signal. Waking in the background without fresh input does not trigger it.

## Native smart mode

On every check (about once a second), Core Audio process activity is read
without recording audio:

- Another process running output on the selected jack blocks automatic signals
  only when the Mac's output volume is **50% or higher**, or cannot be read.
  Below 50%, output activity does not block signals or extend the grace period.
  The output setting is read every second without changing it. When only stereo
  channel controls are available, both must reach 50% before audio suppresses
  the keep-awake signal.
- Another process running an audio input blocks both automatic signals and
  manual Test, even with smart mode disabled, including calls/recordings outside
  the browser. All processes are checked, even if another one is using output.
- Camera activity does not block signals.
- No input for at least 300 seconds plus no output audio pauses automatic signals.
  The explicit Test button bypasses inactivity; microphone protection always applies.
- A two-minute grace period follows output audio at 50% or higher (including
  unknown volume). Stopping microphone use adds no delay. Lowering the volume stops
  extending this grace period; a previously started grace period can still end.
  With music still playing below 50%, signals become eligible automatically
  after that grace period and run at the next due check.
- Unknown microphone state blocks all signals, including Test, even with smart
  mode disabled.

This is a conservative **audio I/O activity** check, not an audibility meter.
The 50% rule is a heuristic based on the Mac's volume setting, not a measurement
of the app's own volume, actual waveform, or the speakers' standby threshold.
Some apps keep silent audio streams open and can still block signals when the
Mac's volume is at least 50%. The app excludes its own audio process from this
check. Muted output is treated as zero volume; this does not make a muted signal
audible to the speakers.

The native app uses current microphone activity, not meeting identity.
Once the microphone stops, its block clears immediately. Existing output-audio
rules and the normal ten-minute schedule still apply. Camera activity and
camera-driver availability do not participate in playback decisions.
The app does not request microphone recording access or listen to audio.

Manual **Test** still bypasses the output-audio and two-minute grace checks,
but never bypasses the physical-output/session gate or microphone protection.
Real microphone activity during calls still needs hardware verification;
injected-state checks establish the playback-policy behavior.

## Local debug history

The running menu-bar app writes JSON lines to
`~/Library/Logs/Keep My Speakers Awake/diagnostics.jsonl` automatically. The footer's
small document button opens the folder. Three rotated archives are retained, each
file limited to about 2 MiB (about 8 MiB total); retention depends on event volume.
Nothing is uploaded. Logs contain timestamps in UTC, a launch ID/version/PID,
Auto/Smart settings, jack eligibility, session state, elapsed input idle time,
microphone/output activity, Mac and signal volume, current blocking reason,
next deadline and last signal time. They contain no keystrokes, mouse coordinates,
audio recordings or names of other applications.

State changes and sleep/lock/wake notifications are recorded immediately; a
heartbeat records the current decision once a minute while the app is running.
Signal requests include their source (`presence_return`, `auto_enabled`,
`scheduled`, `manual_test`), blocks and player errors. Start/finish/interruption
are separate events: a successful player call cannot prove the physical speakers
woke. A heartbeat gap can mean sleep, process termination or stalled scheduling;
compare surrounding session events and macOS power logs. Previews and self-checks
use disabled or temporary loggers and never pollute production history.

## Diagnostics without sound

```sh
"output/native/Keep My Speakers Awake.app/Contents/MacOS/KMSA" --diagnose
```

This prints the current route, jack eligibility, Core Audio activity state,
Mac output volume, input idle duration, whether output audio requires a pause, camera running metadata, and
packaged profile availability. It does not launch the menu bar app or play audio.
Device UIDs in this output are local identifiers; no diagnostics are uploaded.

The executable also accepts `--self-check`: it checks the real model's paused
defaults, automatic jack detection, packaged audio decoding, scheduling, and device
binding without starting playback or changing the user's saved preferences.
It also injects active/unknown/idle microphone states with Smart Mode on and off
to check blocking and immediate recovery without starting actual capture.
Injected low/threshold/unknown volume checks verify quiet playback stays eligible
without extending the grace period, and 50% starts the automatic-output pause.
`KMSAChecks` runs the independent policy, classification and localization checks without a full
Xcode installation or XCTest dependency.

## Source layout

- `Sources/KMSACore`: playback decision policy, tested independently of hardware.
- `Sources/KMSA`: SwiftUI controls, Core Audio observation, AVAudioPlayer playback,
  and Service Management login-item integration.
- `scripts/build.mjs`: copies only the active `sub2` waveform, compiles Swift, and creates
  the app bundle. Generated audio copies and build output are ignored by Git.

The Chrome extension remains available separately. Running one app is sufficient;
the native app does not silently disable or uninstall the extension.
