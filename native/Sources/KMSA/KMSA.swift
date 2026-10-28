import AppKit
import SwiftUI
import KMSACore
import AVFAudio
import ServiceManagement
import Dispatch

@main
@MainActor
enum EntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--update-self-check") {
            Task { @MainActor in
                await UpdateModel.runChecks()
                exit(0)
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--language-check") {
            let report: [String: Any] = [
                "language": L10n.language.rawValue,
                "preferredLanguages": Locale.preferredLanguages,
                "text": Dictionary(uniqueKeysWithValues: AppText.allCases.map { ($0.rawValue, L10n.text($0)) }),
            ]
            let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return
        }
        // Used when moving an already-enabled installation to Applications.
        if CommandLine.arguments.contains("--relocate-login-item") {
            do {
                try SMAppService.mainApp.unregister()
                try SMAppService.mainApp.register()
                guard SMAppService.mainApp.status == .enabled else {
                    print(L10n.text(.loginApproval))
                    exit(1)
                }
                print("\(L10n.text(.relocationSuccess)) \(Bundle.main.bundleURL.path).")
            } catch {
                print(L10n.text(.relocationFailed))
                exit(1)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > index + 1 {
            let suite = "fr.franckdupont.kmsa.preview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            _ = NSApplication.shared
            let model = AppModel(defaults: defaults,
                                readRoute: { CommandLine.arguments.contains("--no-device") ? HAL.Route() : HAL.Route(device: 0, uid: "preview-jack", name: "Jack de prévisualisation", isJack: true, alive: true) },
                                readAudio: { _ in HAL.Activity(known: true, microphoneBusy: false, outputBusy: false) },
                                readOutputVolume: { _ in 0.25 }, readIdleSeconds: { 0 },
                                makePlayer: { _ in let player = SilentCheckPlayer(); player.onPlay = { true }; return player })
            if CommandLine.arguments.contains("--automatic") { model.enabled = true }
            if CommandLine.arguments.contains("--test") { model.testSignal() }
            else if !CommandLine.arguments.contains("--playing") { model.stop() }
            model.refresh()
            let panel = Group {
                if CommandLine.arguments.contains("--help-content") { SmartModeHelp() }
                else {
                    ControlPanel(model: model, updater: UpdateModel.preview(
                        available: CommandLine.arguments.contains("--update-available"),
                        searching: CommandLine.arguments.contains("--update-search"),
                        downloading: CommandLine.arguments.contains("--update-progress")))
                }
            }.environment(\.locale, L10n.locale)
                .background(Color(nsColor: .windowBackgroundColor))
            let view = NSHostingView(rootView: panel)
            let size = view.fittingSize
            view.frame = NSRect(origin: .zero, size: size)
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            print("Rendered native controls without starting playback.")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--preview-icons"), CommandLine.arguments.count > index + 1 {
            _ = NSApplication.shared
            let preview = NSImage(size: NSSize(width: 128, height: 32), flipped: false) { _ in
                NSColor.white.setFill()
                NSRect(x: 0, y: 0, width: 128, height: 32).fill()
                for (index, state) in [(false, false), (true, false), (false, true), (true, true)].enumerated() {
                    MenuBarIcon.image(active: state.0, updateAvailable: state.1)
                        .draw(in: NSRect(x: index * 32 + 5, y: 6, width: 22, height: 20))
                }
                return true
            }
            let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
            try! bitmap.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            print("Rendered paused/active menu-bar icons with and without an update badge. No audio played.")
            return
        }
        if CommandLine.arguments.contains("--self-check") {
            let suite = "fr.franckdupont.kmsa.check.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set("ultrasonic4", forKey: "profile") // Old choices must not reactivate archived signals.
            let model = AppModel(defaults: defaults, readRoute: { HAL.Route() },
                                 makePlayer: { _ in SilentCheckPlayer() })
            precondition(!model.enabled && !model.playing && !model.canTest)
            precondition(model.profileID == "sub2" && model.volume == 1 && model.smartMode)
            precondition(model.profiles.count == 1 && model.profiles.first?.id == "sub2")
            precondition(AppModel.resource("ultrasonic4", ext: "wav") == nil)
            for profile in model.profiles {
                let url = AppModel.resource(profile.id, ext: "wav")!
                let file = try! AVAudioFile(forReading: url)
                precondition(file.processingFormat.channelCount == 2)
                precondition(file.processingFormat.sampleRate == 48_000 && file.length == 288_000)
            }
            model.enabled = true
            precondition(!model.playing && model.nextDue.timeIntervalSinceNow > 590)
            model.testSignal() // No jack must block playback before any player is created.
            precondition(!model.playing && model.route.jackUID == nil)
            precondition(model.message == "\(L10n.text(.wakeBlocked)): \(L10n.text(.noJack))")
            model.enabled = false
            var simulatedAudio = HAL.Activity(known: true, microphoneBusy: false, outputBusy: false)
            var simulatedRoute = HAL.Route(device: 0, uid: "check-jack", name: "Jack de test", isJack: true, alive: true)
            var simulatedVolume: Double? = 0.0625
            let protectedModel = AppModel(defaults: defaults, readRoute: { simulatedRoute },
                                          readAudio: { _ in simulatedAudio }, readOutputVolume: { _ in simulatedVolume },
                                          readIdleSeconds: { 0 }, makePlayer: { _ in SilentCheckPlayer() })
            if protectedModel.sessionAvailable {
                precondition(protectedModel.canTest && protectedModel.route.jackUID == "check-jack")
                simulatedRoute.uid = "another-check-jack"
                protectedModel.refresh()
                precondition(protectedModel.canTest)
                simulatedRoute = HAL.Route()
                protectedModel.refresh()
                precondition(!protectedModel.canTest)
                protectedModel.testSignal()
                precondition(!protectedModel.playing)
                simulatedRoute = HAL.Route(device: 0, uid: "check-jack", name: "Jack de test", isJack: true, alive: true)
                protectedModel.refresh()
                precondition(protectedModel.canTest)
                print("Jack detection: connected and reconnected routes are eligible without confirmation; unplug blocks Test. No audio played.")
                protectedModel.enabled = true
                simulatedAudio.outputBusy = true
                protectedModel.refresh()
                precondition(protectedModel.block == nil && protectedModel.canTest)
                protectedModel.refresh()
                precondition(protectedModel.block == nil) // Low-volume audio must not refresh the grace period.
                simulatedVolume = 0.499
                protectedModel.refresh()
                precondition(protectedModel.block == nil)
                simulatedVolume = 0.5
                protectedModel.refresh()
                precondition(protectedModel.block == .audioInUse && protectedModel.canTest)
                simulatedVolume = nil
                protectedModel.refresh()
                precondition(protectedModel.block == .audioInUse)
                simulatedVolume = 0.0625
                protectedModel.refresh()
                precondition(protectedModel.block == .recentAudio)
                simulatedAudio.outputBusy = false
                protectedModel.enabled = false
                print("Smart output checks passed: quiet playback below 50% stays eligible without adding grace, 50%/unknown blocks automatic signals, Test remains available. No audio played.")
                defaults.set(true, forKey: "meetingPause") // A former saved pause must not block the new version.
                let captureModel = AppModel(defaults: defaults, readRoute: { simulatedRoute },
                                            readAudio: { _ in simulatedAudio }, readOutputVolume: { _ in simulatedVolume },
                                          readIdleSeconds: { 0 }, makePlayer: { _ in SilentCheckPlayer() })
                captureModel.enabled = true
                precondition(defaults.object(forKey: "meetingPause") == nil && captureModel.block == nil)
                for smart in [true, false] {
                    captureModel.smartMode = smart
                    simulatedAudio.microphoneBusy = true
                    captureModel.refresh()
                    precondition(captureModel.captureState == .microphone && captureModel.block == .microphoneInUse && !captureModel.canTest)
                    captureModel.testSignal()
                    precondition(!captureModel.playing)
                    simulatedAudio.microphoneBusy = false
                    simulatedAudio.known = false
                    captureModel.refresh()
                    precondition(captureModel.captureState == .unknown && !captureModel.canTest)
                    simulatedAudio.known = true
                    captureModel.refresh()
                    precondition(captureModel.captureState == .clear && captureModel.canTest && captureModel.block == nil)
                }
                print("Active or unknown microphone blocks all signals with Smart Mode on or off; clearing it restores eligibility immediately. No audio played.")
            }
            defaults.set(false, forKey: "enabled")
            defaults.set(true, forKey: "smartMode")
            var idle: TimeInterval? = 0
            var signalStarts = 0
            var createdPlayers = 0
            var activateMicrophoneDuringPreparation = false
            simulatedAudio = HAL.Activity(known: true, microphoneBusy: false, outputBusy: false)
            simulatedVolume = 0.25
            let triggerModel = AppModel(defaults: defaults, readRoute: { simulatedRoute },
                                        readAudio: { _ in simulatedAudio }, readOutputVolume: { _ in simulatedVolume },
                                        readIdleSeconds: { idle }, makePlayer: { _ in
                                            createdPlayers += 1
                                            let player = SilentCheckPlayer()
                                            player.onPrepare = {
                                                if activateMicrophoneDuringPreparation { simulatedAudio.microphoneBusy = true }
                                                return true
                                            }
                                            player.onPlay = { signalStarts += 1; return true }
                                            return player
                                        })
            if triggerModel.sessionAvailable {
                triggerModel.testSignal()
                precondition(signalStarts == 1 && triggerModel.playing && triggerModel.isTesting && !triggerModel.enabled)
                precondition(triggerModel.nextDue.timeIntervalSinceNow > 590)
                triggerModel.stop()
                triggerModel.enabled = true
                precondition(signalStarts == 2 && triggerModel.playing && !triggerModel.isTesting)
                triggerModel.enabled = true
                precondition(signalStarts == 2)
                idle = 300
                triggerModel.refresh()
                precondition(!triggerModel.playing && triggerModel.block == .inactive)
                triggerModel.testSignal()
                precondition(signalStarts == 3 && triggerModel.playing) // Test is an explicit user action.
                triggerModel.stop()
                simulatedAudio.outputBusy = true
                triggerModel.refresh()
                precondition(triggerModel.block == nil) // Passive listening remains eligible.
                simulatedAudio.microphoneBusy = true
                triggerModel.enabled = false
                triggerModel.enabled = true
                triggerModel.testSignal()
                precondition(signalStarts == 3 && createdPlayers == 3 && !triggerModel.playing)
                simulatedAudio.microphoneBusy = false
                simulatedAudio.outputBusy = false
                idle = 0
                triggerModel.refresh()
                triggerModel.enabled = false
                triggerModel.enabled = true
                precondition(signalStarts == 4 && triggerModel.playing)
                simulatedAudio.microphoneBusy = true
                triggerModel.refresh()
                precondition(!triggerModel.playing && !triggerModel.isTesting) // A microphone appearing during a signal stops it.
                simulatedAudio.microphoneBusy = false
                activateMicrophoneDuringPreparation = true
                triggerModel.testSignal()
                precondition(signalStarts == 4 && createdPlayers == 5 && !triggerModel.playing)
                // The final activity check catches a microphone that starts while loading the signal.
                activateMicrophoneDuringPreparation = false
                simulatedAudio.microphoneBusy = false
                simulatedRoute = HAL.Route()
                triggerModel.tick()
                precondition(!triggerModel.playing && !triggerModel.canTest && signalStarts == 4)
                simulatedRoute = HAL.Route(device: 0, uid: "reconnected-jack", name: "Jack de test", isJack: true, alive: true)
                triggerModel.tick()
                precondition(triggerModel.playing && signalStarts == 5)
                triggerModel.tick()
                precondition(signalStarts == 5) // Stable connection does not repeatedly trigger signals.
                simulatedRoute = HAL.Route()
                triggerModel.refresh()
                precondition(!triggerModel.playing && !triggerModel.canTest)
                triggerModel.testSignal()
                precondition(signalStarts == 5)
                triggerModel.enabled = false
                simulatedRoute = HAL.Route(device: 0, uid: "check-jack", name: "Jack de test", isJack: true, alive: true)
                triggerModel.tick()
                precondition(signalStarts == 5 && !triggerModel.playing && triggerModel.canTest)
                triggerModel.enabled = true
                precondition(signalStarts == 6 && triggerModel.playing && !triggerModel.isTesting)
                triggerModel.testSignal() // A manual test can replace an automatic signal already playing.
                precondition(signalStarts == 7 && triggerModel.playing && triggerModel.isTesting)
                triggerModel.stop()
                precondition(!triggerModel.playing && !triggerModel.isTesting)
                print("Test button: Auto-on keeps the wake-test action; a manual test, including during automatic playback, exposes Stop until stopped. No audio played.")
                print("Jack connection starts one automatic signal when Auto is on; unplug stops playback, reconnect needs no answer, and Auto-off stays paused. In-memory players only.")
            }
            defaults.set(false, forKey: "enabled")
            defaults.set(true, forKey: "smartMode")
            simulatedAudio = HAL.Activity(known: true, microphoneBusy: false, outputBusy: false)
            var presenceIdle: TimeInterval? = 0
            var presenceSignals = 0
            let presenceModel = AppModel(defaults: defaults, readRoute: { simulatedRoute },
                                         readAudio: { _ in simulatedAudio }, readOutputVolume: { _ in 0.25 },
                                         readIdleSeconds: { presenceIdle }, makePlayer: { _ in
                                             let player = SilentCheckPlayer()
                                             player.onPlay = { presenceSignals += 1; return true }
                                             return player
                                         })
            if presenceModel.sessionAvailable {
                presenceModel.testSignal()
                presenceModel.enabled = true
                presenceModel.stop()
                precondition(presenceSignals == 2 && presenceModel.nextDue.timeIntervalSinceNow > 590)
                presenceIdle = 299
                presenceModel.tick()
                precondition(presenceModel.block == nil && presenceSignals == 2)
                presenceIdle = 300
                presenceModel.tick()
                precondition(presenceModel.block == .inactive && presenceSignals == 2)
                presenceIdle = 0
                presenceModel.tick()
                precondition(presenceSignals == 3 && presenceModel.playing)
                precondition(presenceModel.nextDue.timeIntervalSinceNow > 590)
                presenceModel.stop()
                presenceIdle = 1
                presenceModel.tick()
                precondition(presenceSignals == 3) // Exactly one signal for the return.
                presenceIdle = 300
                presenceModel.tick()
                simulatedAudio.microphoneBusy = true
                presenceIdle = 0
                presenceModel.tick()
                precondition(presenceSignals == 3 && !presenceModel.playing)
                simulatedAudio.microphoneBusy = false
                presenceModel.tick()
                precondition(presenceSignals == 3)
                presenceIdle = 300
                presenceModel.tick()
                presenceModel.enabled = false
                presenceIdle = 0
                presenceModel.tick()
                precondition(presenceSignals == 3) // Auto off remains off on return.
                presenceIdle = 300
                presenceModel.tick()
                presenceModel.enabled = true
                precondition(presenceSignals == 3 && presenceModel.block == .inactive)
                presenceModel.smartMode = false
                presenceIdle = 0
                presenceModel.tick()
                precondition(presenceSignals == 3)
                presenceModel.stop()
                print("Presence: 299 s stays active, 300 s pauses, first returning input starts one immediate signal even without audio; microphone and Auto-off remain protected. No audio played.")
            }
            // Reproduce a long screen-off/lock with duplicate wake notifications and a transient locked session.
            let wakeDefaultsName = "fr.franckdupont.kmsa.wakecheck.\(UUID().uuidString)"
            let wakeDefaults = UserDefaults(suiteName: wakeDefaultsName)!
            defer { wakeDefaults.removePersistentDomain(forName: wakeDefaultsName) }
            let wakeLogFolder = FileManager.default.temporaryDirectory.appendingPathComponent("kmsa-wake-check-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: wakeLogFolder) }
            let wakeLog = DiagnosticLog(directory: wakeLogFolder)
            var wakeClock = Date()
            var unlocked = true
            var wakeIdle: TimeInterval? = 0
            var wakeSignals = 0
            var wakeMicrophone = false
            let wakeModel = AppModel(defaults: wakeDefaults, diagnostics: wakeLog, clock: { wakeClock },
                                     readSessionAvailable: { unlocked }, readRoute: { simulatedRoute },
                                     readAudio: { _ in HAL.Activity(known: true, microphoneBusy: wakeMicrophone, outputBusy: false) },
                                     readOutputVolume: { _ in 0.0625 }, readIdleSeconds: { wakeIdle },
                                     makePlayer: { _ in
                                         let player = SilentCheckPlayer()
                                         player.onPlay = { wakeSignals += 1; return true }
                                         return player
                                     })
            wakeModel.enabled = true
            wakeModel.stop()
            precondition(wakeSignals == 1)
            wakeIdle = 900
            wakeModel.tick()
            wakeModel.suspend(reason: "check_screen_off")
            wakeClock.addTimeInterval(3 * 3600)
            unlocked = false
            wakeIdle = 0
            wakeModel.resume(reason: "check_screen_on_still_locked")
            wakeModel.tick()
            precondition(wakeSignals == 1 && wakeModel.block == .unavailableSession)
            unlocked = true
            wakeModel.resume(reason: "check_unlocked")
            wakeModel.resume(reason: "check_duplicate_wake")
            wakeModel.tick()
            precondition(wakeSignals == 2 && wakeModel.playing)
            wakeModel.stop()
            wakeModel.tick()
            precondition(wakeSignals == 2)
            // Sleep can start before the five-minute idle threshold has been observed.
            wakeModel.suspend()
            wakeClock.addTimeInterval(301)
            wakeModel.resume()
            wakeModel.tick()
            precondition(wakeSignals == 3)
            wakeModel.stop()
            // A dark wake with no fresh input must stay silent.
            wakeModel.suspend()
            wakeClock.addTimeInterval(3600)
            wakeIdle = 3600
            wakeModel.resume()
            wakeModel.tick()
            precondition(wakeSignals == 3 && wakeModel.block == .inactive)
            wakeMicrophone = true
            wakeIdle = 0
            wakeModel.tick()
            precondition(wakeSignals == 3)
            wakeMicrophone = false
            wakeModel.tick()
            precondition(wakeSignals == 3) // Blocked returns are consumed, never queued.
            wakeModel.enabled = false
            wakeModel.suspend()
            wakeClock.addTimeInterval(3600)
            wakeModel.resume()
            wakeModel.tick()
            precondition(wakeSignals == 3)
            wakeLog.flush()
            let wakeLines = try! String(contentsOf: wakeLogFolder.appendingPathComponent("diagnostics.jsonl"), encoding: .utf8)
                .split(separator: "\n").map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
            precondition(wakeLines.filter { $0["event"] as? String == "signal_started" }.count == 3)
            precondition(wakeLines.contains { $0["event"] as? String == "signal_blocked" && $0["reason"] as? String == "microphoneInUse" && $0["source"] as? String == "presence_return" })
            precondition(wakeLines.contains { $0["event"] as? String == "session_suspended" })
            precondition(wakeLines.contains { $0["event"] as? String == "heartbeat" })
            print("Screen sleep/lock regression passed: one return signal after hours away, duplicate wakes coalesced, dark wakes/microphone/Auto-off stay silent. In-memory players only.")

            let logFolder = FileManager.default.temporaryDirectory.appendingPathComponent("kmsa-log-check-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: logFolder) }
            let logCheck = DiagnosticLog(directory: logFolder, maxBytes: 1024, archives: 3)
            for index in 0..<50 { logCheck.record("rotation_check", fields: ["index": index]) }
            logCheck.flush()
            let logFiles = try! FileManager.default.contentsOfDirectory(at: logFolder, includingPropertiesForKeys: nil)
            precondition(logFiles.count == 4)
            var latestIndex = -1
            for file in logFiles {
                let data = try! Data(contentsOf: file)
                precondition(data.count <= 1024)
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    let row = try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
                    precondition(row["event"] as? String == "rotation_check" && row["runID"] != nil && row["timestamp"] != nil)
                    if file.lastPathComponent == "diagnostics.jsonl" { latestIndex = row["index"] as! Int }
                }
            }
            precondition(latestIndex == 49)
            print("Diagnostic logging passed: valid JSON lines, chronological writes, bounded rotation, current file contains latest event; production logs untouched.")
            let errorModel = AppModel(defaults: defaults, readRoute: { simulatedRoute },
                                      readAudio: { _ in HAL.Activity(known: true, microphoneBusy: false, outputBusy: false) },
                                      readOutputVolume: { _ in 0.25 }, readIdleSeconds: { 0 },
                                      makePlayer: { _ in throw NSError(domain: "LocalizationCheck", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "Ein fremdsprachiger Systemfehler"]) })
            if errorModel.sessionAvailable {
                errorModel.testSignal()
                precondition(errorModel.message == L10n.text(.playbackFailed) && !errorModel.playing)
            }
            print("Localized blocked/failed playback messages use the app language, including errors supplied in another language. No audio played.")
            let route = HAL.route()
            if let uid = route.jackUID {
                let player = try! AVAudioPlayer(contentsOf: AppModel.resource("sub2", ext: "wav")!)
                player.currentDevice = uid
                player.volume = 0
                precondition(player.prepareToPlay() && player.currentDevice == uid)
                player.stop()
                print("AVAudioPlayer prepared and bound to the current jack, without starting playback.")
            }
            print("Native self-check passed: paused first launch, sub2 only (legacy choice ignored), one decodable stereo WAV, automatic jack eligibility, disconnected playback blocked. No audio played.")
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let route = HAL.route()
            struct Diagnostic: Encodable {
                let route: HAL.Route
                let activity: HAL.Activity
                let camera: CameraHardware.Snapshot
                let idleSeconds: TimeInterval?
                let macOutputVolume: Double?
                let outputNeedsPause: Bool
                let profiles: [String]
                let missingFiles: [String]
            }
            let catalog = AppModel.resource("profiles", ext: "json")
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? JSONDecoder().decode([SignalProfile].self, from: $0) } ?? []
            let missing = catalog.filter {
                AppModel.resource($0.file.replacingOccurrences(of: ".wav", with: ""), ext: "wav") == nil
            }.map(\.file)
            let activity = HAL.activity(output: route.device)
            let volume = HAL.outputVolume(route.device)
            let diagnostic = Diagnostic(route: route, activity: activity,
                                        camera: CameraHardware.snapshot(), idleSeconds: AppModel.inputIdleSeconds(), macOutputVolume: volume,
                                        outputNeedsPause: PlaybackPolicy.outputAudioRequiresPause(outputBusy: activity.outputBusy, outputVolume: volume),
                                        profiles: catalog.map(\.id), missingFiles: missing)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(diagnostic) { print(String(decoding: data, as: UTF8.self)) }
            return
        }
        KMSAApplication.main()
    }
}

struct KMSAApplication: App {
    @StateObject private var model = AppModel(diagnostics: .shared)
    @StateObject private var updater = UpdateModel(automaticChecks: true)
    var body: some Scene {
        MenuBarExtra {
            ControlPanel(model: model, updater: updater).environment(\.locale, L10n.locale)
        } label: {
            Image(nsImage: MenuBarIcon.image(active: model.enabled && model.route.jackUID != nil, updateAvailable: updater.hasUpdate))
                .accessibilityLabel(updater.hasUpdate ? "Keep My Speakers Awake — \(L10n.text(.updateAvailable))" : "Keep My Speakers Awake")
                .help("Keep My Speakers Awake — \(updater.hasUpdate ? L10n.text(.updateAvailable) : model.status)")
        }
        .menuBarExtraStyle(.window)
    }
}

enum MenuBarIcon {
    // macOS renders its black shapes in the appropriate color for light/dark menu bars.
    static func image(active: Bool, updateAvailable: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
            let symbol = NSImage(systemSymbolName: "hifispeaker.fill",
                                 accessibilityDescription: nil)!
            // Center the speaker in the full icon now that no question badge uses the right edge.
            symbol.draw(in: NSRect(x: 4.5, y: 1, width: 13, height: 18))
            if !active {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 3.75, y: 18.5))
                slash.line(to: NSPoint(x: 18.25, y: 1.5))
                slash.lineCapStyle = .round
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .copy
                NSColor.clear.setStroke()
                slash.lineWidth = 3.8
                slash.stroke()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.black.setStroke()
                slash.lineWidth = 1.6
                slash.stroke()
            }
            if updateAvailable {
                // A template dot adapts to light/dark menu bars. Its transparent
                // halo keeps it separate from the speaker and paused-state slash.
                let halo = NSBezierPath(ovalIn: NSRect(x: 14.5, y: 13.5, width: 7, height: 7))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.compositingOperation = .copy
                NSColor.clear.setFill()
                halo.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 16, y: 15, width: 4, height: 4)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct ControlPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: UpdateModel
    @State private var showingSmartModeHelp = false
    @Environment(\.colorScheme) private var colorScheme

    private var anthracite: Color {
        colorScheme == .dark ? Color(white: 0.8) : Color(red: 72 / 255, green: 72 / 255, blue: 74 / 255)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: "hifispeaker.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(model.enabled && model.route.jackUID != nil ? Color.green : anthracite)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep My Speakers Awake").font(.headline)
                    Text(L10n.text(.subtitle)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle(L10n.text(.enableApp), isOn: Binding(
                    get: { model.enabled && model.route.jackUID != nil },
                    set: { model.enabled = $0 }
                ))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
                    .disabled(model.route.jackUID == nil)
            }

            if model.route.jackUID != nil {
                VStack(spacing: 5) {
                    HStack {
                        Text(L10n.text(.wakeVolume)).font(.subheadline)
                        Spacer()
                        Text("\(Int((model.volume * 100).rounded())) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(value: $model.volume, in: 0.05...1, step: 0.05)
                        .accessibilityLabel(L10n.text(.wakeVolume))
                }

                Button {
                    if model.isTesting { model.stop(); model.refresh() }
                    else { model.testSignal() }
                } label: {
                    Text(model.isTesting ? L10n.text(.stopTest) : L10n.text(.testWake))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large).disabled(!model.isTesting && !model.canTest)

                HStack(spacing: 5) {
                    Toggle(L10n.text(.smartMode), isOn: $model.smartMode)
                        .accessibilityLabel(L10n.text(.smartModeOption))
                        .fixedSize()
                        .disabled(!model.enabled)
                        .opacity(model.enabled ? 1 : 0.45)
                    Button { showingSmartModeHelp.toggle() } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .padding(3)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(SmartModeHelp.text)
                    .accessibilityLabel(L10n.text(.aboutSmartMode))
                    .accessibilityHint(L10n.text(.smartModeHint))
                    .popover(isPresented: $showingSmartModeHelp, arrowEdge: .top) {
                        SmartModeHelp()
                    }
                    Text(L10n.text(.recommended))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(model.enabled ? 1 : 0.45)
                        .accessibilityHidden(true)
                }
                Toggle(L10n.text(.openAtLogin), isOn: Binding(get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                if let message = model.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.route.jackUID == nil {
                Text(L10n.text(.noJack))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                Divider()
                UpdateControl(updater: updater) {
                    Task { await updater.check { model.stop() } }
                }
                HStack(spacing: 6) {
                    Text("KMSA · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")").font(.caption2).foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Link(destination: AppLinks.repository) {
                        HStack(spacing: 3) {
                            Text("GitHub")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .medium))
                                .accessibilityHidden(true)
                        }
                    }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .buttonStyle(.plain)
                        .help(L10n.text(.githubRepository))
                        .accessibilityLabel(L10n.text(.githubRepository))
                    Spacer(minLength: 0)
                    Button(L10n.text(.quit)) { model.stop(); NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                }
            }
        }
        .foregroundStyle(anthracite)
        .padding(20).frame(width: 355)
        .background(PanelCorners())
    }

}

// Clip the existing AppKit panel surface, retaining its system material and shadow.
// The frame view owns the complete surface; clipping only SwiftUI content would
// leave the original window background visible behind the rounder corners.
private struct PanelCorners: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { CornerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CornerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let surface = window.contentView?.superview else { return }
            window.isOpaque = false
            surface.wantsLayer = true
            surface.layer?.cornerRadius = 20
            surface.layer?.cornerCurve = .continuous
            surface.layer?.masksToBounds = true
            window.invalidateShadow()
        }
    }
}

struct SmartModeHelp: View {
    static var text: String { L10n.text(.smartHelp) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(.smartMode)).font(.headline)
            Text(Self.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 310, alignment: .leading)
    }
}
