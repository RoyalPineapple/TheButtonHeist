#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains.RepeatUntil.Terminal {
    internal static func initialObservationUnavailableExpectation(
        step: ResolvedRepeatUntilStep,
        receipt: HeistWaitReceipt
    ) -> ExpectationResult.Unmet {
        ExpectationResult.Unmet(receipt.expectation) ?? ExpectationResult.Unmet(
            predicate: step.predicate,
            actual: "initial observation unavailable"
        )
    }

    internal static func timeoutReason(
        step: ResolvedRepeatUntilStep,
        expectation: ExpectationResult.Unmet
    ) -> String {
        let timeout = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            PredicateWait.clampedWaitTimeout(step.timeout)
        )
        return [
            "timed out after \(timeout)s waiting for repeat_until predicate",
            "expected: \(step.predicate.description)",
            "last result: \(expectation.result.actual ?? "not met")",
        ].joined(separator: "; ")
    }
}

extension TheBrains {
    internal func repeatUntilIterationResultsDroppingRedundantFailure(
        _ iterationResults: [HeistExecutionStepResult],
        failedPath: String
    ) -> [HeistExecutionStepResult] {
        iterationResults.filter { $0.path != failedPath }
    }

    internal func repeatUntilInternalStateFailure(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        observed: String
    ) -> HeistExecutionStepResult {
        heistFailedReceipt(
            path: context.path,
            kind: .repeatUntil,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: .repeatUntil(predicate: step.predicateExpression, timeout: step.timeout),
            failure: HeistFailureDetail(
                category: .loop,
                contract: "repeat_until execution reaches a terminal state",
                observed: observed,
                expected: "terminal repeat_until state"
            )
        )
    }

    internal func repeatUntilResolutionFailure(
        _ step: RepeatUntilStep,
        path: String,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
        heistFailedReceipt(
            path: path,
            kind: .repeatUntil,
            durationMs: elapsedMilliseconds(since: start),
            intent: .repeatUntil(predicate: step.predicate, timeout: step.timeout),
            failure: HeistFailureDetail(
                category: .validation,
                contract: "repeat_until predicate resolves before evaluation",
                observed: "could not resolve heist repeat_until predicate: \(error)",
                expected: step.predicate.description
            )
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
