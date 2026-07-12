#if canImport(UIKit)
#if DEBUG
import Foundation

import ThePlans
import TheScore

extension TheBrains {

    internal func executeWarnStep(
        _ warn: WarnStep,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        heistWarningReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: .warn(message: warn.message),
            warning: HeistExecutionWarning(path: path, message: warn.message)
        )
    }

    internal func executeFailStep(
        _ fail: FailStep,
        path: String,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        heistExplicitFailureReceipt(
            path: path,
            durationMs: elapsedMilliseconds(since: start),
            intent: .fail(message: fail.message),
            failure: HeistFailureDetail(
                category: .explicitFailure,
                contract: "explicit heist failure",
                observed: fail.message
            )
        )
    }

    internal func recursiveInvocationResult(
        context: InvocationExecutionContext,
        resolvedInvocationName: String
    ) -> HeistExecutionStepResult {
        let observed = "recursive heist run \(resolvedInvocationName)"
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(HeistInvocationEvidence.invocation(
                context.invoke,
                name: context.requestedName
            )),
            failure: HeistFailureDetail(
                category: .invocation,
                contract: "heist invocation must not recurse",
                observed: observed
            )
        )
    }

    internal func unknownInvocationResult(
        context: InvocationExecutionContext
    ) -> HeistExecutionStepResult {
        let observed = "unknown heist run \(context.requestedName)"
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(HeistInvocationEvidence.invocation(
                context.invoke,
                name: context.requestedName
            )),
            failure: HeistFailureDetail(
                category: .invocation,
                contract: "heist invocation path resolves to a definition",
                observed: observed,
                expected: context.requestedName
            )
        )
    }

    internal func invocationBindingFailureResult(
        context: InvocationExecutionContext,
        error: Error
    ) -> HeistExecutionStepResult {
        let observed = "could not bind heist run argument: \(error)"
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(HeistInvocationEvidence.invocation(
                context.invoke,
                name: context.requestedName
            )),
            failure: HeistFailureDetail(
                category: .validation,
                contract: "heist invocation argument binds to the target parameter",
                observed: observed
            )
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
            message: observed
        )
        let expectationResult = ExpectationResult(
            met: false,
            predicate: nil,
            actual: observed
        )
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(HeistInvocationEvidence.invocation(
                context.invoke,
                name: context.requestedName,
                argument: context.argumentSummary,
                expectation: .init(
                    actionResult: expectationActionResult,
                    expectation: expectationResult
                )
            )),
            failure: HeistFailureDetail(
                category: .expectation,
                contract: "heist invocation expectation predicate resolves before evaluation",
                observed: observed,
                expected: expectation.predicate.description
            )
        )
    }

    internal func completedInvocationResult(
        context: InvocationExecutionContext,
        childExecution: HeistReceiptChildren,
        expectationContext: InvocationExpectationContext?,
        expectationOutcome: InvocationExpectationOutcome
    ) -> HeistExecutionStepResult {
        let expectationEvidence = expectationOutcome.receipt.map {
            invocationExpectationEvidence(receipt: $0, context: expectationContext)
        }
        let invocationExpectation = expectationEvidence.map {
            HeistInvocationEvidence.InvocationExpectationEvidence(
                actionResult: $0.actionResult,
                expectation: $0.expectation,
                waitEvidence: $0
            )
        }
        let evidence = HeistInvocationEvidence.invocation(
            context.invoke,
            name: context.requestedName,
            argument: context.argumentSummary,
            childFailedPath: childExecution.abortedAtChildPath,
            expectation: invocationExpectation
        )
        let failure: HeistFailureDetail? = switch expectationOutcome {
        case .notEvaluated, .matched:
            nil
        case .failed(receipt: _, detail: let detail):
            detail
        }
        return heistInvocationReceipt(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: context.intent,
            evidence: .invocation(evidence),
            failure: failure,
            children: childExecution,
            childFailure: { childPath in
                self.childFailureDetail(category: .invocation, childPath: childPath)
            }
        )
    }

    private func invocationExpectationEvidence(
        receipt: HeistWaitReceipt,
        context: InvocationExpectationContext?
    ) -> HeistWaitEvidence {
        let finalSummary = receipt.observationSummary ?? receipt.expectation.actual
        if let expectation = MetExpectationResult(receipt.expectation),
           let check = HeistWaitEvidence.MatchedCheck(
               actionResult: receipt.actionResult,
               expectation: expectation
           ) {
            return .matched(
                check,
                baselineSummary: context?.baseline.observationSummary,
                finalSummary: finalSummary
            )
        }
        guard let check = HeistWaitEvidence.UnmatchedCheck(
            actionResult: receipt.actionResult,
            expectation: receipt.expectation
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
        abortedAtPath: String?
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
