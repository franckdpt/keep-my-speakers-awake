import Foundation

/// An app-owned schedule: no checks while the process is stopped, no catch-up burst
/// after sleep, and a shorter retry if the network was unavailable.
public struct UpdateCheckSchedule {
    public static let dailyInterval: TimeInterval = 24 * 60 * 60
    public static let retryInterval: TimeInterval = 60 * 60
    public private(set) var nextCheck: Date?
    private var lastStarted: Date?

    public init() {}

    public func isDue(at now: Date) -> Bool {
        guard let nextCheck, let lastStarted else { return true }
        return now >= nextCheck || now < lastStarted
    }

    public mutating func started(at now: Date) {
        lastStarted = now
        nextCheck = now.addingTimeInterval(Self.dailyInterval)
    }

    public mutating func finished(success: Bool, at now: Date) {
        lastStarted = now
        nextCheck = now.addingTimeInterval(success ? Self.dailyInterval : Self.retryInterval)
    }
}
