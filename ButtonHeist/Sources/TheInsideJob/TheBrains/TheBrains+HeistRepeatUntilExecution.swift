#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    private struct RepeatUntilExecutionContext {
        let path: String
        let start: CFAbsoluteTime
        let runtime: HeistExecutionRuntime
        let environment: HeistExecutionEnvironment
        let scope: HeistExecutionScope
    }

    private struct RepeatUntilObservation {
        let sequence: SettledObservationSequence
        let trace: AccessibilityTrace?
        let summary: String?

        init?(_ receipt: HeistWaitReceipt) {
            guard let sequence = receipt.observedSequence else { return nil }
            self.sequence = sequence
            trace = receipt.accessibilityTrace
            summary = receipt.observationSummary
        }
    }

    private struct RepeatUntilMetCheck {
        let observation: RepeatUntilObservation
        let expectation: MetExpectationResult
        let receipt: HeistWaitReceipt
    }

    private struct RepeatUntilUnmetCheck {
        let observation: RepeatUntilObservation
        let expectation: UnmetExpectationResult
        let receipt: HeistWaitReceipt
    }

    private enum RepeatUntilObservedCheck {
        case met(RepeatUntilMetCheck)
        case unmet(RepeatUntilUnmetCheck)

        init?(
            receipt: HeistWaitReceipt,
            expectation: ExpectationResult? = nil
        ) {
            guard let observation = RepeatUntilObservation(receipt) else { return nil }
            self.init(
                observation: observation,
                check: PredicateExpectationCheck(expectation ?? receipt.expectation),
                receipt: receipt
            )
        }

        init(
            observation: RepeatUntilObservation,
            check: PredicateExpectationCheck,
            receipt: HeistWaitReceipt
        ) {
            switch check {
            case .met(let expectation):
                self = .met(RepeatUntilMetCheck(
                    observation: observation,
                    expectation: expectation,
                    receipt: receipt
                ))
            case .unmet(let expectation):
                self = .unmet(RepeatUntilUnmetCheck(
                    observation: observation,
                    expectation: expectation,
                    receipt: receipt
                ))
            }
        }
    }

    private enum RepeatUntilInitialCheck {
        case unavailable(HeistWaitReceipt)
        case met(RepeatUntilMetCheck)
        case unmet(RepeatUntilUnmetCheck)

        static func make(receipt: HeistWaitReceipt) -> RepeatUntilInitialCheck {
            guard let check = RepeatUntilObservedCheck(receipt: receipt) else {
                return .unavailable(receipt)
            }
            switch check {
            case .met(let check):
                return .met(check)
            case .unmet(let check):
                return .unmet(check)
            }
        }
    }

    private enum RepeatUntilIterationOutcome {
        case predicateMet(MetExpectationResult)
        case continued(UnmetExpectationResult)
        case failed(expectation: UnmetExpectationResult, childPath: String)

        var abortedAtChildPath: String? {
            switch self {
            case .predicateMet, .continued:
                return nil
            case .failed(expectation: _, childPath: let childPath):
                return childPath
            }
        }
    }

    private enum RepeatUntilPostBodyCheck {
        case deadlineElapsed(UnmetExpectationResult)
        case changedMet(RepeatUntilMetCheck)
        case changedUnmet(RepeatUntilUnmetCheck)
        case noProgress(observation: RepeatUntilObservation?, expectation: UnmetExpectationResult, receipt: HeistWaitReceipt)

        var iterationOutcome: RepeatUntilIterationOutcome {
            switch self {
            case .deadlineElapsed(let expectation),
                 .noProgress(_, let expectation, _):
                return .continued(expectation)
            case .changedMet(let check):
                return .predicateMet(check.expectation)
            case .changedUnmet(let check):
                return .continued(check.expectation)
            }
        }

        var observation: RepeatUntilObservation? {
            switch self {
            case .deadlineElapsed:
                return nil
            case .changedMet(let check):
                return check.observation
            case .changedUnmet(let check):
                return check.observation
            case .noProgress(let observation, _, _):
                return observation
            }
        }
    }

    private struct RepeatUntilRunningState {
        let currentCheck: RepeatUntilUnmetCheck
        let iterationNodes: [HeistExecutionStepResult]

        func appendingIteration(_ node: HeistExecutionStepResult, nextCheck: RepeatUntilUnmetCheck) -> RepeatUntilRunningState {
            RepeatUntilRunningState(currentCheck: nextCheck, iterationNodes: iterationNodes + [node])
        }
    }

    private enum RepeatUntilLoopState {
        case awaitingInitial
        case running(RepeatUntilRunningState)
        case terminal(RepeatUntilTerminal)

        static func reduce(_ state: RepeatUntilLoopState, event: RepeatUntilLoopEvent) -> RepeatUntilLoopState {
            switch (state, event) {
            case (.awaitingInitial, .initial(let check)):
                switch check {
                case .unavailable(let receipt):
                    return .terminal(.initialObservationUnavailable(receipt))
                case .met(let check):
                    return .terminal(.predicateMet(
                        check: check,
                        iterationCount: 0,
                        iterationNodes: []
                    ))
                case .unmet(let check):
                    return .running(RepeatUntilRunningState(currentCheck: check, iterationNodes: []))
                }
            case (.running(let running), .deadlineElapsed(let expectation)):
                return .terminal(.timedOut(
                    observation: running.currentCheck.observation,
                    expectation: expectation,
                    iterationCount: running.iterationNodes.count,
                    iterationNodes: running.iterationNodes
                ))
            case (.running(let running), .iterationPassed(let event)):
                return reduceIterationPassed(running: running, event: event)
            case (.running(let running), .iterationFailed(let event)):
                return reduceIterationFailed(running: running, event: event)
            case (.terminal(let terminal), .elseCompleted(let children)):
                return reduceElseCompleted(state: state, terminal: terminal, children: children)
            case (.awaitingInitial, _),
                 (.running, .initial),
                 (.running, .elseCompleted),
                 (.terminal, .initial),
                 (.terminal, .deadlineElapsed),
                 (.terminal, .iterationPassed),
                 (.terminal, .iterationFailed):
                return state
            }
        }

        private static func reduceIterationPassed(
            running: RepeatUntilRunningState,
            event: RepeatUntilPassedIterationEvent
        ) -> RepeatUntilLoopState {
            switch event.postBody {
            case .changedMet(let check):
                return .terminal(.predicateMet(
                    check: check,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes + [event.iterationNode]
                ))
            case .changedUnmet(let check):
                return .running(running.appendingIteration(event.iterationNode, nextCheck: check))
            case .deadlineElapsed(let expectation):
                return .terminal(.timedOut(
                    observation: running.currentCheck.observation,
                    expectation: expectation,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes + [event.iterationNode]
                ))
            case .noProgress(let observation, let expectation, _):
                return .terminal(.timedOut(
                    observation: observation,
                    expectation: expectation,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes + [event.iterationNode]
                ))
            }
        }

        private static func reduceIterationFailed(
            running: RepeatUntilRunningState,
            event: RepeatUntilFailedIterationEvent
        ) -> RepeatUntilLoopState {
            if let postBody = event.postBody,
               case .changedMet(let check) = postBody {
                return .terminal(.predicateMet(
                    check: check,
                    iterationCount: event.frame.count,
                    iterationNodes: running.iterationNodes + [event.predicateMetIterationNode]
                ))
            }
            return .terminal(.bodyFailed(
                observation: running.currentCheck.observation,
                expectation: event.failureExpectation,
                iterationIndex: event.frame.index,
                childPath: event.failedStep.path,
                iterationNodes: running.iterationNodes + [event.failedIterationNode]
            ))
        }

        private static func reduceElseCompleted(
            state: RepeatUntilLoopState,
            terminal: RepeatUntilTerminal,
            children: [HeistExecutionStepResult]
        ) -> RepeatUntilLoopState {
            guard case .timedOut(let observation, let expectation, let iterationCount, let iterationNodes) = terminal else {
                return state
            }
            switch HeistReceiptChildren(children) {
            case .childAborted(let childAbort):
                return .terminal(.timeoutElseFailed(
                    observation: observation,
                    expectation: expectation,
                    iterationCount: iterationCount,
                    iterationNodes: iterationNodes,
                    elseChildren: childAbort.children,
                    childPath: childAbort.abortedAtChildPath
                ))
            case .completed(let completed):
                return .terminal(.timeoutHandledByElse(
                    observation: observation,
                    expectation: expectation,
                    iterationCount: iterationCount,
                    iterationNodes: iterationNodes,
                    elseChildren: completed.children
                ))
            }
        }
    }

    private enum RepeatUntilLoopEvent {
        case initial(RepeatUntilInitialCheck)
        case deadlineElapsed(UnmetExpectationResult)
        case iterationPassed(RepeatUntilPassedIterationEvent)
        case iterationFailed(RepeatUntilFailedIterationEvent)
        case elseCompleted([HeistExecutionStepResult])
    }

    private enum RepeatUntilTerminal {
        case predicateMet(check: RepeatUntilMetCheck, iterationCount: Int, iterationNodes: [HeistExecutionStepResult])
        case timedOut(
            observation: RepeatUntilObservation?,
            expectation: UnmetExpectationResult,
            iterationCount: Int,
            iterationNodes: [HeistExecutionStepResult]
        )
        case initialObservationUnavailable(HeistWaitReceipt)
        case bodyFailed(
            observation: RepeatUntilObservation,
            expectation: UnmetExpectationResult,
            iterationIndex: Int,
            childPath: String,
            iterationNodes: [HeistExecutionStepResult]
        )
        case timeoutHandledByElse(
            observation: RepeatUntilObservation?,
            expectation: UnmetExpectationResult,
            iterationCount: Int,
            iterationNodes: [HeistExecutionStepResult],
            elseChildren: [HeistExecutionStepResult]
        )
        case timeoutElseFailed(
            observation: RepeatUntilObservation?,
            expectation: UnmetExpectationResult,
            iterationCount: Int,
            iterationNodes: [HeistExecutionStepResult],
            elseChildren: [HeistExecutionStepResult],
            childPath: String
        )

        var iterationNodes: [HeistExecutionStepResult] {
            switch self {
            case .predicateMet(_, _, let iterationNodes),
                 .timedOut(_, _, _, let iterationNodes),
                 .bodyFailed(_, _, _, _, let iterationNodes),
                 .timeoutHandledByElse(_, _, _, let iterationNodes, _),
                 .timeoutElseFailed(_, _, _, let iterationNodes, _, _):
                return iterationNodes
            case .initialObservationUnavailable:
                return []
            }
        }

        var children: [HeistExecutionStepResult] {
            switch self {
            case .timeoutHandledByElse(_, _, _, let iterationNodes, let elseChildren),
                 .timeoutElseFailed(_, _, _, let iterationNodes, let elseChildren, _):
                return iterationNodes + elseChildren
            case .predicateMet,
                 .timedOut,
                 .initialObservationUnavailable,
                 .bodyFailed:
                return iterationNodes
            }
        }

        static func initialObservationUnavailableExpectation(
            step: ResolvedRepeatUntilStep,
            receipt: HeistWaitReceipt
        ) -> UnmetExpectationResult {
            UnmetExpectationResult(receipt.expectation) ?? UnmetExpectationResult(
                predicate: step.predicate,
                actual: "initial observation unavailable"
            )
        }

        static func timeoutReason(
            step: ResolvedRepeatUntilStep,
            expectation: UnmetExpectationResult
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

    private enum RepeatUntilTerminalResult {
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

        init(
            terminal: RepeatUntilTerminal,
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
                let failureReason = RepeatUntilTerminal.timeoutReason(step: step, expectation: expectation)
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
                        expectation: RepeatUntilTerminal.initialObservationUnavailableExpectation(
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
                        failureReason: RepeatUntilTerminal.timeoutReason(step: step, expectation: expectation)
                    ),
                    children: terminal.children
                )
            case .timeoutElseFailed(let observation, let expectation, let iterationCount, _, _, let childPath):
                let failureReason = [
                    RepeatUntilTerminal.timeoutReason(step: step, expectation: expectation),
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

        var evidence: HeistRepeatUntilEvidence {
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

        var children: [HeistExecutionStepResult] {
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

        func stepResult(
            path: String,
            durationMs: Int,
            intent: HeistStepIntent
        ) -> HeistExecutionStepResult {
            let stepEvidence = HeistStepEvidence.repeatUntil(evidence)
            switch self {
            case .predicateMet,
                 .timeoutHandledByElse:
                return .passed(
                    path: path,
                    kind: .repeatUntil,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: stepEvidence,
                    children: children
                )
            case .timedOut(_, let failure, _),
                 .initialUnavailable(_, let failure, _):
                return .failed(
                    path: path,
                    kind: .repeatUntil,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: stepEvidence,
                    failure: failure,
                    children: children
                )
            case .bodyFailed(_, let failure, let abortedAtChildPath, _),
                 .timeoutElseFailed(_, let failure, let abortedAtChildPath, _):
                return .childAborted(
                    path: path,
                    kind: .repeatUntil,
                    durationMs: durationMs,
                    intent: intent,
                    evidence: stepEvidence,
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

    private struct RepeatUntilIterationFrame {
        let path: String
        let start: CFAbsoluteTime
        let index: Int
        let count: Int
    }

    private struct RepeatUntilPassedIterationEvent {
        let frame: RepeatUntilIterationFrame
        let postBody: RepeatUntilPostBodyCheck
        let iterationNode: HeistExecutionStepResult
    }

    private struct RepeatUntilFailedIterationEvent {
        let frame: RepeatUntilIterationFrame
        let failedStep: HeistExecutionStepResult
        let postBody: RepeatUntilPostBodyCheck?
        let failureExpectation: UnmetExpectationResult
        let predicateMetIterationNode: HeistExecutionStepResult
        let failedIterationNode: HeistExecutionStepResult
    }

    func executeRepeatUntilStep(
        _ step: RepeatUntilStep,
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let context = RepeatUntilExecutionContext(
            path: path,
            start: start,
            runtime: runtime,
            environment: environment,
            scope: scope
        )
        let resolved: ResolvedRepeatUntilStep
        do {
            resolved = try step.resolve(in: environment)
        } catch {
            return repeatUntilResolutionFailure(step, path: path, start: start, error: error)
        }

        let initialReceipt = await runtime.wait(
            .immediate(ResolvedWaitStep(predicate: resolved.predicate, timeout: immediateTimeout))
        )
        var state = RepeatUntilLoopState.reduce(
            .awaitingInitial,
            event: .initial(RepeatUntilInitialCheck.make(receipt: initialReceipt))
        )
        let timeout = PredicateWait.clampedWaitTimeout(resolved.timeout)

        if case .running = state, timeout <= 0 {
            state = RepeatUntilLoopState.reduce(
                state,
                event: .deadlineElapsed(UnmetExpectationResult(
                    predicate: resolved.predicate,
                    actual: "repeat_until deadline elapsed"
                ))
            )
        }

        guard case .running = state else {
            return await repeatUntilTerminalResult(
                context: context,
                step: resolved,
                state: state
            )
        }

        return await repeatUntilLoopResult(
            context: context,
            step: resolved,
            state: state,
            timeout: timeout
        )
    }

    private func repeatUntilLoopResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        state initialState: RepeatUntilLoopState,
        timeout: Double
    ) async -> HeistExecutionStepResult {
        let deadline = context.start + timeout
        var state = initialState

        while case .running(let running) = state, CFAbsoluteTimeGetCurrent() < deadline {
            let iterationIndex = running.iterationNodes.count
            let iterationStart = CFAbsoluteTimeGetCurrent()
            let iterationPath = "\(context.path).repeat_until.iterations[\(iterationIndex)]"
            let iterationResults = await executeHeistSteps(
                step.body,
                runtime: context.runtime,
                environment: context.environment,
                scope: context.scope,
                path: "\(iterationPath).body"
            )
            let frame = RepeatUntilIterationFrame(
                path: iterationPath,
                start: iterationStart,
                index: iterationIndex,
                count: iterationIndex + 1
            )

            if let failedStep = iterationResults.firstFailedStep {
                let event = await repeatUntilFailedIterationEvent(
                    context: context,
                    step: step,
                    frame: frame,
                    failedStep: failedStep,
                    iterationResults: iterationResults,
                    deadline: deadline,
                    running: running
                )
                state = RepeatUntilLoopState.reduce(state, event: .iterationFailed(event))
                break
            }

            let postBody = await repeatUntilPostBodyCheck(
                context: context,
                step: step,
                observation: running.currentCheck.observation,
                deadline: deadline
            )
            let iterationNode = repeatUntilIterationResult(
                frame: frame,
                step: step,
                outcome: postBody.iterationOutcome,
                observation: postBody.observation,
                children: iterationResults
            )
            state = RepeatUntilLoopState.reduce(
                state,
                event: .iterationPassed(RepeatUntilPassedIterationEvent(
                    frame: frame,
                    postBody: postBody,
                    iterationNode: iterationNode
                ))
            )
            if case .terminal = state {
                break
            }
        }

        if case .running = state {
            state = RepeatUntilLoopState.reduce(
                state,
                event: .deadlineElapsed(UnmetExpectationResult(
                    predicate: step.predicate,
                    actual: "repeat_until deadline elapsed"
                ))
            )
        }

        return await repeatUntilTerminalResult(context: context, step: step, state: state)
    }

    private func repeatUntilFailedIterationEvent(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        frame: RepeatUntilIterationFrame,
        failedStep: HeistExecutionStepResult,
        iterationResults: [HeistExecutionStepResult],
        deadline: CFAbsoluteTime,
        running: RepeatUntilRunningState
    ) async -> RepeatUntilFailedIterationEvent {
        let postBody: RepeatUntilPostBodyCheck?
        if repeatUntilShouldCheckStopPredicate(afterBodyFailure: failedStep, in: iterationResults) {
            postBody = await repeatUntilPostBodyCheck(
                context: context,
                step: step,
                observation: running.currentCheck.observation,
                deadline: deadline
            )
        } else {
            postBody = nil
        }
        let failureExpectation = UnmetExpectationResult(
            predicate: step.predicate,
            actual: "iteration body failed before predicate evaluation"
        )
        let predicateMetIterationNode = repeatUntilIterationResult(
            frame: frame,
            step: step,
            outcome: postBody?.iterationOutcome ?? .continued(failureExpectation),
            observation: postBody?.observation,
            children: repeatUntilIterationResultsDroppingRedundantFailure(
                iterationResults,
                failedPath: failedStep.path
            )
        )
        let failedIterationNode = repeatUntilIterationResult(
            frame: frame,
            step: step,
            outcome: .failed(expectation: failureExpectation, childPath: failedStep.path),
            observation: running.currentCheck.observation,
            children: iterationResults
        )
        return RepeatUntilFailedIterationEvent(
            frame: frame,
            failedStep: failedStep,
            postBody: postBody,
            failureExpectation: failureExpectation,
            predicateMetIterationNode: predicateMetIterationNode,
            failedIterationNode: failedIterationNode
        )
    }

    private func repeatUntilShouldCheckStopPredicate(
        afterBodyFailure failedStep: HeistExecutionStepResult,
        in iterationResults: [HeistExecutionStepResult]
    ) -> Bool {
        guard iterationResults.contains(where: { $0.path == failedStep.path }) else { return false }
        guard failedStep.kind == .action,
              failedStep.failure?.category == .action,
              failedStep.actionEvidence?.dispatchResult?.success == false else {
            return false
        }
        switch failedStep.actionEvidence?.dispatchResult?.errorKind {
        case nil, .some(.actionFailed):
            return true
        case .some(.accessibilityTreeUnavailable),
             .some(.elementNotFound),
             .some(.timeout),
             .some(.validationError),
             .some(.authFailure),
             .some(.general):
            return false
        }
    }

    private func repeatUntilIterationResultsDroppingRedundantFailure(
        _ iterationResults: [HeistExecutionStepResult],
        failedPath: String
    ) -> [HeistExecutionStepResult] {
        iterationResults.filter { $0.path != failedPath }
    }

    private func repeatUntilPostBodyCheck(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        observation: RepeatUntilObservation,
        deadline: CFAbsoluteTime
    ) async -> RepeatUntilPostBodyCheck {
        let remaining = deadline - CFAbsoluteTimeGetCurrent()
        guard remaining > 0 else {
            return .deadlineElapsed(UnmetExpectationResult(
                predicate: step.predicate,
                actual: "repeat_until deadline elapsed"
            ))
        }
        let progressTimeout = min(defaultActionExpectationTimeout, remaining)
        let receipt = await context.runtime.wait(.afterObservation(
            ResolvedWaitStep(predicate: .change(), timeout: progressTimeout),
            baselineTrace: observation.trace,
            sequence: observation.sequence
        ))
        let expectation = repeatUntilStopExpectation(
            step.predicate,
            trace: receipt.accessibilityTrace,
            fallback: receipt.message ?? receipt.expectation.actual
        )
        let stopCheck = PredicateExpectationCheck(expectation)
        let observedCheck = RepeatUntilObservation(receipt).map {
            RepeatUntilObservedCheck(observation: $0, check: stopCheck, receipt: receipt)
        }
        guard receipt.succeeded,
              let check = observedCheck else {
            let noProgressExpectation: UnmetExpectationResult
            switch stopCheck {
            case .met(let metExpectation):
                noProgressExpectation = UnmetExpectationResult(
                    predicate: step.predicate,
                    actual: receipt.observedSequence == nil
                        ? "repeat_until post-body check matched without settled observation"
                        : (metExpectation.result.actual ?? "repeat_until post-body check made no progress")
                )
            case .unmet(let unmetExpectation):
                noProgressExpectation = unmetExpectation
            }
            return .noProgress(
                observation: RepeatUntilObservation(receipt),
                expectation: noProgressExpectation,
                receipt: receipt
            )
        }
        switch check {
        case .met(let check):
            return .changedMet(check)
        case .unmet(let check):
            return .changedUnmet(check)
        }
    }

    private func repeatUntilStopExpectation(
        _ predicate: AccessibilityPredicate,
        trace: AccessibilityTrace?,
        fallback: String?
    ) -> ExpectationResult {
        guard let trace else {
            return ExpectationResult(
                met: false,
                predicate: predicate,
                actual: fallback ?? "no observed accessibility trace"
            )
        }
        return PredicateEvaluation.evaluate(
            predicate,
            currentElements: trace.captures.last?.interface.projectedElements ?? [],
            accumulatedDelta: trace.accumulatedDelta
        )
    }

    private func repeatUntilTerminalResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        state: RepeatUntilLoopState
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
                terminalState: RepeatUntilLoopState.reduce(state, event: .elseCompleted(elseChildren))
            )
        }
        return repeatUntilResult(context: context, step: step, terminalState: state)
    }

    private func repeatUntilResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        terminalState: RepeatUntilLoopState
    ) -> HeistExecutionStepResult {
        guard case .terminal(let terminal) = terminalState else {
            return repeatUntilInternalStateFailure(
                context: context,
                step: step,
                observed: "repeat_until result requires terminal state"
            )
        }
        let terminalResult = RepeatUntilTerminalResult(
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
                predicate: step.predicate.description,
                timeout: step.timeout
            )
        )
    }

    private func repeatUntilIterationResult(
        frame: RepeatUntilIterationFrame,
        step: ResolvedRepeatUntilStep,
        outcome: RepeatUntilIterationOutcome,
        observation: RepeatUntilObservation?,
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
        let receiptOutcome = HeistReceiptOutcome(
            evidence: stepEvidence,
            children: childExecution,
            completedOutcome: HeistReceiptCompletedOutcome(
                failure: outcome.abortedAtChildPath.map {
                    childFailureDetail(category: .loop, childPath: $0)
                }
            ),
            childFailure: { childAbort in
                childFailureDetail(category: .loop, childPath: childAbort.abortedAtChildPath)
            }
        )
        return heistLoopReceipt(
            path: frame.path,
            kind: .repeatUntilIteration,
            durationMs: elapsedMilliseconds(since: frame.start),
            intent: .repeatUntil(
                predicate: step.predicate.description,
                timeout: step.timeout
            ),
            outcome: receiptOutcome
        )
    }

    private func repeatUntilInternalStateFailure(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        observed: String
    ) -> HeistExecutionStepResult {
        heistFailedReceipt(
            path: context.path,
            kind: .repeatUntil,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: .repeatUntil(predicate: step.predicate.description, timeout: step.timeout),
            failure: HeistFailureDetail(
                category: .loop,
                contract: "repeat_until execution reaches a terminal state",
                observed: observed,
                expected: "terminal repeat_until state"
            )
        )
    }

    private func repeatUntilResolutionFailure(
        _ step: RepeatUntilStep,
        path: String,
        start: CFAbsoluteTime,
        error: Error
    ) -> HeistExecutionStepResult {
        heistFailedReceipt(
            path: path,
            kind: .repeatUntil,
            durationMs: elapsedMilliseconds(since: start),
            intent: .repeatUntil(predicate: step.predicate.description, timeout: step.timeout),
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
