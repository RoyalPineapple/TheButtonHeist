import Foundation

/// One-second fixed-window rate limiter for a single client message stream.
/// It owns both the recent-message window and the once-per-window notification state.
struct MessageRateLimiter: Equatable, Sendable {
    static let defaultMaxMessagesPerSecond = 30

    let maxMessagesPerSecond: Int
    private var state: State

    init(maxMessagesPerSecond: Int = Self.defaultMaxMessagesPerSecond) {
        self.maxMessagesPerSecond = maxMessagesPerSecond
        self.state = .accepting(timestamps: [])
    }

    /// Records a message attempt. Returns true when the caller should drop it.
    mutating func recordMessage(at now: Date = Date()) -> Bool {
        let activeTimestamps = state.timestamps.filter { now.timeIntervalSince($0) < 1.0 }
        guard activeTimestamps.count < maxMessagesPerSecond else {
            state = state.limited(with: activeTimestamps)
            return true
        }

        state = .accepting(timestamps: activeTimestamps + [now])
        return false
    }

    /// Marks that this rate-limit window has notified the client.
    /// Returns true only for the first notification in the current window.
    mutating func markNotifiedIfNeeded() -> Bool {
        switch state {
        case .accepting:
            return false
        case .limitedNotified:
            return false
        case .limitedUnnotified(let timestamps):
            state = .limitedNotified(timestamps: timestamps)
            return true
        }
    }

    private enum State: Equatable, Sendable {
        case accepting(timestamps: [Date])
        case limitedUnnotified(timestamps: [Date])
        case limitedNotified(timestamps: [Date])

        var timestamps: [Date] {
            switch self {
            case .accepting(let timestamps),
                 .limitedUnnotified(let timestamps),
                 .limitedNotified(let timestamps):
                return timestamps
            }
        }

        func limited(with timestamps: [Date]) -> Self {
            switch self {
            case .limitedNotified:
                return .limitedNotified(timestamps: timestamps)
            case .accepting,
                 .limitedUnnotified:
                return .limitedUnnotified(timestamps: timestamps)
            }
        }
    }
}
