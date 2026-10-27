import Foundation

/// One return event after a known idle period; unknown readings never establish absence.
public struct PresenceTracker {
    private var wasIdle = false
    private var suspendedAt: Date?

    public init() {}

    /// Preserve absence through lock/screen sleep; repeated notifications must not restart it.
    public mutating func suspend(at date: Date) {
        if suspendedAt == nil { suspendedAt = date }
    }

    public mutating func update(idleSeconds: TimeInterval?, at date: Date = Date()) -> Bool {
        guard let idleSeconds, idleSeconds.isFinite, idleSeconds >= 0 else {
            reset()
            return false
        }
        let isIdle = idleSeconds >= PlaybackPolicy.idleThreshold
        let longSuspension = suspendedAt.map { date.timeIntervalSince($0) >= PlaybackPolicy.idleThreshold } ?? false
        let returned = (wasIdle || longSuspension) && !isIdle
        suspendedAt = nil
        wasIdle = isIdle
        return returned
    }

    public mutating func reset() { wasIdle = false; suspendedAt = nil }
}
