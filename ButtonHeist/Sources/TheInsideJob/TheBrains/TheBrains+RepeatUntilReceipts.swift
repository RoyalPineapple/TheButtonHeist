#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
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

        switch terminal {
        case .predicateMet(let check, let iterationCount, _):
            let evidence = HeistRepeatUntilEvidence.matched(
                iterationCount: iterationCount,
                expectation: check.expectation,
                lastObservedSummary: check.observation.summary
            )
            guard let evidence = HeistPassedRepeatUntilEvidence(evidence),
                  case .passed(let children) = HeistExecutedChildren(terminal.children) else {
                preconditionFailure("matched repeat_until terminal must carry passing evidence and children")
            }
            return repeatUntilResult(context: context, step: step, completion: .passed(
                evidence: evidence,
                children: children
            ))
        case .timedOut(let observation, let expectation, let iterationCount, _):
            let reason = RepeatUntil.Terminal.timeoutReason(step: step, expectation: expectation)
            let evidence = HeistRepeatUntilEvidence.failed(
                iterationCount: iterationCount,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: reason
            )
            guard let evidence = HeistFailedRepeatUntilEvidence(evidence),
                  case .passed(let children) = HeistExecutedChildren(terminal.children) else {
                preconditionFailure("timed-out repeat_until terminal must carry failed evidence and passing children")
            }
            return repeatUntilResult(context: context, step: step, completion: .failed(
                evidence: .observed(evidence),
                failure: repeatUntilFailure(step: step, observed: reason),
                children: children
            ))
        case .bodyFailed(let observation, let expectation, let index, let childPath, _):
            let reason = "iteration \(index) failed at \(childPath)"
            let evidence = HeistRepeatUntilEvidence.failed(
                iterationCount: index + 1,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: reason
            )
            guard let evidence = HeistFailedRepeatUntilEvidence(evidence),
                  case .aborted(let children) = HeistExecutedChildren(terminal.children) else {
                preconditionFailure("body-failed repeat_until terminal must carry failed evidence and children")
            }
            return repeatUntilResult(context: context, step: step, completion: .childAborted(
                evidence: evidence,
                failure: repeatUntilFailure(step: step, observed: reason),
                children: children
            ))
        case .timeoutHandledByElse(let observation, let expectation, let iterationCount, _, _):
            let evidence = HeistRepeatUntilEvidence.handledElse(
                iterationCount: iterationCount,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: RepeatUntil.Terminal.timeoutReason(step: step, expectation: expectation)
            )
            guard let evidence = HeistPassedRepeatUntilEvidence(evidence),
                  case .passed(let children) = HeistExecutedChildren(terminal.children) else {
                preconditionFailure("handled repeat_until terminal must carry passing evidence and children")
            }
            return repeatUntilResult(context: context, step: step, completion: .passed(
                evidence: evidence,
                children: children
            ))
        case .timeoutElseFailed(let observation, let expectation, let iterationCount, _, _, let childPath):
            return repeatUntilElseFailureResult(
                context: context,
                step: step,
                terminal: terminal,
                observation: observation,
                expectation: expectation,
                iterationCount: iterationCount,
                childPath: childPath
            )
        }
    }

    private func repeatUntilElseFailureResult(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        terminal: RepeatUntil.Terminal,
        observation: RepeatUntil.Observation?,
        expectation: ExpectationResult.Unmet,
        iterationCount: Int,
        childPath: HeistExecutionPath
    ) -> HeistExecutionStepResult {
        let reason = [
            RepeatUntil.Terminal.timeoutReason(step: step, expectation: expectation),
            "else body failed at \(childPath)",
        ].joined(separator: "; ")
        let evidence = HeistRepeatUntilEvidence.failed(
            iterationCount: iterationCount,
            expectation: expectation,
            lastObservedSummary: observation?.summary,
            failureReason: reason
        )
        guard let evidence = HeistFailedRepeatUntilEvidence(evidence),
              case .aborted(let children) = HeistExecutedChildren(terminal.children) else {
            preconditionFailure("else-failed repeat_until terminal must carry failed evidence and children")
        }
        return repeatUntilResult(context: context, step: step, completion: .childAborted(
            evidence: evidence,
            failure: childFailureDetail(category: .loop, childPath: childPath),
            children: children
        ))
    }

    private func repeatUntilResult(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        completion: HeistRepeatUntilCompletion
    ) -> HeistExecutionStepResult {
        .repeatUntil(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            predicate: step.predicateExpression,
            timeout: step.timeout,
            completion: completion
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
        let evidence: HeistRepeatUntilEvidence
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
        switch outcome {
        case .predicateMet, .continued:
            guard let evidence = HeistPassedRepeatUntilIterationEvidence(evidence),
                  case .passed(let children) = HeistExecutedChildren(children) else {
                preconditionFailure("passing repeat_until iteration must carry compatible evidence and children")
            }
            return .repeatUntilIteration(
                path: frame.path,
                durationMs: elapsedMilliseconds(since: frame.start),
                predicate: step.predicateExpression,
                timeout: step.timeout,
                completion: .passed(evidence: evidence, children: children)
            )
        case .failed(expectation: _, childPath: let childPath):
            guard let evidence = HeistFailedRepeatUntilEvidence(evidence),
                  case .aborted(let children) = HeistExecutedChildren(children) else {
                preconditionFailure("failed repeat_until iteration must carry failed evidence and children")
            }
            return .repeatUntilIteration(
                path: frame.path,
                durationMs: elapsedMilliseconds(since: frame.start),
                predicate: step.predicateExpression,
                timeout: step.timeout,
                completion: .childAborted(
                    evidence: evidence,
                    failure: childFailureDetail(category: .loop, childPath: childPath),
                    children: children
                )
            )
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
