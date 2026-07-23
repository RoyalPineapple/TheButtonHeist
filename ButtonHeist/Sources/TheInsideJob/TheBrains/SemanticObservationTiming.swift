#if canImport(UIKit)
#if DEBUG
import Foundation

enum SemanticObservationTiming {
    static let defaultTimeout: Double = 1
}

struct SemanticObservationDeadline: Sendable, Equatable {
    let start: RuntimeElapsed.Instant
    private let timeout: Duration

    init(start: RuntimeElapsed.Instant, timeoutSeconds: Double) {
        precondition(timeoutSeconds.isFinite && timeoutSeconds >= 0, "observation timeout must be finite and non-negative")
        self.start = start
        timeout = .seconds(timeoutSeconds)
    }

    init(start: RuntimeElapsed.Instant, timeoutMs: Int) {
        precondition(timeoutMs >= 0, "observation timeout must be non-negative")
        self.init(start: start, timeoutSeconds: Double(timeoutMs) / 1_000)
    }

    var timeoutSeconds: Double {
        timeout / .seconds(1)
    }

    func hasTimeRemaining(at now: RuntimeElapsed.Instant) -> Bool {
        now < deadline
    }

    func remainingSeconds(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Double {
        max(0, now.duration(to: deadline) / .seconds(1))
    }

    func remainingDuration(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Duration {
        let remaining = now.duration(to: deadline)
        return remaining > .zero ? remaining : .zero
    }

    func elapsedMilliseconds(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Int {
        max(0, Int(start.duration(to: now) / .milliseconds(1)))
    }

    func reserving(
        _ seconds: Double,
        at now: RuntimeElapsed.Instant = RuntimeElapsed.now
    ) -> Self {
        precondition(seconds.isFinite && seconds >= 0, "observation reservation must be finite and non-negative")
        return Self(start: now, timeoutSeconds: max(0, remainingSeconds(at: now) - seconds))
    }

    private var deadline: RuntimeElapsed.Instant {
        start.advanced(by: timeout)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
