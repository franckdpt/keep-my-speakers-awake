import CoreAudio
import IOKit.audio

public enum OutputKind: String, Codable {
    case external, builtInSpeakers, unavailable
}

public enum OutputClassifier {
    /// Classify the selected output, independently of a physical jack sensor or its name.
    public static func classify(transport: UInt32, terminals: [UInt32], sources: [UInt32],
                                alive: Bool, hasOutput: Bool,
                                suboutputs: [OutputKind] = []) -> OutputKind {
        guard alive, hasOutput else { return .unavailable }
        if transport == kAudioDeviceTransportTypeBuiltIn {
            // A selected source takes precedence on devices that share speakers and a port.
            if sources.contains(UInt32(kIOAudioOutputPortSubTypeInternalSpeaker)) { return .builtInSpeakers }
            let externalSources = [kIOAudioOutputPortSubTypeHeadphones, kIOAudioOutputPortSubTypeLine,
                                   kIOAudioOutputPortSubTypeExternalSpeaker, kIOAudioOutputPortSubTypeSPDIF].map { UInt32($0) }
            if sources.contains(where: { externalSources.contains($0) }) { return .external }
            if terminals.contains(kAudioStreamTerminalTypeSpeaker) || terminals.contains(UInt32(OUTPUT_SPEAKER)) {
                return .builtInSpeakers
            }
            let externalTerminals = [kAudioStreamTerminalTypeHeadphones, kAudioStreamTerminalTypeLine,
                                     kAudioStreamTerminalTypeDigitalAudioInterface, UInt32(OUTPUT_HEADPHONES),
                                     UInt32(EXTERNAL_ANALOG_CONNECTOR), UInt32(EXTERNAL_DIGITAL_AUDIO_INTERFACE)]
            return terminals.contains(where: { externalTerminals.contains($0) }) ? .external : .unavailable
        }
        if transport == kAudioDeviceTransportTypeAggregate {
            // Multi-output devices must never carry the signal to the Mac's own speakers.
            return !suboutputs.isEmpty && suboutputs.allSatisfy { $0 == .external } ? .external : .unavailable
        }
        switch transport {
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE,
             kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeAirPlay,
             kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypePCI,
             kAudioDeviceTransportTypeAVB:
            return .external
        default:
            // Virtual/unknown devices do not establish where the sound will physically play.
            return .unavailable
        }
    }
}
