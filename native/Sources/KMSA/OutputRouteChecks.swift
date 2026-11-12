import Foundation
import CoreAudio
import KMSACore

extension AppModel {
    static func runOutputRouteChecks() {
        let suite = "fr.franckdupont.kmsa.output-check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let builtIn = HAL.Route(device: 1, uid: "mac-speakers", name: "Renamed device",
                                outputKind: .builtInSpeakers, alive: true)
        var route = builtIn
        var starts = 0
        var created = 0
        var changeDuringPreparation = false
        let model = AppModel(defaults: defaults, readSessionAvailable: { true }, readRoute: { route },
                             readAudio: { _ in HAL.Activity(known: true, microphoneBusy: false, outputBusy: false) },
                             readOutputVolume: { _ in 0.25 }, readIdleSeconds: { 0 }, makePlayer: { _ in
            created += 1
            let player = SilentCheckPlayer()
            player.onPrepare = {
                if changeDuringPreparation { route = builtIn }
                return true
            }
            player.onPlay = { starts += 1; return true }
            return player
        })
        model.volume = 0.35
        precondition(!model.canTest && model.status == L10n.text(.builtInSpeakers))
        model.enabled = true
        model.testSignal()
        precondition(!model.playing && created == 0 && model.block == .wrongOutput)
        for transport in [kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetooth,
                          kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeAirPlay,
                          kAudioDeviceTransportTypeBuiltIn] {
            let kind = OutputClassifier.classify(transport: transport, terminals: [kAudioStreamTerminalTypeHeadphones],
                                                 sources: [], alive: true, hasOutput: true)
            route = HAL.Route(device: 2, uid: "external-\(transport)", name: "Mac speakers", outputKind: kind, alive: true)
            let previous = starts
            model.tick()
            precondition(model.canTest && model.playing && starts == previous + 1)
            model.tick()
            precondition(starts == previous + 1 && model.volume == 0.35)
            route = builtIn
            model.refresh()
            precondition(!model.canTest && !model.playing && model.enabled)
            precondition(model.status == L10n.text(.builtInSpeakers))
            model.testSignal()
            precondition(starts == previous + 1)
        }
        model.enabled = false
        route = HAL.Route(device: 2, uid: "usb", outputKind: .external, alive: true)
        let previous = starts
        model.tick()
        precondition(model.canTest && !model.playing && starts == previous)
        model.testSignal()
        precondition(model.playing && model.isTesting && starts == previous + 1)
        route = builtIn
        model.refresh()
        precondition(!model.playing && !model.isTesting)
        route = HAL.Route(device: 2, uid: "usb", outputKind: .external, alive: true)
        changeDuringPreparation = true
        model.testSignal()
        precondition(!model.playing && starts == previous + 1)
        precondition(model.route.outputKind == .builtInSpeakers)
        route = HAL.Route()
        model.refresh()
        precondition(model.status == L10n.text(.noExternalOutput) && !model.canTest)
        print("External output checks passed: USB, Bluetooth, HDMI, AirPlay and analog routes; Mac speaker exclusion, settings preservation, Auto-off, test interruption and route changes during preparation. Silent in-memory players only.")
    }
}
