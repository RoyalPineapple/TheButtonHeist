#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    /// Internal changed-wait entry point through the canonical Settlement path.
    func executeChangedWait(
        timeout: TimeInterval,
        expectation: AccessibilityPredicate?
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
        let result = await executeSettlementWait(step)
        return result.outcome.actionResult
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
