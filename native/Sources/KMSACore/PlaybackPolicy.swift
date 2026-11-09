import Foundation

public enum PlaybackBlock: String, Equatable {
    case paused, unavailableSession, wrongOutput, unknownActivity
    case microphoneInUse, unknownCapture, inactive
}

public enum PlaybackTrigger {
    case automatic, manualTest
}

/// Explicit tests bypass the schedule and inactivity check, never the session, screen, jack, or capture protection.
public struct PlaybackPolicy {
    public static let interval: TimeInterval = 600
    public static let idleThreshold: TimeInterval = 300

    public static func block(
        enabled: Bool, trigger: PlaybackTrigger, sessionAvailable: Bool, screenAvailable: Bool = true,
        jackUID: String?, smartMode: Bool,
        activityKnown: Bool, audioBusy: Bool,
        captureState: CaptureState = .clear,
        idleSeconds: TimeInterval?
    ) -> PlaybackBlock? {
        if trigger == .automatic && !enabled { return .paused }
        if !sessionAvailable { return .unavailableSession }
        // A dark/locked screen does not end a listening session. Only automatic Smart
        // Mode signals may continue, with known output activity in the current user session.
        if !screenAvailable && !(trigger == .automatic && smartMode && activityKnown && audioBusy) {
            return .unavailableSession
        }
        guard let jackUID, !jackUID.isEmpty else { return .wrongOutput }
        // Microphone protection applies to every signal, independently of Smart Mode.
        switch captureState {
        case .microphone: return .microphoneInUse
        case .unknown: return .unknownCapture
        case .clear: break
        }
        if trigger != .manualTest && smartMode {
            if !activityKnown { return .unknownActivity }
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
