#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains.RepeatUntil.Terminal {
    internal static func timeoutReason(
        step: ResolvedRepeatUntilStep,
        expectation: ExpectationResult.Unmet
    ) -> String {
        let timeout = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            step.timeout.seconds
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
        failedPath: HeistExecutionPath
    ) -> [HeistExecutionStepResult] {
        iterationResults.filter { $0.path != failedPath }
    }

    internal func repeatUntilInternalStateFailure(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        observed: String
    ) -> HeistExecutionStepResult {
        .repeatUntil(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            predicate: step.predicateExpression,
            timeout: step.timeout,
            completion: .failed(evidence: .unavailable, failure: HeistFailureDetail(
                category: .loop,
                contract: "repeat_until execution reaches a terminal state",
                observed: observed,
                expected: "terminal repeat_until state"
            ))
        )
    }

    internal func repeatUntilResolutionFailure(
        _ step: RepeatUntilStep,
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
        .repeatUntil(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            predicate: step.predicate,
            timeout: step.timeout,
            completion: .failed(evidence: .unavailable, failure: HeistFailureDetail(
                category: .validation,
                contract: "repeat_until predicate resolves before evaluation",
                observed: "could not resolve heist repeat_until predicate: \(error)",
                expected: step.predicate.description
            ))
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
