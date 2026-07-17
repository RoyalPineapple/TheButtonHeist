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
            method: .wait,
            errorKind: .actionFailed,
            message: observed,
            evidence: .none
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
        guard let evidence = HeistFailedInvocationEvidence(evidence) else {
            preconditionFailure("failed invocation expectation resolution must prove failure")
        }
        return .invocation(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            invocationPath: context.invoke.path,
            argument: context.invoke.argument,
            completion: .failed(evidence: .observed(evidence), failure: HeistFailureDetail(
                category: .expectation,
                contract: "heist invocation expectation predicate resolves before evaluation",
                observed: observed,
                expected: expectation.predicate.description
            ))
        )
    }

    internal func completedInvocationResult(
        context: InvocationExecutionContext,
        childExecution: [HeistExecutionStepResult],
        expectationContext: InvocationExpectationContext?,
        expectationOutcome: InvocationExpectationOutcome
    ) -> HeistExecutionStepResult {
        let expectationEvidence = expectationOutcome.receipt.map {
            invocationExpectationEvidence(receipt: $0, context: expectationContext)
        }
        let invocationExpectation = expectationEvidence.map {
            HeistInvocationEvidence.InvocationExpectationEvidence.wait($0)
        }
        switch HeistExecutedChildren(childExecution) {
        case .aborted(let children):
            let evidence = HeistInvocationEvidence.childFailed(path: children.abortedAtPath)
            guard let evidence = HeistFailedInvocationEvidence(evidence) else {
                preconditionFailure("child-aborted invocation must prove failure")
            }
            return .invocation(
                path: context.path,
                durationMs: elapsedMilliseconds(since: context.start),
                invocationPath: context.invoke.path,
                argument: context.invoke.argument,
                completion: .childAborted(
                    evidence: .observed(evidence),
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
                guard let evidence = HeistFailedInvocationEvidence(evidence) else {
                    preconditionFailure("failed invocation expectation must prove failure")
                }
                return .invocation(
                    path: context.path,
                    durationMs: elapsedMilliseconds(since: context.start),
                    invocationPath: context.invoke.path,
                    argument: context.invoke.argument,
                    completion: .failed(evidence: .observed(evidence), failure: detail, children: children)
                )
            case .notEvaluated, .matched:
                guard let evidence = HeistPassedInvocationEvidence(evidence) else {
                    preconditionFailure("completed invocation must carry passing evidence")
                }
                return .invocation(
                    path: context.path,
                    durationMs: elapsedMilliseconds(since: context.start),
                    invocationPath: context.invoke.path,
                    argument: context.invoke.argument,
                    completion: .passed(evidence: evidence, children: children)
                )
            }
        }
    }

    private func invocationExpectationEvidence(
        receipt: HeistWaitReceipt,
        context: InvocationExpectationContext?
    ) -> HeistWaitEvidence {
        let finalSummary = receipt.observationSummary ?? receipt.result.expectation.actual
        if let expectation = ExpectationResult.Met(receipt.result.expectation),
           let check = HeistWaitEvidence.MatchedCheck(
               actionResult: receipt.result.actionResult,
               expectation: expectation
           ) {
            return .matched(
                check,
                baselineSummary: context?.baseline.observationSummary,
                finalSummary: finalSummary
            )
        }
        guard let check = HeistWaitEvidence.UnmatchedCheck(
            actionResult: receipt.result.actionResult,
            expectation: receipt.result.expectation
        ) else {
            preconditionFailure("Failed invocation expectation evidence requires a failed action result or unmet expectation")
        }
        return .failed(
            check,
            baselineSummary: context?.baseline.observationSummary,
            finalSummary: finalSummary
        )
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
