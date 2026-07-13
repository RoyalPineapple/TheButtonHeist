#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    /// Changed-predicate wait entry point. It subscribes to the same settled
    /// observation event stream as every other wait and evaluates only event
    /// deltas, never command-local baseline state.
    func executeChangedWait(
        timeout: TimeInterval,
        expectation: AccessibilityPredicate<RootContext>?
    ) async -> ActionResult {
        guard semanticObservationIsActive else {
            return runtimeInactiveResult(method: .wait)
        }
        guard beginChangedWait() else {
            return .failure(
                method: .wait,
                errorKind: .actionFailed,
                message: "wait already in progress",
                evidence: .none
            )
        }
        defer { finishChangedWait() }

        let predicate = expectation ?? .changed(.elements())
        let receipt = await interactionObservation.waitForPredicate(WaitStep(predicate: predicate, timeout: timeout))
        return receipt.actionResult
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
