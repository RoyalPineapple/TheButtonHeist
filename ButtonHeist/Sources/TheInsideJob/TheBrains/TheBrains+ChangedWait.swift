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
        let resolvedTimeout: WaitTimeout
        let resolved: ResolvedAccessibilityPredicate
        do {
            resolvedTimeout = try WaitTimeout(validatingSeconds: timeout)
            resolved = try predicate.resolve(in: .empty)
        } catch {
            return .failure(
                payload: .wait,
                failureKind: .validationError,
                message: "could not resolve changed wait predicate: \(error)"
            )
        }
        let result = await executeSettlementCommand(Settlement.Command(
            observing: predicate,
            resolved: resolved,
            timeout: resolvedTimeout
        ))
        return Settlement.ResultProjector.projectWait(result).actionResult
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
