import Foundation

/// One-second fixed-window rate limiter for a single client message stream.
/// It owns both the recent-message window and the once-per-window notification bit.
struct MessageRateLimiter: Equatable, Sendable {
    static let defaultMaxMessagesPerSecond = 30

    let maxMessagesPerSecond: Int
    private(set) var timestamps: [Date]
    private(set) var rateLimitNotified: Bool

    init(
        maxMessagesPerSecond: Int = Self.defaultMaxMessagesPerSecond,
        timestamps: [Date] = [],
        rateLimitNotified: Bool = false
    ) {
        self.maxMessagesPerSecond = maxMessagesPerSecond
        self.timestamps = timestamps
        self.rateLimitNotified = rateLimitNotified
    }

    /// Records a message attempt. Returns true when the caller should drop it.
    mutating func recordMessage(at now: Date = Date()) -> Bool {
        timestamps = timestamps.filter { now.timeIntervalSince($0) < 1.0 }
        let isLimited = timestamps.count >= maxMessagesPerSecond
        if !isLimited {
            timestamps.append(now)
            rateLimitNotified = false
        }
        return isLimited
    }

    /// Marks that this rate-limit window has notified the client.
    /// Returns true only for the first notification in the current window.
    mutating func markNotifiedIfNeeded() -> Bool {
        guard !rateLimitNotified else { return false }
        rateLimitNotified = true
        return true
    }
}
