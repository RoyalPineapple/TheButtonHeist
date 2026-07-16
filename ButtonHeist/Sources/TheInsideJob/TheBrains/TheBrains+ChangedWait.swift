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
        expectation: AccessibilityPredicate?,
        onReadyToPoll: PredicateWait.ReadyToPoll? = nil
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
        let step: ResolvedWaitRuntimeInput
        do {
            step = try ResolvedWaitRuntimeInput(
                resolving: WaitStep(
                    predicate: predicate,
                    timeout: WaitTimeout(validatingSeconds: timeout)
                ),
                in: .empty
            )
        } catch {
            return .failure(
                method: .wait,
                errorKind: .validationError,
                message: "could not resolve changed wait predicate: \(error)",
                evidence: .none
            )
        }
        let receipt = await waitForPredicate(
            step,
            onReadyToPoll: onReadyToPoll
        )
        return receipt.actionResult
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
