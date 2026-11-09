import Foundation
import CoreAudio
import IOKit.audio
import KMSACore

private var checkCount = 0
private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    checkCount += 1
    guard actual == expected else { fatalError("Expected \(expected), got \(actual)", file: file, line: line) }
}
private func expectNil<T>(_ actual: T?, file: StaticString = #file, line: UInt = #line) {
    checkCount += 1
    guard actual == nil else { fatalError("Expected nil, got \(String(describing: actual))", file: file, line: line) }
}

final class PlaybackPolicyTests {
    func block(enabled: Bool = true, test: Bool = false, session: Bool = true, screen: Bool = true,
               jack: String? = "jack-a", smart: Bool = true,
               known: Bool = true, busy: Bool = false,
               capture: CaptureState = .clear,
               idle: TimeInterval? = 0,
               trigger: PlaybackTrigger? = nil) -> PlaybackBlock? {
        PlaybackPolicy.block(enabled: enabled, trigger: trigger ?? (test ? .manualTest : .automatic), sessionAvailable: session, screenAvailable: screen,
                             jackUID: jack, smartMode: smart,
                             activityKnown: known, audioBusy: busy,
                             captureState: capture, idleSeconds: idle)
    }

    func testAudioKeepsAutomaticSignalsEligible() {
        for screen in [true, false] {
            for idle: TimeInterval? in [0, 3600, nil, .nan] {
                expectNil(block(screen: screen, busy: true, idle: idle))
                expectEqual(block(screen: screen, busy: true, capture: .microphone, idle: idle), .microphoneInUse)
                expectEqual(block(screen: screen, busy: true, capture: .unknown, idle: idle), .unknownCapture)
                expectEqual(block(session: false, screen: screen, busy: true, idle: idle), .unavailableSession)
                expectEqual(block(screen: screen, jack: nil, busy: true, idle: idle), .wrongOutput)
            }
        }
        expectEqual(block(screen: false), .unavailableSession)
        expectEqual(block(screen: false, smart: false, busy: true), .unavailableSession)
        expectEqual(block(screen: false, known: false, busy: true), .unavailableSession)
        expectEqual(block(test: true, screen: false, busy: true), .unavailableSession)
        expectEqual(block(enabled: false, screen: false, busy: true), .paused)
        expectEqual(block(known: false, busy: true), .unknownActivity)
    }

    func testAutomaticPlaybackNeedsAllProtections() {
        expectNil(block())
        expectEqual(block(enabled: false), .paused)
        expectEqual(block(session: false), .unavailableSession)
        expectEqual(block(jack: nil), .wrongOutput)
        expectEqual(block(jack: ""), .wrongOutput)
        expectEqual(block(known: false), .unknownActivity)
        expectNil(block(busy: true))
    }

    func testManualTestCannotEscapeThePhysicalOutputAndSessionGate() {
        expectNil(block(enabled: false, test: true, known: false, busy: true))
        expectEqual(block(test: true, session: false), .unavailableSession)
        expectEqual(block(test: true, jack: nil), .wrongOutput)
    }

    func testSmartToggleCannotDisableTheJackProtection() {
        expectNil(block(smart: false, known: false, busy: true))
        expectEqual(block(jack: nil, smart: false), .wrongOutput)
        expectEqual(block(session: false, smart: false), .unavailableSession)
    }

    func testMicrophoneProtectionAlwaysBlocksSignals() {
        for test in [false, true] {
            for smart in [false, true] {
                expectEqual(block(test: test, smart: smart, capture: .microphone), .microphoneInUse)
                expectEqual(block(test: test, smart: smart, capture: .unknown), .unknownCapture)
                expectNil(block(test: test, smart: smart, capture: .clear))
            }
        }
        expectEqual(block(test: true, session: false, capture: .microphone), .unavailableSession)
        expectEqual(block(test: true, jack: nil, capture: .microphone), .wrongOutput)
    }

    func testIdleRequiresBothNoInputAndNoAudio() {
        expectNil(block(idle: 299.999))
        expectEqual(block(idle: 300), .inactive)
        expectEqual(block(idle: 3600), .inactive)
        expectNil(block(busy: true, idle: 3600))
        expectEqual(block(capture: .microphone, idle: 0), .microphoneInUse)
        for idle: TimeInterval? in [nil, .nan, .infinity, -1] {
            expectEqual(block(idle: idle), .unknownActivity)
            expectNil(block(busy: true, idle: idle))
        }
        expectNil(block(smart: false, idle: 3600))
        expectNil(block(test: true, idle: 3600))
    }

    func testPresenceReturnIsOneEventAfterFiveMinutes() {
        var tracker = PresenceTracker()
        for idle in [0.0, 1, 60, 299.999, 300, 900] {
            expectEqual(tracker.update(idleSeconds: idle), false)
        }
        expectEqual(tracker.update(idleSeconds: 0), true)
        expectEqual(tracker.update(idleSeconds: 1), false)
        expectEqual(tracker.update(idleSeconds: 0), false)
        expectEqual(tracker.update(idleSeconds: 300), false)
        expectEqual(tracker.update(idleSeconds: 0), true)
        for unknown: TimeInterval? in [nil, .nan, .infinity, -1] {
            _ = tracker.update(idleSeconds: 300)
            expectEqual(tracker.update(idleSeconds: unknown), false)
            expectEqual(tracker.update(idleSeconds: 0), false)
        }
        _ = tracker.update(idleSeconds: 300)
        tracker.reset()
        expectEqual(tracker.update(idleSeconds: 0), false)
    }

    func testPresenceSurvivesSessionSuspension() {
        let start = Date(timeIntervalSince1970: 1000)
        var tracker = PresenceTracker()
        _ = tracker.update(idleSeconds: 900, at: start)
        tracker.suspend(at: start)
        expectEqual(tracker.update(idleSeconds: 0, at: start.addingTimeInterval(1)), true)
        expectEqual(tracker.update(idleSeconds: 0, at: start.addingTimeInterval(2)), false)
        tracker.suspend(at: start)
        tracker.suspend(at: start.addingTimeInterval(299))
        expectEqual(tracker.update(idleSeconds: 0, at: start.addingTimeInterval(300)), true)
        tracker.suspend(at: start)
        expectEqual(tracker.update(idleSeconds: 0, at: start.addingTimeInterval(299.999)), false)
        tracker.suspend(at: start)
        expectEqual(tracker.update(idleSeconds: 3600, at: start.addingTimeInterval(3600)), false)
        expectEqual(tracker.update(idleSeconds: 0, at: start.addingTimeInterval(3601)), true)
        tracker.suspend(at: start)
        expectEqual(tracker.update(idleSeconds: nil, at: start.addingTimeInterval(3600)), false)
        expectEqual(tracker.update(idleSeconds: 0, at: start.addingTimeInterval(3601)), false)
        tracker.suspend(at: start)
        expectEqual(tracker.update(idleSeconds: 0, at: start.addingTimeInterval(-1)), false)
    }

    func testLanguageUsesOnlyThePrimaryPreference() {
        for languages in [["fr"], ["fr-FR"], ["fr-CA", "en-US"], ["fr_CH"], ["FR-fr"]] {
            expectEqual(AppLanguage.resolve(languages), .french)
        }
        for languages in [[], ["en"], ["en-FR"], ["de-DE", "fr-FR"], ["es-ES", "fr"], ["ja-JP"], ["zh-Hans"], ["", "fr"]] {
            expectEqual(AppLanguage.resolve(languages), .english)
        }
        for key in AppText.allCases {
            for language in AppLanguage.allCases {
                expectEqual(key.localized(in: language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, false)
            }
        }
        expectEqual(AppText.testWake.localized(in: .french), "Tester le réveil")
        expectEqual(AppText.testWake.localized(in: .english), "Test wake-up")
        expectEqual(AppText.noJack.localized(in: .french), "Pas de connexion jack détectée")
        expectEqual(AppText.noJack.localized(in: .english), "No jack connection detected")
        expectEqual(AppText.smartHelp.localized(in: .french).components(separatedBy: "\n").count, 6)
        expectEqual(AppText.smartHelp.localized(in: .english).components(separatedBy: "\n").count, 6)
    }

    func testMicrophoneDetection() {
        expectEqual(CaptureState.detect(audioKnown: true, microphoneBusy: false), .clear)
        expectEqual(CaptureState.detect(audioKnown: true, microphoneBusy: true), .microphone)
        expectEqual(CaptureState.detect(audioKnown: false, microphoneBusy: false), .unknown)
        expectEqual(CaptureState.detect(audioKnown: false, microphoneBusy: true), .microphone)
    }
}

@main
enum PolicyChecks {
    static func main() {
        let policy = PlaybackPolicyTests()
        policy.testAutomaticPlaybackNeedsAllProtections()
        policy.testAudioKeepsAutomaticSignalsEligible()
        policy.testManualTestCannotEscapeThePhysicalOutputAndSessionGate()
        policy.testSmartToggleCannotDisableTheJackProtection()
        policy.testMicrophoneProtectionAlwaysBlocksSignals()
        policy.testMicrophoneDetection()
        policy.testLanguageUsesOnlyThePrimaryPreference()
        policy.testPresenceReturnIsOneEventAfterFiveMinutes()
        policy.testPresenceSurvivesSessionSuspension()
        policy.testIdleRequiresBothNoInputAndNoAudio()
        func classify(_ transport: UInt32 = kAudioDeviceTransportTypeBuiltIn,
                      _ terminal: UInt32, source: UInt32? = nil, jack: UInt32? = nil, alive: Bool = true) -> Bool {
            OutputClassifier.isBuiltInJack(transport: transport, terminals: [terminal], sources: source.map { [$0] } ?? [],
                                           jackControl: jack, alive: alive)
        }
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, kAudioStreamTerminalTypeHeadphones), true)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, UInt32(OUTPUT_HEADPHONES)), true)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, 0, source: UInt32(kIOAudioOutputPortSubTypeHeadphones)), true)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, kAudioStreamTerminalTypeLine, jack: 1), true)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, kAudioStreamTerminalTypeHeadphones, jack: 0), false)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, kAudioStreamTerminalTypeHeadphones, alive: false), false)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, kAudioStreamTerminalTypeSpeaker, jack: 1), false)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, UInt32(OUTPUT_SPEAKER)), false)
        expectEqual(classify(kAudioDeviceTransportTypeUSB, kAudioStreamTerminalTypeHeadphones, jack: 1), false)
        expectEqual(classify(kAudioDeviceTransportTypeBluetooth, UInt32(OUTPUT_HEADPHONES)), false)
        expectEqual(classify(kAudioDeviceTransportTypeHDMI, kAudioStreamTerminalTypeLine), false)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, kAudioStreamTerminalTypeDigitalAudioInterface), false)
        let updateChecks = runUpdateChecks()
        print("Passed \(checkCount + updateChecks) native policy, output-classification, localization and update checks (\(updateChecks) update checks). No audio played.")
    }
}
