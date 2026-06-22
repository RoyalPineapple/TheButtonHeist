#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    /// Changed-predicate wait entry point. It subscribes to the same settled
    /// observation event stream as every other wait and evaluates only event
    /// deltas, never command-local baseline state.
    func executeChangedWait(timeout: TimeInterval, expectation: AccessibilityPredicate?) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: .wait)
        }
        guard beginChangedWait() else {
            var builder = ActionResultBuilder(method: .wait)
            builder.message = "wait already in progress"
            return builder.failure(errorKind: .actionFailed)
        }
        defer { finishChangedWait() }

        let predicate = expectation ?? .changed(.elements)
        let receipt = await interactionObservation.waitForPredicate(WaitStep(predicate: predicate, timeout: timeout))
        return receipt.actionResult
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
