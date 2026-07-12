#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains.RepeatUntil {
    internal enum TerminalResult {
        case predicateMet(
            evidence: HeistRepeatUntilEvidence,
            children: [HeistExecutionStepResult]
        )
        case timedOut(
            evidence: HeistRepeatUntilEvidence,
            failure: HeistFailureDetail,
            children: [HeistExecutionStepResult]
        )
        case initialUnavailable(
            evidence: HeistRepeatUntilEvidence,
            failure: HeistFailureDetail,
            children: [HeistExecutionStepResult]
        )
        case bodyFailed(
            evidence: HeistRepeatUntilEvidence,
            failure: HeistFailureDetail,
            abortedAtChildPath: String,
            children: [HeistExecutionStepResult]
        )
        case timeoutHandledByElse(
            evidence: HeistRepeatUntilEvidence,
            children: [HeistExecutionStepResult]
        )
        case timeoutElseFailed(
            evidence: HeistRepeatUntilEvidence,
            failure: HeistFailureDetail,
            abortedAtChildPath: String,
            children: [HeistExecutionStepResult]
        )

        internal init(
            terminal: Terminal,
            step: ResolvedRepeatUntilStep,
            childFailureDetail: (String) -> HeistFailureDetail
        ) {
            switch terminal {
            case .predicateMet(let check, let iterationCount, _):
                self = .predicateMet(
                    evidence: HeistRepeatUntilEvidence.predicateMet(
                        predicate: step.predicate,
                        timeout: step.timeout,
                        iterationCount: iterationCount,
                        expectation: check.expectation,
                        lastObservedSummary: check.observation.summary
                    ),
                    children: terminal.children
                )
            case .timedOut(let observation, let expectation, let iterationCount, _):
                let failureReason = Terminal.timeoutReason(step: step, expectation: expectation)
                self = .timedOut(
                    evidence: HeistRepeatUntilEvidence.timedOut(
                        predicate: step.predicate,
                        timeout: step.timeout,
                        iterationCount: iterationCount,
                        expectation: expectation,
                        lastObservedSummary: observation?.summary,
                        failureReason: failureReason
                    ),
                    failure: Self.failureDetail(
                        step: step,
                        observed: failureReason
                    ),
                    children: terminal.children
                )
            case .initialObservationUnavailable(let receipt):
                let failureReason = "could not observe settled semantic hierarchy before evaluating repeat_until"
                self = .initialUnavailable(
                    evidence: HeistRepeatUntilEvidence.initialObservationUnavailable(
                        predicate: step.predicate,
                        timeout: step.timeout,
                        expectation: Terminal.initialObservationUnavailableExpectation(
                            step: step,
                            receipt: receipt
                        ),
                        lastObservedSummary: receipt.observationSummary,
                        failureReason: failureReason
                    ),
                    failure: Self.failureDetail(
                        step: step,
                        observed: failureReason
                    ),
                    children: terminal.children
                )
            case .bodyFailed(let observation, let expectation, let iterationIndex, let childPath, _):
                let failureReason = "iteration \(iterationIndex) failed at \(childPath)"
                self = .bodyFailed(
                    evidence: HeistRepeatUntilEvidence.bodyFailed(
                        predicate: step.predicate,
                        timeout: step.timeout,
                        iterationCount: iterationIndex + 1,
                        expectation: expectation,
                        lastObservedSummary: observation.summary,
                        failureReason: failureReason
                    ),
                    failure: Self.failureDetail(
                        step: step,
                        observed: failureReason
                    ),
                    abortedAtChildPath: childPath,
                    children: terminal.children
                )
            case .timeoutHandledByElse(let observation, let expectation, let iterationCount, _, _):
                self = .timeoutHandledByElse(
                    evidence: HeistRepeatUntilEvidence.timeoutHandledByElse(
                        predicate: step.predicate,
                        timeout: step.timeout,
                        iterationCount: iterationCount,
                        expectation: expectation,
                        lastObservedSummary: observation?.summary,
                        failureReason: Terminal.timeoutReason(step: step, expectation: expectation)
                    ),
                    children: terminal.children
                )
            case .timeoutElseFailed(let observation, let expectation, let iterationCount, _, _, let childPath):
                let failureReason = [
                    Terminal.timeoutReason(step: step, expectation: expectation),
                    "else body failed at \(childPath)",
                ].joined(separator: "; ")
                self = .timeoutElseFailed(
                    evidence: HeistRepeatUntilEvidence.timeoutElseFailed(
                        predicate: step.predicate,
                        timeout: step.timeout,
                        iterationCount: iterationCount,
                        expectation: expectation,
                        lastObservedSummary: observation?.summary,
                        failureReason: failureReason
                    ),
                    failure: childFailureDetail(childPath),
                    abortedAtChildPath: childPath,
                    children: terminal.children
                )
            }
        }

        internal var evidence: HeistRepeatUntilEvidence {
            switch self {
            case .predicateMet(let evidence, _),
                 .timedOut(let evidence, _, _),
                 .initialUnavailable(let evidence, _, _),
                 .bodyFailed(let evidence, _, _, _),
                 .timeoutHandledByElse(let evidence, _),
                 .timeoutElseFailed(let evidence, _, _, _):
                return evidence
            }
        }

        internal var children: [HeistExecutionStepResult] {
            switch self {
            case .predicateMet(_, let children),
                 .timedOut(_, _, let children),
                 .initialUnavailable(_, _, let children),
                 .bodyFailed(_, _, _, let children),
                 .timeoutHandledByElse(_, let children),
                 .timeoutElseFailed(_, _, _, let children):
                return children
            }
        }

        internal func stepResult(
            path: String,
            durationMs: Int,
            intent: HeistStepIntent
        ) -> HeistExecutionStepResult {
            switch self {
            case .predicateMet,
                 .timeoutHandledByElse:
                return .passed(
                    path: path,
                    receiptKind: .repeatUntil,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: evidence,
                    children: children
                )
            case .timedOut(_, let failure, _),
                 .initialUnavailable(_, let failure, _):
                return .failed(
                    path: path,
                    receiptKind: .repeatUntil,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: evidence,
                    failure: failure,
                    children: children
                )
            case .bodyFailed(_, let failure, let abortedAtChildPath, _),
                 .timeoutElseFailed(_, let failure, let abortedAtChildPath, _):
                return .childAborted(
                    path: path,
                    receiptKind: .repeatUntil,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: evidence,
                    failure: failure,
                    abortedAtChildPath: abortedAtChildPath,
                    children: children
                )
            }
        }

        private static func failureDetail(
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
    }
}

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
                path: "\(context.path).repeat_until.else_body"
            )
            return repeatUntilResult(
                context: context,
                step: step,
                terminalState: RepeatUntil.LoopState.reduce(state, event: .elseCompleted(elseChildren))
            )
        }
        return repeatUntilResult(context: context, step: step, terminalState: state)
    }

    private func repeatUntilResult(
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
        let terminalResult = RepeatUntil.TerminalResult(
            terminal: terminal,
            step: step,
            childFailureDetail: {
                childFailureDetail(category: .loop, childPath: $0)
            }
        )
        return terminalResult.stepResult(
            path: context.path,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: .repeatUntil(
                predicate: step.predicateExpression,
                timeout: step.timeout
            )
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
            evidence = HeistRepeatUntilEvidence.failedIteration(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: "child failed at \(childPath)"
            )
        case .predicateMet(let expectation):
            evidence = HeistRepeatUntilEvidence.predicateMet(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary
            )
        case .continued(let expectation):
            evidence = HeistRepeatUntilEvidence.continued(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary
            )
        }
        let stepEvidence = HeistStepEvidence.repeatUntil(evidence)
        let childExecution = HeistReceiptChildren(children)
        let failure: HeistFailureDetail? = switch outcome {
        case .predicateMet, .continued:
            nil
        case .failed(expectation: _, childPath: let childPath):
            childFailureDetail(category: .loop, childPath: childPath)
        }
        return heistLoopReceipt(
            path: frame.path,
            kind: .repeatUntilIteration,
            durationMs: elapsedMilliseconds(since: frame.start),
            intent: .repeatUntil(
                predicate: step.predicateExpression,
                timeout: step.timeout
            ),
            evidence: stepEvidence,
            failure: failure,
            children: childExecution,
            childFailure: { childPath in
                childFailureDetail(category: .loop, childPath: childPath)
            }
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
