#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

extension TheBrains {
    /// Legacy wire command entry point. It now subscribes to the same settled
    /// observation event stream as every other wait and evaluates only event
    /// deltas, never command-local baseline state.
    func executeWaitForChange(timeout: TimeInterval, expectation: AccessibilityPredicate?) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: .wait)
        }
        guard beginWaitForChange() else {
            var builder = ActionResultBuilder(method: .wait)
            builder.message = "wait already in progress"
            return builder.failure(errorKind: .actionFailed)
        }
        defer { finishWaitForChange() }

        let predicate = expectation ?? .changed(.elements)
        let receipt = await interactionObservation.waitForPredicateAfterCurrentSettledSequence(
            WaitStep(predicate: predicate, timeout: timeout)
        )
        return receipt.actionResult
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
