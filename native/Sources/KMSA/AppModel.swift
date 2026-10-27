import AppKit
import AVFAudio
import CoreGraphics
import KMSACore
import ServiceManagement

@MainActor
final class AppModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            defaults.set(enabled, forKey: "enabled")
            log("settings_changed", ["setting": "enabled", "value": enabled])
            stop()
            nextDue = clock().addingTimeInterval(PlaybackPolicy.interval)
            refresh()
            if enabled && route.jackUID != nil { play(trigger: .automatic, source: "auto_enabled") }
        }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: "volume"); player?.volume = Float(volume)
            log("settings_changed", ["setting": "signalVolume", "value": volume]) }
    }
    let profileID = "sub2"
    @Published var smartMode: Bool {
        didSet { defaults.set(smartMode, forKey: "smartMode"); refresh()
            log("settings_changed", ["setting": "smartMode", "value": smartMode]) }
    }
    @Published private(set) var route = HAL.Route()
    @Published private(set) var activity = HAL.Activity(known: false, microphoneBusy: false, outputBusy: false)
    @Published private(set) var macOutputVolume: Double?
    @Published private(set) var captureState: CaptureState = .unknown
    @Published private(set) var idleSeconds: TimeInterval?
    @Published private(set) var status = L10n.text(.paused)
    @Published private(set) var playing = false
    @Published private(set) var lastSignal: Date?
    @Published private(set) var nextDue = Date().addingTimeInterval(PlaybackPolicy.interval)
    @Published private(set) var now = Date()
    @Published private(set) var loginEnabled = false
    @Published private(set) var message: String?
    let profiles: [SignalProfile]

    private let diagnostics: DiagnosticLog
    private let clock: () -> Date
    private let readSessionAvailable: () -> Bool
    private var lastStateKey = ""
    private var lastHeartbeat = Date.distantPast
    private let defaults: UserDefaults
    private let readRoute: () -> HAL.Route
    private let readAudio: (UInt32) -> HAL.Activity
    private let readOutputVolume: (UInt32) -> Double?
    private let readIdleSeconds: () -> TimeInterval?
    private let makePlayer: (URL) throws -> any SignalPlayer
    private var player: (any SignalPlayer)?
    private var observer: HardwareObserver?
    private var timer: Timer?
    private var notifications: [(NotificationCenter, NSObjectProtocol)] = []
    private var lastBusyAt: Date?
    private var sessionSuspended = false
    private var presenceTracker = PresenceTracker()
    private var pendingPresenceReturn = false

    init(defaults: UserDefaults = .standard,
         diagnostics: DiagnosticLog = .disabled,
         clock: @escaping () -> Date = Date.init,
         readSessionAvailable: @escaping () -> Bool = AppModel.consoleSessionAvailable,
         readRoute: @escaping () -> HAL.Route = HAL.route,
         readAudio: @escaping (UInt32) -> HAL.Activity = { HAL.activity(output: $0) },
         readOutputVolume: @escaping (UInt32) -> Double? = HAL.outputVolume,
         readIdleSeconds: @escaping () -> TimeInterval? = AppModel.inputIdleSeconds,
         makePlayer: @escaping (URL) throws -> any SignalPlayer = { try AVAudioPlayer(contentsOf: $0) }) {
        self.diagnostics = diagnostics
        self.clock = clock
        self.readSessionAvailable = readSessionAvailable
        self.defaults = defaults
        self.readRoute = readRoute
        self.readAudio = readAudio
        self.readOutputVolume = readOutputVolume
        self.readIdleSeconds = readIdleSeconds
        self.makePlayer = makePlayer
        let catalog = Self.resource("profiles", ext: "json")
        profiles = catalog.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([SignalProfile].self, from: $0) }?
            .filter { $0.id == "sub2" && $0.file == "sub2.wav" } ?? []
        enabled = defaults.bool(forKey: "enabled") // Paused for the first launch, while the extension is still installed.
        let storedVolume = defaults.object(forKey: "volume") as? Double ?? 1
        volume = storedVolume.isFinite ? min(1, max(0.05, storedVolume)) : 1
        smartMode = defaults.object(forKey: "smartMode") as? Bool ?? true
        defaults.removeObject(forKey: "meetingPause") // Retire the former manual meeting lock.
        super.init()
        loginEnabled = SMAppService.mainApp.status == .enabled
        log("app_started", ["bundlePath": Bundle.main.bundleURL.path])
        refresh()
        observer = HardwareObserver { [weak self] in
            Task { @MainActor in self?.hardwareChanged() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 0.25
        observeWorkspace()
    }

    static func resource(_ name: String, ext: String) -> URL? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Signals")
        }
        return Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Resources")
    }

    nonisolated static func inputIdleSeconds() -> TimeInterval? {
        // Query elapsed input time only; no event tap, keystrokes or mouse coordinates are collected.
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                              eventType: CGEventType(rawValue: UInt32.max)!)
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    var sessionAvailable: Bool { !sessionSuspended && readSessionAvailable() }

    nonisolated static func consoleSessionAvailable() -> Bool {
        guard
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              session[kCGSessionLoginDoneKey as String] as? Bool == true else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool != true
    }

    var block: PlaybackBlock? { block(trigger: .automatic) }
    var canTest: Bool { block(trigger: .manualTest) == nil && !profiles.isEmpty }
    var selectedProfile: SignalProfile? { profiles.first { $0.id == profileID } }
    var isTesting: Bool { playing && currentTrigger == .manualTest }

    private func block(trigger: PlaybackTrigger) -> PlaybackBlock? {
        PlaybackPolicy.block(enabled: enabled, trigger: trigger,
                             sessionAvailable: sessionAvailable, jackUID: route.jackUID,
                             smartMode: smartMode,
                             activityKnown: activity.known, audioBusy: activity.outputBusy,
                             lastBusyAt: lastBusyAt, now: now,
                             captureState: captureState,
                             outputVolume: macOutputVolume, idleSeconds: idleSeconds)
    }

    private func hardwareChanged() {
        log("hardware_notification")
        stop(reason: "hardware_notification")
        refresh()
    }

    func refresh() {
        now = clock()
        let current = readRoute()
        if current != route {
            log("route_changed", ["device": current.device, "jackEligible": current.jackUID != nil,
                                  "alive": current.alive, "routeError": current.error ?? "none"])
            stop(reason: "route_changed")
            route = current
            message = nil
            // A newly selected jack becomes eligible on the next tick without a user answer.
            if route.jackUID != nil { nextDue = now }
        }
        activity = readAudio(route.device)
        macOutputVolume = readOutputVolume(route.device)
        idleSeconds = readIdleSeconds()
        if sessionAvailable {
            if presenceTracker.update(idleSeconds: idleSeconds, at: now) {
                pendingPresenceReturn = true
                log("presence_return_detected")
            }
        } else {
            presenceTracker.suspend(at: now)
            pendingPresenceReturn = false
        }
        captureState = CaptureState.detect(audioKnown: activity.known, microphoneBusy: activity.microphoneBusy)
        let outputNeedsPause = PlaybackPolicy.outputAudioRequiresPause(outputBusy: activity.outputBusy,
                                                                       outputVolume: macOutputVolume)
        if outputNeedsPause { lastBusyAt = now }
        if !sessionAvailable || route.jackUID == nil {
            stop(reason: "session_or_route_unavailable")
        } else if captureState != .clear {
            stop(reason: "microphone_protection") // Active or unknown microphone state also interrupts an explicit test.
        } else if playing && block(trigger: currentTrigger) != nil {
            stop(reason: block(trigger: currentTrigger)?.rawValue ?? "policy_changed")
        }
        if playing { status = L10n.text(.wakePlaying) }
        else if let block { status = Self.label(block) }
        else { status = L10n.text(.ready) }
        if profiles.isEmpty { status = L10n.text(.audioFilesUnavailable) }
        recordState()
    }

    private var currentTrigger: PlaybackTrigger = .automatic

    func tick() {
        let previous = now
        refresh()
        let returned = pendingPresenceReturn
        pendingPresenceReturn = false
        if returned {
            if smartMode && enabled && route.jackUID != nil && !playing {
                play(trigger: .automatic, source: "presence_return")
                return
            }
            log("presence_return_skipped", ["reason": !enabled ? "auto_off" : !smartMode ? "smart_off" : playing ? "already_playing" : "no_jack"])
        }
        // Discard stale timers after sleep or a long scheduling stall, never catch up with a sound.
        if now.timeIntervalSince(previous) > 60 {
            nextDue = now.addingTimeInterval(PlaybackPolicy.interval)
            log("timer_gap", ["gapSeconds": now.timeIntervalSince(previous)])
            return
        }
        guard enabled, now >= nextDue, !playing, block == nil else { return }
        nextDue = now.addingTimeInterval(PlaybackPolicy.interval)
        play(trigger: .automatic, source: "scheduled")
    }

    func testSignal() { play(trigger: .manualTest, source: "manual_test") }

    private func play(trigger: PlaybackTrigger, source: String) {
        refresh()
        log("signal_requested", ["source": source])
        if let reason = block(trigger: trigger) {
            log("signal_blocked", ["source": source, "reason": reason.rawValue])
            message = "\(L10n.text(.wakeBlocked)): \(Self.label(reason))"
            return
        }
        guard let profile = selectedProfile,
              let url = Self.resource(profile.file.replacingOccurrences(of: ".wav", with: ""), ext: "wav") else {
            log("signal_failed", ["source": source, "reason": "missing_file"])
            message = L10n.text(.wakeFileMissing)
            return
        }
        stop()
        do {
            let candidate = try makePlayer(url)
            candidate.currentDevice = route.uid // Explicit device binding; never intentionally play on the system fallback.
            candidate.volume = Float(volume)
            candidate.numberOfLoops = 0
            candidate.delegate = self
            guard candidate.prepareToPlay(), candidate.currentDevice == route.uid else {
                log("signal_failed", ["source": source, "reason": "device_binding_or_prepare"])
                message = L10n.text(.jackUnavailable)
                return
            }
            // The output can change while a file is loading. Recheck immediately before starting.
            let fresh = readRoute()
            guard fresh == route, fresh.jackUID != nil, sessionAvailable else {
                hardwareChanged()
                log("signal_failed", ["source": source, "reason": "route_changed_before_play"])
                message = L10n.text(.routeChanged)
                return
            }
            refresh()
            if let reason = block(trigger: trigger) {
                log("signal_blocked", ["source": source, "reason": reason.rawValue])
                message = "\(L10n.text(.wakeBlocked)): \(Self.label(reason))"
                return
            }
            currentTrigger = trigger
            player = candidate
            guard candidate.play() else {
                log("signal_failed", ["source": source, "reason": "play_returned_false"])
                stop()
                message = L10n.text(.playbackFailed)
                return
            }
            playing = true
            pendingPresenceReturn = false
            lastSignal = clock()
            nextDue = clock().addingTimeInterval(PlaybackPolicy.interval)
            message = nil
            status = L10n.text(.wakePlaying)
            log("signal_started", ["source": source, "profile": profileID])
        } catch {
            let failure = error as NSError
            log("signal_failed", ["source": source, "reason": "player_error",
                                  "errorDomain": failure.domain, "errorCode": failure.code])
            stop()
            message = L10n.text(.playbackFailed)
        }
    }

    func stop(reason: String = "requested") {
        if playing { log("signal_stopped", ["reason": reason, "manualTest": isTesting]) }
        player?.stop()
        player = nil
        playing = false
        currentTrigger = .automatic
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.log("signal_finished", ["success": flag])
            self.stop(reason: flag ? "completed" : "interrupted")
            if !flag { self.message = L10n.text(.playbackInterrupted) }
            self.refresh()
        }
    }

    func setLoginEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if value && !loginEnabled { message = L10n.text(.loginApproval) }
        } catch { message = L10n.text(.loginFailed) }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(center, name) { [weak self] in self?.suspend(reason: name.rawValue) }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(center, name) { [weak self] in self?.resume(reason: name.rawValue) }
        }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { [weak self] in
            self?.log("app_terminating")
            self?.diagnostics.flush()
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.suspend(reason: "screen_locked") }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.resume(reason: "screen_unlocked") }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        }
        notifications.append((center, token))
    }

    func suspend(reason: String = "session_suspended") {
        presenceTracker.suspend(at: clock())
        sessionSuspended = true
        log("session_suspended", ["notification": reason])
        stop(reason: reason)
        refresh()
    }

    func resume(reason: String = "session_resumed") {
        sessionSuspended = false
        log("session_resumed", ["notification": reason])
        nextDue = clock().addingTimeInterval(PlaybackPolicy.interval)
        refresh()
    }

    private func log(_ event: String, _ extra: [String: Any] = [:]) {
        var fields: [String: Any] = [
            "enabled": enabled, "smartMode": smartMode, "playing": playing,
            "sessionAvailable": sessionAvailable, "sessionSuspended": sessionSuspended,
            "jackEligible": route.jackUID != nil, "device": route.device,
            "activityKnown": activity.known, "microphoneBusy": activity.microphoneBusy,
            "outputBusy": activity.outputBusy, "signalVolume": volume,
            "macOutputVolume": macOutputVolume as Any? ?? NSNull(),
            "idleSeconds": idleSeconds as Any? ?? NSNull(),
            "block": block?.rawValue ?? "none",
            "secondsUntilDue": nextDue.timeIntervalSince(now),
            "lastSignal": lastSignal.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull(),
            "graceRemainingSeconds": lastBusyAt.map { max(0, PlaybackPolicy.grace - now.timeIntervalSince($0)) } ?? 0,
        ]
        fields.merge(extra) { _, new in new }
        diagnostics.record(event, fields: fields)
    }

    private func recordState() {
        let key = "\(enabled)|\(smartMode)|\(sessionAvailable)|\(route.device)|\(route.jackUID != nil)|\(activity.known)|\(activity.microphoneBusy)|\(activity.outputBusy)|\(macOutputVolume.map { Int(($0 * 1000).rounded()) } ?? -1)|\(block?.rawValue ?? "none")|\(playing)"
        if key != lastStateKey {
            lastStateKey = key
            log("state_changed")
        }
        if now.timeIntervalSince(lastHeartbeat) >= 60 {
            lastHeartbeat = now
            log("heartbeat")
        }
    }

    static func label(_ reason: PlaybackBlock) -> String {
        switch reason {
        case .paused: return L10n.text(.autoPaused)
        case .unavailableSession: return L10n.text(.sessionUnavailable)
        case .wrongOutput: return L10n.text(.noJack)
        case .unknownActivity: return L10n.text(.unknownAudio)
        case .audioInUse: return L10n.text(.audioInUse)
        case .recentAudio: return L10n.text(.recentAudio)
        case .microphoneInUse: return L10n.text(.microphoneInUse)
        case .unknownCapture: return L10n.text(.unknownMicrophone)
        case .inactive: return L10n.text(.inactive)
        }
    }
}
