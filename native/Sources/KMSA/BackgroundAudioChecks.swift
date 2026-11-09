import Foundation
import KMSACore

extension AppModel {
    static func runBackgroundAudioChecks() {
        let suite = "fr.franckdupont.kmsa.background-audio-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var clock = Date(timeIntervalSince1970: 100_000)
        var onConsole = true
        var unlocked = true
        var idle: TimeInterval? = 0
        var audio = HAL.Activity(known: true, microphoneBusy: false, outputBusy: true)
        var macVolume: Double? = 0.0625
        var route = HAL.Route(device: 0, uid: "background-check-jack", name: "Silent check", isJack: true, alive: true)
        var starts = 0
        var leaveSessionDuringPreparation = false
        var signalLevels: [Float] = []
        let model = AppModel(defaults: defaults, clock: { clock },
                             readSessionAvailable: { unlocked }, readSessionOnConsole: { onConsole },
                             readRoute: { route }, readAudio: { _ in audio },
                             readOutputVolume: { _ in macVolume }, readIdleSeconds: { idle },
                             makePlayer: { _ in
                                 let player = SilentCheckPlayer()
                                 player.onPrepare = {
                                     if leaveSessionDuringPreparation { onConsole = false }
                                     return true
                                 }
                                 player.onPlay = { [weak player] in
                                     starts += 1
                                     signalLevels.append(player?.volume ?? -1)
                                     return true
                                 }
                                 return player
                             })
        // App Nap timing must not keep the display or the whole Mac awake.
        precondition(!playbackActivityOptions.contains(.idleSystemSleepDisabled))
        precondition(!playbackActivityOptions.contains(.idleDisplaySleepDisabled))
        precondition(!model.backgroundTimingActive)
        model.volume = 0.35
        model.enabled = true
        precondition(starts == 1 && model.playing && model.backgroundTimingActive)
        let initialDue = model.nextDue
        model.setScreensSleeping(true)
        unlocked = false
        model.setScreenLocked(true)
        precondition(model.playing && model.block == nil && !model.canTest)
        precondition(model.nextDue == initialDue && !model.sessionAvailable)
        model.stop()
        idle = 3600
        // An hour of passive listening must still produce six scheduled wake-ups.
        // Real players are never constructed; no audio is emitted.
        let levels: [Double?] = [0.0625, 0.499, 0.5, 1, nil]
        for step in 1...120 {
            clock.addTimeInterval(30)
            macVolume = levels[step % levels.count]
            model.tick()
            precondition(model.block == nil && model.backgroundTimingActive)
            if model.playing { model.stop() }
        }
        precondition(starts == 7 && signalLevels.allSatisfy { abs($0 - 0.35) < 0.0001 })
        let dueBeforeDuplicate = model.nextDue
        model.setScreensSleeping(true)
        model.setScreenLocked(true)
        model.setSessionActive(true)
        precondition(model.nextDue == dueBeforeDuplicate)

        // Stopping the music while still absent immediately restores the pause.
        audio.outputBusy = false
        model.refresh()
        precondition(model.block == .unavailableSession && !model.backgroundTimingActive)
        for _ in 0..<20 { clock.addTimeInterval(30); model.tick() }
        precondition(starts == 7)
        audio.outputBusy = true
        model.tick()
        precondition(starts == 8 && model.playing && model.backgroundTimingActive)
        audio.microphoneBusy = true
        model.refresh()
        precondition(model.block == .microphoneInUse && !model.playing)
        audio.microphoneBusy = false
        audio.known = false
        model.refresh()
        precondition(model.block != nil && !model.backgroundTimingActive)
        audio.known = true
        model.smartMode = false
        precondition(model.block == .unavailableSession && !model.backgroundTimingActive)
        model.smartMode = true
        model.enabled = false
        precondition(model.block == .paused && !model.backgroundTimingActive)
        model.testSignal()
        precondition(starts == 8 && !model.playing)
        model.enabled = true
        precondition(starts == 9 && model.playing)
        route = HAL.Route()
        model.refresh()
        precondition(model.block == .wrongOutput && !model.playing && !model.backgroundTimingActive)
        route = HAL.Route(device: 0, uid: "background-check-jack", name: "Silent check", isJack: true, alive: true)
        model.refresh()

        // Fast user switching and real system sleep stay independent hard gates.
        model.setSessionActive(false)
        precondition(model.block == .unavailableSession && !model.backgroundTimingActive)
        model.suspend()
        model.setSessionActive(true)
        precondition(model.block == .unavailableSession)
        model.setScreensSleeping(false)
        unlocked = true
        model.setScreenLocked(false)
        precondition(model.block == .unavailableSession)
        model.setSessionActive(false)
        model.resume()
        precondition(model.block == .unavailableSession)
        model.setSessionActive(true)
        onConsole = false
        model.refresh()
        precondition(model.block == .unavailableSession && !model.backgroundTimingActive)
        onConsole = true
        model.refresh()
        model.setScreensSleeping(true)
        unlocked = false
        model.setScreenLocked(true)
        model.suspend()
        clock.addTimeInterval(3600)
        model.resume()
        model.tick()
        precondition(starts == 9 && model.block == nil && !model.playing)
        precondition(model.nextDue.timeIntervalSince(clock) == PlaybackPolicy.interval)

        // Recheck the current console session immediately before a background signal.
        leaveSessionDuringPreparation = true
        for _ in 0..<20 { clock.addTimeInterval(30); model.tick() }
        precondition(starts == 9 && !model.playing && model.block == .unavailableSession)
        precondition(!model.backgroundTimingActive)
        model.enabled = false
        print("Background listening regression passed: six hourly scheduled signals with a dark/locked screen at every volume; microphone, unknown activity, Auto-off, jack, user switching and system sleep remain protected. Silent in-memory players only.")
    }
}
