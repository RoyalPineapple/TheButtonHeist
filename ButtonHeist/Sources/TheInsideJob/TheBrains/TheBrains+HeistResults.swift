#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
import TheScore

extension TheBrains {

    internal func executeWarnStep(
        _ warn: WarnStep,
        path: HeistExecutionPath,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        .warning(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            message: warn.message,
            completion: .passed()
        )
    }

    internal func executeFailStep(
        _ fail: FailStep,
        path: HeistExecutionPath,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        .failure(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            message: fail.message,
            completion: .failed(failure: HeistFailureDetail(
                category: .explicitFailure,
                contract: "explicit heist failure",
                observed: fail.message.rawValue
            ))
        )
    }

    internal func recursiveInvocationResult(
        context: InvocationExecutionContext,
        resolvedInvocationName: HeistInvocationPath
    ) -> HeistExecutionStepResult {
        let observed = "recursive heist run \(resolvedInvocationName)"
        return .invocation(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            invocationPath: context.invoke.path,
            argument: context.invoke.argument,
            completion: .failed(evidence: .unavailable, failure: HeistFailureDetail(
                category: .invocation,
                contract: "heist invocation must not recurse",
                observed: observed
            ))
        )
    }

    internal func unknownInvocationResult(
        context: InvocationExecutionContext
    ) -> HeistExecutionStepResult {
        let observed = "unknown heist run \(context.requestedName)"
        return .invocation(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            invocationPath: context.invoke.path,
            argument: context.invoke.argument,
            completion: .failed(evidence: .unavailable, failure: HeistFailureDetail(
                category: .invocation,
                contract: "heist invocation path resolves to a definition",
                observed: observed,
                expected: context.requestedName.description
            ))
        )
    }

    internal func invocationBindingFailureResult(
        context: InvocationExecutionContext,
        error: Error
    ) -> HeistExecutionStepResult {
        let observed = "could not bind heist run argument: \(error)"
        return .invocation(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            invocationPath: context.invoke.path,
            argument: context.invoke.argument,
            completion: .failed(evidence: .unavailable, failure: HeistFailureDetail(
                category: .validation,
                contract: "heist invocation argument binds to the target parameter",
                observed: observed
            ))
        )
    }

    internal func invocationExpectationResolutionFailureResult(
        context: InvocationExecutionContext,
        expectation: WaitStep,
        error: Error
    ) -> HeistExecutionStepResult {
        let observed = "could not resolve heist run expectation: \(error)"
        let expectationActionResult = ActionResult.failure(
            payload: .wait,
            failureKind: .actionFailed,
            message: observed
        )
        let expectationResult = ExpectationResult(
            met: false,
            predicate: nil,
            actual: observed
        )
        let evidence = HeistInvocationEvidence.completed(
            expectation: .result(
                actionResult: expectationActionResult,
                expectation: expectationResult
            )
        )
        return .invocation(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            invocationPath: context.invoke.path,
            argument: context.invoke.argument,
            completion: .failed(evidence: .observed(.init(admitted: evidence)), failure: HeistFailureDetail(
                category: .expectation,
                contract: "heist invocation expectation predicate resolves before evaluation",
                observed: observed,
                expected: expectation.predicate.description
            ))
        )
    }

    internal func completedInvocationResult(
        context: InvocationExecutionContext,
        childExecution: HeistExecutedChildren,
        expectationContext: InvocationExpectationContext?,
        expectationOutcome: InvocationExpectationOutcome
    ) -> HeistExecutionStepResult {
        let expectationEvidence = expectationOutcome.result.map {
            invocationExpectationEvidence(result: $0, context: expectationContext)
        }
        let invocationExpectation = expectationEvidence.map {
            HeistInvocationEvidence.InvocationExpectationEvidence.wait($0)
        }
        switch childExecution {
        case .aborted(let children):
            let evidence = HeistInvocationEvidence.childFailed(path: children.abortedAtPath)
            return .invocation(
                path: context.path,
                durationMs: elapsedMilliseconds(since: context.start),
                invocationPath: context.invoke.path,
                argument: context.invoke.argument,
                completion: .childAborted(
                    evidence: .observed(.init(admitted: evidence)),
                    failure: childFailureDetail(
                        category: .invocation,
                        childPath: children.abortedAtPath
                    ),
                    children: children
                )
            )
        case .passed(let children):
            let evidence = HeistInvocationEvidence.completed(expectation: invocationExpectation)
            switch expectationOutcome {
            case .failed(_, let detail):
                return .invocation(
                    path: context.path,
                    durationMs: elapsedMilliseconds(since: context.start),
                    invocationPath: context.invoke.path,
                    argument: context.invoke.argument,
                    completion: .failed(
                        evidence: .observed(.init(admitted: evidence)),
                        failure: detail,
                        children: children
                    )
                )
            case .notEvaluated, .matched:
                return .invocation(
                    path: context.path,
                    durationMs: elapsedMilliseconds(since: context.start),
                    invocationPath: context.invoke.path,
                    argument: context.invoke.argument,
                    completion: .passed(evidence: .init(admitted: evidence), children: children)
                )
            }
        }
    }

    private func invocationExpectationEvidence(
        result: HeistWaitResult,
        context: InvocationExpectationContext?
    ) -> HeistWaitEvidence {
        let finalSummary = result.observationSummary ?? result.outcome.expectation.actual
        switch result.outcome {
        case .matched(let actionResult, let expectation):
            return .matched(
                .init(executed: actionResult, expectation: expectation),
                baselineSummary: context?.baseline.observationSummary,
                finalSummary: finalSummary
            )
        case .unmatched(let actionResult, let expectation):
            return .failed(
                .init(executed: actionResult, expectation: expectation.result),
                baselineSummary: context?.baseline.observationSummary,
                finalSummary: finalSummary
            )
        }
    }

    internal func heistExecutionMessage(
        completedCount: Int,
        abortedAtPath: HeistExecutionPath?
    ) -> String {
        if let abortedAtPath {
            return "Heist execution stopped at \(abortedAtPath) after \(completedCount) executed step(s)"
        }
        return "Heist execution completed \(completedCount) step(s)"
    }

    internal func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
