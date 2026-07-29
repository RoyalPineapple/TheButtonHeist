#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

enum SemanticObservationTiming {
    /// How long a caller waits on a reading before the timeout answers instead.
    /// Timeout is the only failure, so this is the only budget there is.
    static let defaultTimeout: Duration = .seconds(1)

    /// Below this there is no point starting a viewport transition: the move
    /// would not have time to be read before the budget ran out.
    static let viewportTransitionMinimumBudgetMs = 32
}

struct SemanticObservationDeadline: Sendable, Equatable {
    let start: RuntimeElapsed.Instant
    let timeoutSeconds: Double

    init(start: RuntimeElapsed.Instant, timeoutSeconds: Double) {
        precondition(timeoutSeconds.isFinite && timeoutSeconds >= 0, "observation timeout must be finite and non-negative")
        self.start = start
        self.timeoutSeconds = timeoutSeconds
    }

    init(start: RuntimeElapsed.Instant, timeout: Duration) {
        self.init(start: start, timeoutSeconds: timeout / .seconds(1))
    }

    init(start: RuntimeElapsed.Instant, timeoutMs: Int) {
        precondition(timeoutMs >= 0, "observation timeout must be non-negative")
        self.init(start: start, timeoutSeconds: Double(timeoutMs) / 1_000)
    }

    func hasTimeRemaining(at now: RuntimeElapsed.Instant) -> Bool {
        elapsedSeconds(at: now) < timeoutSeconds
    }

    func remainingSeconds(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Double {
        max(0, timeoutSeconds - elapsedSeconds(at: now))
    }

    func remainingDuration(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Duration {
        .saturatingSeconds(remainingSeconds(at: now))
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

    private func elapsedSeconds(at now: RuntimeElapsed.Instant) -> Double {
        max(0, start.duration(to: now) / .seconds(1))
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
