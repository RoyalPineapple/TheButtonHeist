#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

enum SemanticObservationTiming {
    /// Default budget for action leaves and external observation requests.
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

    func hasTimeRemaining(at now: RuntimeElapsed.Instant) -> Bool {
        elapsedSeconds(at: now) < timeoutSeconds
    }

    func remainingSeconds(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Double {
        max(0, timeoutSeconds - elapsedSeconds(at: now))
    }

    func remainingDuration(at now: RuntimeElapsed.Instant = RuntimeElapsed.now) -> Duration {
        .saturatingSeconds(remainingSeconds(at: now))
    }

    var budgetMilliseconds: Int {
        Int((timeoutSeconds * 1_000).rounded(.up))
    }

    private func elapsedSeconds(at now: RuntimeElapsed.Instant) -> Double {
        max(0, start.duration(to: now) / .seconds(1))
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
