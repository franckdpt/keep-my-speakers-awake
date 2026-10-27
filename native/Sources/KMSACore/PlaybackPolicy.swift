import Foundation

public enum PlaybackBlock: String, Equatable {
    case paused, unavailableSession, wrongOutput, unknownActivity, audioInUse, recentAudio
    case microphoneInUse, unknownCapture, inactive
}

public enum PlaybackTrigger {
    case automatic, manualTest
}

/// Explicit tests bypass the schedule and output-audio checks, never the session, jack, or capture protection.
public struct PlaybackPolicy {
    public static let interval: TimeInterval = 600
    public static let grace: TimeInterval = 120
    public static let outputVolumeThreshold: Double = 0.5
    public static let idleThreshold: TimeInterval = 300

    public static func outputAudioRequiresPause(outputBusy: Bool, outputVolume: Double?) -> Bool {
        guard outputBusy else { return false }
        // Do not assume a safe low volume when the driver cannot report it.
        guard let outputVolume, outputVolume.isFinite, (0...1).contains(outputVolume) else { return true }
        return outputVolume >= outputVolumeThreshold
    }

    public static func block(
        enabled: Bool, trigger: PlaybackTrigger, sessionAvailable: Bool,
        jackUID: String?, smartMode: Bool,
        activityKnown: Bool, audioBusy: Bool, lastBusyAt: Date?, now: Date,
        captureState: CaptureState = .clear,
        outputVolume: Double? = nil, idleSeconds: TimeInterval?
    ) -> PlaybackBlock? {
        if trigger == .automatic && !enabled { return .paused }
        if !sessionAvailable { return .unavailableSession }
        guard let jackUID, !jackUID.isEmpty else { return .wrongOutput }
        // Microphone protection applies to every signal, independently of Smart Mode.
        switch captureState {
        case .microphone: return .microphoneInUse
        case .unknown: return .unknownCapture
        case .clear: break
        }
        if trigger != .manualTest && smartMode {
            if !activityKnown { return .unknownActivity }
            if outputAudioRequiresPause(outputBusy: audioBusy, outputVolume: outputVolume) { return .audioInUse }
            if let lastBusyAt, now.timeIntervalSince(lastBusyAt) < grace { return .recentAudio }
            if !audioBusy {
                guard let idleSeconds, idleSeconds.isFinite, idleSeconds >= 0 else { return .unknownActivity }
                if idleSeconds >= idleThreshold { return .inactive }
            }
        }
        return nil
    }
}

public struct SignalProfile: Decodable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let file: String
    public let hint: String?
}
