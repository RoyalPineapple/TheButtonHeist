#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    private struct RepeatUntilReceiptContext {
        let path: HeistExecutionPath
        let durationMs: Int
        let declaration: HeistRepeatUntilDeclaration
        let step: ResolvedRepeatUntilStep
        let children: [HeistExecutionStepResult]

        init(
            path: HeistExecutionPath,
            durationMs: Int,
            step: ResolvedRepeatUntilStep,
            children: [HeistExecutionStepResult]
        ) {
            self.path = path
            self.durationMs = durationMs
            declaration = HeistRepeatUntilDeclaration(
                predicate: step.predicateExpression,
                timeout: step.timeout
            )
            self.step = step
            self.children = children
        }
    }

    internal func repeatUntilTerminalResult(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        state: RepeatUntil.LoopState
    ) async -> HeistExecutionStepResult {
        guard case .terminal(let terminal) = state else {
            return repeatUntilInternalStateFailure(
                context: context,
                step: step,
                observed: "repeat_until execution ended without terminal state"
            )
        }
        if case .timedOut = terminal,
           let elseBody = step.elseBody {
            let elseChildren = await executeHeistSteps(
                elseBody,
                runtime: context.runtime,
                environment: context.environment,
                scope: context.scope,
                path: context.path.repeatUntilElseBody()
            )
            return repeatUntilTerminalReceipt(
                context: context,
                step: step,
                terminalState: RepeatUntil.LoopState.reduce(state, event: .elseCompleted(elseChildren))
            )
        }
        return repeatUntilTerminalReceipt(context: context, step: step, terminalState: state)
    }

    private func repeatUntilTerminalReceipt(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        terminalState: RepeatUntil.LoopState
    ) -> HeistExecutionStepResult {
        guard case .terminal(let terminal) = terminalState else {
            return repeatUntilInternalStateFailure(
                context: context,
                step: step,
                observed: "repeat_until result requires terminal state"
            )
        }
        let receiptContext = RepeatUntilReceiptContext(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            step: step,
            children: terminal.children
        )

        switch terminal {
        case .predicateMet(let check, let iterationCount, _):
            return repeatUntilPredicateMetResult(
                context: receiptContext,
                check: check,
                iterationCount: iterationCount
            )
        case .timedOut(let observation, let expectation, let iterationCount, _):
            return repeatUntilTimedOutResult(
                context: receiptContext,
                observation: observation,
                expectation: expectation,
                iterationCount: iterationCount
            )
        case .bodyFailed(let observation, let expectation, let index, let childPath, _):
            return repeatUntilBodyFailureResult(
                context: receiptContext,
                observation: observation,
                expectation: expectation,
                iterationIndex: index,
                childPath: childPath
            )
        case .timeoutHandledByElse(let observation, let expectation, let iterationCount, _, _):
            return repeatUntilHandledTimeoutResult(
                context: receiptContext,
                observation: observation,
                expectation: expectation,
                iterationCount: iterationCount
            )
        case .timeoutElseFailed(let observation, let expectation, let iterationCount, _, _, let childPath):
            return repeatUntilElseFailureResult(
                context: receiptContext,
                observation: observation,
                expectation: expectation,
                iterationCount: iterationCount,
                childPath: childPath
            )
        }
    }

    private func repeatUntilPredicateMetResult(
        context: RepeatUntilReceiptContext,
        check: RepeatUntil.MetCheck,
        iterationCount: Int
    ) -> HeistExecutionStepResult {
        let completion: HeistRepeatUntilCompletion?
        if case .passed(let children) = HeistExecutedChildren(context.children) {
            completion = HeistRepeatUntilEvidence.matched(
                iterationCount: iterationCount,
                expectation: check.expectation,
                lastObservedSummary: check.observation.summary
            ).flatMap(HeistPassedRepeatUntilEvidence.init).map { evidence in
                .passed(evidence: evidence, children: children)
            }
        } else {
            completion = nil
        }
        return repeatUntilResult(
            context: context,
            completion: completion
        )
    }

    private func repeatUntilTimedOutResult(
        context: RepeatUntilReceiptContext,
        observation: RepeatUntil.Observation?,
        expectation: ExpectationResult.Unmet,
        iterationCount: Int
    ) -> HeistExecutionStepResult {
        let reason = RepeatUntil.Terminal.timeoutReason(step: context.step, expectation: expectation)
        let completion: HeistRepeatUntilCompletion?
        if case .passed(let children) = HeistExecutedChildren(context.children) {
            completion = HeistRepeatUntilEvidence.failed(
                iterationCount: iterationCount,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: reason
            ).flatMap(HeistFailedRepeatUntilEvidence.init).map { evidence in
                .failed(
                    evidence: .observed(evidence),
                    failure: repeatUntilFailure(step: context.step, observed: reason),
                    children: children
                )
            }
        } else {
            completion = nil
        }
        return repeatUntilResult(
            context: context,
            completion: completion
        )
    }

    private func repeatUntilBodyFailureResult(
        context: RepeatUntilReceiptContext,
        observation: RepeatUntil.Observation?,
        expectation: ExpectationResult.Unmet,
        iterationIndex: Int,
        childPath: HeistExecutionPath
    ) -> HeistExecutionStepResult {
        let reason = "iteration \(iterationIndex) failed at \(childPath)"
        let completion: HeistRepeatUntilCompletion?
        if case .aborted(let children) = HeistExecutedChildren(context.children) {
            completion = HeistRepeatUntilEvidence.failed(
                iterationCount: iterationIndex + 1,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: reason
            ).flatMap(HeistFailedRepeatUntilEvidence.init).map { evidence in
                .childAborted(
                    evidence: evidence,
                    failure: repeatUntilFailure(step: context.step, observed: reason),
                    children: children
                )
            }
        } else {
            completion = nil
        }
        return repeatUntilResult(
            context: context,
            completion: completion
        )
    }

    private func repeatUntilHandledTimeoutResult(
        context: RepeatUntilReceiptContext,
        observation: RepeatUntil.Observation?,
        expectation: ExpectationResult.Unmet,
        iterationCount: Int
    ) -> HeistExecutionStepResult {
        let completion: HeistRepeatUntilCompletion?
        if case .passed(let children) = HeistExecutedChildren(context.children) {
            completion = HeistRepeatUntilEvidence.handledElse(
                iterationCount: iterationCount,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: RepeatUntil.Terminal.timeoutReason(step: context.step, expectation: expectation)
            ).flatMap(HeistPassedRepeatUntilEvidence.init).map { evidence in
                .passed(evidence: evidence, children: children)
            }
        } else {
            completion = nil
        }
        return repeatUntilResult(
            context: context,
            completion: completion
        )
    }

    private func repeatUntilElseFailureResult(
        context: RepeatUntilReceiptContext,
        observation: RepeatUntil.Observation?,
        expectation: ExpectationResult.Unmet,
        iterationCount: Int,
        childPath: HeistExecutionPath
    ) -> HeistExecutionStepResult {
        let reason = [
            RepeatUntil.Terminal.timeoutReason(step: context.step, expectation: expectation),
            "else body failed at \(childPath)",
        ].joined(separator: "; ")
        let completion: HeistRepeatUntilCompletion?
        if case .aborted(let children) = HeistExecutedChildren(context.children) {
            completion = HeistRepeatUntilEvidence.failed(
                iterationCount: iterationCount,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: reason
            ).flatMap(HeistFailedRepeatUntilEvidence.init).map { evidence in
                .childAborted(
                    evidence: evidence,
                    failure: childFailureDetail(category: .loop, childPath: childPath),
                    children: children
                )
            }
        } else {
            completion = nil
        }
        return repeatUntilResult(
            context: context,
            completion: completion
        )
    }

    private func repeatUntilResult(
        context: RepeatUntilReceiptContext,
        completion: HeistRepeatUntilCompletion?
    ) -> HeistExecutionStepResult {
        let admittedCompletion = requireAdmitted(
            completion,
            "repeat_until receipt completion must match the terminal state and admitted evidence"
        )
        return requireAdmitted(
            HeistExecutionStepResult.repeatUntil(
                path: context.path,
                durationMs: context.durationMs,
                declaration: context.declaration,
                completion: admittedCompletion
            ),
            "repeat_until receipt must match its declaration"
        )
    }

    private func repeatUntilFailure(
        step: ResolvedRepeatUntilStep,
        observed: String
    ) -> HeistFailureDetail {
        HeistFailureDetail(
            category: .loop,
            contract: "repeat_until predicate is met before timeout",
            observed: observed,
            expected: step.predicate.description
        )
    }

    internal func repeatUntilIterationResult(
        frame: RepeatUntil.IterationFrame,
        step: ResolvedRepeatUntilStep,
        outcome: RepeatUntil.IterationOutcome,
        observation: RepeatUntil.Observation?,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let evidence: HeistRepeatUntilEvidence?
        switch outcome {
        case .failed(expectation: let expectation, childPath: let childPath):
            evidence = HeistRepeatUntilEvidence.failed(
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: "child failed at \(childPath)"
            )
        case .predicateMet(let expectation):
            evidence = HeistRepeatUntilEvidence.matched(
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary
            )
        case .continued(let expectation):
            evidence = HeistRepeatUntilEvidence.continued(
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary
            )
        }
        let durationMs = elapsedMilliseconds(since: frame.start)
        let declaration = HeistRepeatUntilDeclaration(
            predicate: step.predicateExpression,
            timeout: step.timeout
        )
        switch outcome {
        case .predicateMet, .continued:
            let admittedEvidence = requireAdmitted(
                evidence.flatMap(HeistPassedRepeatUntilIterationEvidence.init),
                "repeat_until iteration passing evidence must match the iteration declaration"
            )
            let admittedChildren = requirePassingChildren(
                children,
                "repeat_until passing iteration must not contain a failed child"
            )
            return requireAdmitted(
                HeistExecutionStepResult.repeatUntilIteration(
                    path: frame.path,
                    durationMs: durationMs,
                    declaration: declaration,
                    completion: .passed(evidence: admittedEvidence, children: admittedChildren)
                ),
                "repeat_until passing iteration receipt must match its declaration"
            )
        case .failed(expectation: _, childPath: let childPath):
            let admittedEvidence = requireAdmitted(
                evidence.flatMap(HeistFailedRepeatUntilEvidence.init),
                "repeat_until iteration child-aborted evidence must match the iteration declaration"
            )
            let admittedChildren = requireAbortedChildren(
                children,
                "repeat_until failed iteration must carry the aborted child path"
            )
            return requireAdmitted(
                HeistExecutionStepResult.repeatUntilIteration(
                    path: frame.path,
                    durationMs: durationMs,
                    declaration: declaration,
                    completion: .childAborted(
                        evidence: admittedEvidence,
                        failure: childFailureDetail(category: .loop, childPath: childPath),
                        children: admittedChildren
                    )
                ),
                "repeat_until failed iteration receipt must match its declaration"
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
