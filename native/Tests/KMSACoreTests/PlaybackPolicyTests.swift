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
               output: String? = "external-a", smart: Bool = true,
               known: Bool = true, busy: Bool = false,
               capture: CaptureState = .clear,
               idle: TimeInterval? = 0,
               trigger: PlaybackTrigger? = nil) -> PlaybackBlock? {
        PlaybackPolicy.block(enabled: enabled, trigger: trigger ?? (test ? .manualTest : .automatic), sessionAvailable: session, screenAvailable: screen,
                             externalOutputUID: output, smartMode: smart,
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
                expectEqual(block(screen: screen, output: nil, busy: true, idle: idle), .wrongOutput)
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
        expectEqual(block(output: nil), .wrongOutput)
        expectEqual(block(output: ""), .wrongOutput)
        expectEqual(block(known: false), .unknownActivity)
        expectNil(block(busy: true))
    }

    func testManualTestCannotEscapeThePhysicalOutputAndSessionGate() {
        expectNil(block(enabled: false, test: true, known: false, busy: true))
        expectEqual(block(test: true, session: false), .unavailableSession)
        expectEqual(block(test: true, output: nil), .wrongOutput)
    }

    func testSmartToggleCannotDisableTheOutputProtection() {
        expectNil(block(smart: false, known: false, busy: true))
        expectEqual(block(output: nil, smart: false), .wrongOutput)
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
        expectEqual(block(test: true, output: nil, capture: .microphone), .wrongOutput)
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
        expectEqual(AppText.noExternalOutput.localized(in: .french), "Aucune sortie audio externe utilisable")
        expectEqual(AppText.noExternalOutput.localized(in: .english), "No usable external audio output")
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
        policy.testSmartToggleCannotDisableTheOutputProtection()
        policy.testMicrophoneProtectionAlwaysBlocksSignals()
        policy.testMicrophoneDetection()
        policy.testLanguageUsesOnlyThePrimaryPreference()
        policy.testPresenceReturnIsOneEventAfterFiveMinutes()
        policy.testPresenceSurvivesSessionSuspension()
        policy.testIdleRequiresBothNoInputAndNoAudio()
        func classify(_ transport: UInt32 = kAudioDeviceTransportTypeBuiltIn,
                      _ terminals: [UInt32] = [], sources: [UInt32] = [], alive: Bool = true,
                      hasOutput: Bool = true, suboutputs: [OutputKind] = []) -> OutputKind {
            OutputClassifier.classify(transport: transport, terminals: terminals, sources: sources,
                                      alive: alive, hasOutput: hasOutput, suboutputs: suboutputs)
        }
        for terminal in [kAudioStreamTerminalTypeHeadphones, kAudioStreamTerminalTypeLine,
                         kAudioStreamTerminalTypeDigitalAudioInterface, UInt32(OUTPUT_HEADPHONES)] {
            expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, [terminal]), .external)
        }
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, sources: [UInt32(kIOAudioOutputPortSubTypeHeadphones)]), .external)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, [kAudioStreamTerminalTypeSpeaker]), .builtInSpeakers)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, [UInt32(OUTPUT_SPEAKER)]), .builtInSpeakers)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, [kAudioStreamTerminalTypeHeadphones],
                             sources: [UInt32(kIOAudioOutputPortSubTypeInternalSpeaker)]), .builtInSpeakers)
        expectEqual(classify(kAudioDeviceTransportTypeBuiltIn, [kAudioStreamTerminalTypeSpeaker],
                             sources: [UInt32(kIOAudioOutputPortSubTypeHeadphones)]), .external)
        expectEqual(classify(), .unavailable)
        for transport in [kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetooth,
                          kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeHDMI,
                          kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeAirPlay,
                          kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeFireWire,
                          kAudioDeviceTransportTypePCI, kAudioDeviceTransportTypeAVB] {
            // No terminal metadata or jack connection sensor is required on external hardware.
            expectEqual(classify(transport), .external)
            expectEqual(classify(transport, [kAudioStreamTerminalTypeSpeaker]), .external)
            expectEqual(classify(transport, alive: false), .unavailable)
            expectEqual(classify(transport, hasOutput: false), .unavailable)
        }
        for transport in [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeUnknown, UInt32.max] {
            expectEqual(classify(transport, [kAudioStreamTerminalTypeHeadphones]), .unavailable)
        }
        expectEqual(classify(kAudioDeviceTransportTypeAggregate, suboutputs: [.external, .external]), .external)
        for members: [OutputKind] in [[], [.external, .builtInSpeakers], [.external, .unavailable], [.builtInSpeakers]] {
            expectEqual(classify(kAudioDeviceTransportTypeAggregate, suboutputs: members), .unavailable)
        }
        expectEqual(AppText.builtInSpeakers.localized(in: .french), "Haut-parleurs du Mac utilisés · aucun réveil nécessaire")
        expectEqual(AppText.builtInSpeakers.localized(in: .english), "Mac speakers in use · no wake-up needed")
        let updateChecks = runUpdateChecks()
        print("Passed \(checkCount + updateChecks) native policy, output-classification, localization and update checks (\(updateChecks) update checks). No audio played.")
    }
}
