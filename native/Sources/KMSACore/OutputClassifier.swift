import CoreAudio
import IOKit.audio

public enum OutputClassifier {
    public static func isBuiltInJack(transport: UInt32, terminals: [UInt32], sources: [UInt32],
                                     jackControl: UInt32?, alive: Bool) -> Bool {
        guard alive, transport == kAudioDeviceTransportTypeBuiltIn, jackControl != 0 else { return false }
        // Apple drivers expose both modern Core Audio terminal FourCCs and legacy IOAudio terminal types.
        let analogTerminal = terminals.contains(kAudioStreamTerminalTypeHeadphones)
            || terminals.contains(kAudioStreamTerminalTypeLine)
            || terminals.contains(UInt32(OUTPUT_HEADPHONES))
        let analogSource = sources.contains(UInt32(kIOAudioOutputPortSubTypeHeadphones))
            || sources.contains(UInt32(kIOAudioOutputPortSubTypeLine))
        return analogTerminal || analogSource
    }
}
