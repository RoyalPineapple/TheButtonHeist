import Foundation

/// One-second fixed-window rate limiter for a single client message stream.
/// It owns both the recent-message window and the once-per-window notification state.
extension ClientAdmission {
private enum RateLimitState: Equatable, Sendable {
    case accepting(timestamps: [Date])
    case limitedNotified(timestamps: [Date])

    var timestamps: [Date] {
        switch self {
        case .accepting(let timestamps),
             .limitedNotified(let timestamps):
            return timestamps
        }
    }
}

enum RateLimitDecision: Equatable, Sendable {
    case accept
    case drop(shouldNotify: Bool)
}

struct RateLimiter: Equatable, Sendable {
    static let defaultMaxMessagesPerSecond = 30

    let maxMessagesPerSecond: Int
    private var state: RateLimitState

    init(maxMessagesPerSecond: Int = Self.defaultMaxMessagesPerSecond) {
        self.maxMessagesPerSecond = maxMessagesPerSecond
        self.state = .accepting(timestamps: [])
    }

    mutating func admitMessage(at now: Date = Date()) -> RateLimitDecision {
        let activeTimestamps = state.timestamps.filter { now.timeIntervalSince($0) < 1.0 }
        guard activeTimestamps.count < maxMessagesPerSecond else {
            let shouldNotify: Bool
            switch state {
            case .accepting:
                shouldNotify = true
            case .limitedNotified:
                shouldNotify = false
            }
            state = .limitedNotified(timestamps: activeTimestamps)
            return .drop(shouldNotify: shouldNotify)
        }

        state = .accepting(timestamps: activeTimestamps + [now])
        return .accept
    }

}
}
