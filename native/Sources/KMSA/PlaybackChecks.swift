import Foundation
import KMSACore

extension AppModel {
    static func runCountdownChecks() {
        let suite = "fr.franckdupont.kmsa.countdown-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let player = SilentCheckPlayer()
        player.onPlay = { true }
        var audio = HAL.Activity(known: true, microphoneBusy: false, outputBusy: false)
        let model = AppModel(defaults: defaults, readSessionAvailable: { true },
                             readRoute: { HAL.Route(device: 0, uid: "countdown-check", name: "Silent check", isJack: true, alive: true) },
                             readAudio: { _ in audio }, readOutputVolume: { _ in 0.25 },
                             readIdleSeconds: { 0 }, makePlayer: { _ in player })
        precondition(model.testSecondsRemaining == nil && model.wakeTestTitle == L10n.text(.testWake))
        model.testSignal()
        precondition(model.isTesting && model.testSecondsRemaining == 6)
        precondition(model.wakeTestTitle == "\(L10n.text(.stopTest)) (6 s)")
        for (elapsed, remaining) in [(0.2, 6), (1.0, 5), (4.7, 2), (5.99, 1), (6.0, 0), (6.2, 0)] {
            player.currentTime = elapsed
            model.refresh()
            precondition(model.testSecondsRemaining == remaining)
            precondition(model.wakeTestTitle == "\(L10n.text(.stopTest)) (\(remaining) s)")
        }
        player.currentTime = .nan
        precondition(model.testSecondsRemaining == nil && model.wakeTestTitle == L10n.text(.stopTest))
        player.currentTime = 0
        model.stop()
        precondition(model.testSecondsRemaining == nil && model.wakeTestTitle == L10n.text(.testWake))
        model.enabled = true
        precondition(model.playing && !model.isTesting && model.testSecondsRemaining == nil)
        precondition(model.wakeTestTitle == L10n.text(.testWake))
        model.enabled = false
        model.testSignal()
        precondition(model.testSecondsRemaining == 6)
        audio.microphoneBusy = true
        model.refresh()
        precondition(!model.playing && model.testSecondsRemaining == nil)
        precondition(model.wakeTestTitle == L10n.text(.testWake))
        print("Wake-test countdown passed: player position, rounding, completion, Stop, automatic playback and microphone interruption. In-memory player only; no audio played.")
    }
}
