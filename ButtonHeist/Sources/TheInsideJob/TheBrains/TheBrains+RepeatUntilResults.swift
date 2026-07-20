#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    private struct RepeatUntilResultContext {
        let path: HeistExecutionPath
        let durationMs: ElapsedMilliseconds
        let declaration: HeistRepeatUntilDeclaration
        let step: ResolvedRepeatUntilStep

        init(
            path: HeistExecutionPath,
            durationMs: ElapsedMilliseconds,
            step: ResolvedRepeatUntilStep
        ) {
            self.path = path
            self.durationMs = durationMs
            declaration = HeistRepeatUntilDeclaration(
                predicate: step.predicateExpression,
                timeout: step.timeout
            )
            self.step = step
        }
    }

    internal func repeatUntilTerminalResult(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        state: RepeatUntil.LoopState
    ) async -> HeistExecutionStepResult {
        guard case .terminal = state else {
            return repeatUntilInternalStateFailure(
                context: context,
                step: step,
                observed: "repeat_until execution ended without terminal state"
            )
        }
        return repeatUntilTerminalResult(context: context, step: step, terminalState: state)
    }

    private func repeatUntilTerminalResult(
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
        let resultContext = RepeatUntilResultContext(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            step: step
        )

        switch terminal {
        case .predicateMet(let check, let iterationCount, let children):
            return repeatUntilPredicateMetResult(
                context: resultContext,
                check: check,
                iterationCount: iterationCount,
                children: children
            )
        case .timedOut(let observation, let expectation, let iterationCount, let children):
            return repeatUntilTimedOutResult(
                context: resultContext,
                observation: observation,
                expectation: expectation,
                iterationCount: iterationCount,
                children: children
            )
        case .bodyFailed(let observation, let expectation, let index, let children):
            return repeatUntilBodyFailureResult(
                context: resultContext,
                observation: observation,
                expectation: expectation,
                iterationIndex: index,
                children: children
            )
        }
    }

    private func repeatUntilPredicateMetResult(
        context: RepeatUntilResultContext,
        check: RepeatUntil.MetCheck,
        iterationCount: Int,
        children: HeistPassingChildren
    ) -> HeistExecutionStepResult {
        let evidence = HeistRepeatUntilEvidence.executedMatched(
            iterationCount: iterationCount,
            expectation: check.expectation,
            lastObservedSummary: check.observation.summary
        )
        return repeatUntilResult(
            context: context,
            completion: .passed(evidence: .init(admitted: evidence), children: children)
        )
    }

    private func repeatUntilTimedOutResult(
        context: RepeatUntilResultContext,
        observation: RepeatUntil.Observation?,
        expectation: ExpectationResult.Unmet,
        iterationCount: Int,
        children: HeistPassingChildren
    ) -> HeistExecutionStepResult {
        let reason = RepeatUntil.Terminal.timeoutReason(step: context.step, expectation: expectation)
        let evidence = HeistRepeatUntilEvidence.executedFailed(
            iterationCount: iterationCount,
            expectation: expectation,
            lastObservedSummary: observation?.summary,
            failureReason: reason
        )
        return repeatUntilResult(
            context: context,
            completion: .failed(
                evidence: .observed(.init(admitted: evidence)),
                failure: repeatUntilFailure(step: context.step, observed: reason),
                children: children
            )
        )
    }

    private func repeatUntilBodyFailureResult(
        context: RepeatUntilResultContext,
        observation: RepeatUntil.Observation?,
        expectation: ExpectationResult.Unmet,
        iterationIndex: Int,
        children: HeistAbortedChildren
    ) -> HeistExecutionStepResult {
        let childPath = children.abortedAtPath
        let reason = "iteration \(iterationIndex) failed at \(childPath)"
        let evidence = HeistRepeatUntilEvidence.executedFailed(
            iterationCount: iterationIndex + 1,
            expectation: expectation,
            lastObservedSummary: observation?.summary,
            failureReason: reason
        )
        return repeatUntilResult(
            context: context,
            completion: .childAborted(
                evidence: .init(admitted: evidence),
                failure: repeatUntilFailure(step: context.step, observed: reason),
                children: children
            )
        )
    }

    private func repeatUntilResult(
        context: RepeatUntilResultContext,
        completion: HeistRepeatUntilCompletion
    ) -> HeistExecutionStepResult {
        .repeatUntil(
            path: context.path,
            durationMs: context.durationMs,
            declaration: context.declaration,
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

    internal func repeatUntilPassingIterationResult(
        frame: RepeatUntil.IterationFrame,
        step: ResolvedRepeatUntilStep,
        postBody: RepeatUntil.PostBodyCheck,
        children: HeistPassingChildren
    ) -> HeistPassingChildren {
        let evidence: HeistRepeatUntilEvidence
        switch postBody {
        case .met(let check):
            evidence = .executedMatched(
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: check.expectation,
                lastObservedSummary: check.observation.summary
            )
        case .unmet(let check):
            evidence = .executedContinued(
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: check.expectation,
                lastObservedSummary: check.observation.summary
            )
        case .deadlineElapsed(let expectation):
            evidence = .executedContinued(
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation
            )
        case .noProgress(let observation, let expectation, _):
            evidence = .executedContinued(
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary
            )
        }
        return children.wrappedInRepeatUntilIteration(
            path: frame.path,
            durationMs: elapsedMilliseconds(since: frame.start),
            declaration: HeistRepeatUntilDeclaration(
                predicate: step.predicateExpression,
                timeout: step.timeout
            ),
            evidence: .init(admitted: evidence)
        )
    }

    internal func repeatUntilFailedIterationResult(
        frame: RepeatUntil.IterationFrame,
        step: ResolvedRepeatUntilStep,
        expectation: ExpectationResult.Unmet,
        observation: RepeatUntil.Observation?,
        children: HeistAbortedChildren
    ) -> HeistAbortedChildren {
        let childPath = children.abortedAtPath
        let evidence = HeistRepeatUntilEvidence.executedFailed(
            iterationCount: frame.count,
            iterationOrdinal: frame.index,
            expectation: expectation,
            lastObservedSummary: observation?.summary,
            failureReason: "child failed at \(childPath)"
        )
        return children.wrappedInRepeatUntilIteration(
            path: frame.path,
            durationMs: elapsedMilliseconds(since: frame.start),
            declaration: HeistRepeatUntilDeclaration(
                predicate: step.predicateExpression,
                timeout: step.timeout
            ),
            evidence: .init(admitted: evidence),
            failure: childFailureDetail(category: .loop, childPath: childPath)
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
