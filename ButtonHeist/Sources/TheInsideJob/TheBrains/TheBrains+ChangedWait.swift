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
            return runtimeInactiveResult(payload: .wait)
        }
        guard beginChangedWait() else {
            return .failure(
                payload: .wait,
                failureKind: .actionFailed,
                message: "wait already in progress"
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
                payload: .wait,
                failureKind: .validationError,
                message: "could not resolve changed wait predicate: \(error)"
            )
        }
        let result = await interactionCoordinator.waitForPredicate(
            step,
            onReadyToPoll: onReadyToPoll
        )
        return result.outcome.actionResult
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
