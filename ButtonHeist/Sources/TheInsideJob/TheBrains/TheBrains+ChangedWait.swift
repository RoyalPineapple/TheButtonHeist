#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    /// Internal changed-wait entry point through the canonical HeistExecution path.
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

        let predicate = expectation ?? .elementsChanged
        do {
            let resolvedTimeout = try WaitTimeout(validatingSeconds: timeout)
            let plan = try HeistPlan(body: [
                .wait(WaitStep(predicate: predicate, timeout: resolvedTimeout)),
            ])
            return await executeSingleStepPlan(plan, fallbackPayload: .wait)
        } catch {
            return .failure(
                payload: .wait,
                failureKind: .validationError,
                message: "could not resolve changed wait predicate: \(error)"
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
