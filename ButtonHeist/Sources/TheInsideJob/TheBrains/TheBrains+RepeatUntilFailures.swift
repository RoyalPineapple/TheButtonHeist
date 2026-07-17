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
        let durationMs = elapsedMilliseconds(since: context.start)
        let declaration = HeistRepeatUntilDeclaration(
            predicate: step.predicateExpression,
            timeout: step.timeout
        )
        let construction = HeistExecutionStepResult.construct(
            path: context.path,
            durationMs: durationMs,
            node: .repeatUntil(
                declaration: declaration,
                completion: .failed(evidence: .unavailable, failure: HeistFailureDetail(
                    category: .loop,
                    contract: "repeat_until execution reaches a terminal state",
                    observed: observed,
                    expected: "terminal repeat_until state"
                ))
            )
        )
        return receiptResult(
            construction,
            path: context.path,
            durationMs: durationMs
        )
    }

    internal func repeatUntilResolutionFailure(
        _ step: RepeatUntilStep,
        path: HeistExecutionPath,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let declaration = HeistRepeatUntilDeclaration(step)
        let construction = HeistExecutionStepResult.construct(
            path: path,
            durationMs: durationMs,
            node: .repeatUntil(
                declaration: declaration,
                completion: .failed(evidence: .unavailable, failure: HeistFailureDetail(
                    category: .validation,
                    contract: "repeat_until predicate resolves before evaluation",
                    observed: "could not resolve heist repeat_until predicate: \(error)",
                    expected: step.predicate.description
                ))
            )
        )
        return receiptResult(
            construction,
            path: path,
            durationMs: durationMs
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
