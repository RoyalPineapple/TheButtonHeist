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

    private struct RepeatUntilCheck {
        let observation: RepeatUntilObservation
        let expectation: ExpectationResult
        let receipt: HeistWaitReceipt

        init?(
            receipt: HeistWaitReceipt,
            expectation: ExpectationResult? = nil
        ) {
            guard let observation = RepeatUntilObservation(receipt) else { return nil }
            self.observation = observation
            self.expectation = expectation ?? receipt.expectation
            self.receipt = receipt
        }
    }

    private enum RepeatUntilInitialCheck {
        case unavailable(HeistWaitReceipt)
        case met(RepeatUntilCheck)
        case unmet(RepeatUntilCheck)

        static func make(receipt: HeistWaitReceipt) -> RepeatUntilInitialCheck {
            guard let check = RepeatUntilCheck(receipt: receipt) else {
                return .unavailable(receipt)
            }
            return check.expectation.met ? .met(check) : .unmet(check)
        }
    }

    private enum RepeatUntilPostBodyCheck {
        case deadlineElapsed(ExpectationResult)
        case changedMet(RepeatUntilCheck)
        case changedUnmet(RepeatUntilCheck)
        case noProgress(observation: RepeatUntilObservation?, expectation: ExpectationResult, receipt: HeistWaitReceipt)

        var expectation: ExpectationResult {
            switch self {
            case .deadlineElapsed(let expectation):
                return expectation
            case .changedMet(let check),
                 .changedUnmet(let check):
                return check.expectation
            case .noProgress(_, let expectation, _):
                return expectation
            }
        }

        var observation: RepeatUntilObservation? {
            switch self {
            case .deadlineElapsed:
                return nil
            case .changedMet(let check),
                 .changedUnmet(let check):
                return check.observation
            case .noProgress(let observation, _, _):
                return observation
            }
        }
    }

    private struct RepeatUntilRunningState {
        let currentCheck: RepeatUntilCheck
        let iterationNodes: [HeistExecutionStepResult]

        func appendingIteration(_ node: HeistExecutionStepResult, nextCheck: RepeatUntilCheck) -> RepeatUntilRunningState {
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
                switch event.postBody {
                case .changedMet(let check):
                    let nodes = running.iterationNodes + [event.iterationNode]
                    return .terminal(.predicateMet(
                        check: check,
                        iterationCount: event.frame.count,
                        iterationNodes: nodes
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
            case (.running(let running), .iterationFailed(let event)):
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
            case (.terminal(let terminal), .elseCompleted(let children)):
                switch terminal {
                case .timedOut(let observation, let expectation, let iterationCount, let iterationNodes):
                    if let failedPath = children.firstFailedStep?.path {
                        return .terminal(.timeoutElseFailed(
                            observation: observation,
                            expectation: expectation,
                            iterationCount: iterationCount,
                            iterationNodes: iterationNodes,
                            elseChildren: children,
                            childPath: failedPath
                        ))
                    }
                    return .terminal(.timeoutHandledByElse(
                        observation: observation,
                        expectation: expectation,
                        iterationCount: iterationCount,
                        iterationNodes: iterationNodes,
                        elseChildren: children
                    ))
                case .predicateMet,
                     .initialObservationUnavailable,
                     .bodyFailed,
                     .timeoutHandledByElse,
                     .timeoutElseFailed:
                    return state
                }
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
    }

    private enum RepeatUntilLoopEvent {
        case initial(RepeatUntilInitialCheck)
        case deadlineElapsed(ExpectationResult)
        case iterationPassed(RepeatUntilPassedIterationEvent)
        case iterationFailed(RepeatUntilFailedIterationEvent)
        case elseCompleted([HeistExecutionStepResult])
    }

    private enum RepeatUntilTerminal {
        case predicateMet(check: RepeatUntilCheck, iterationCount: Int, iterationNodes: [HeistExecutionStepResult])
        case timedOut(
            observation: RepeatUntilObservation?,
            expectation: ExpectationResult,
            iterationCount: Int,
            iterationNodes: [HeistExecutionStepResult]
        )
        case initialObservationUnavailable(HeistWaitReceipt)
        case bodyFailed(
            observation: RepeatUntilObservation,
            expectation: ExpectationResult,
            iterationIndex: Int,
            childPath: String,
            iterationNodes: [HeistExecutionStepResult]
        )
        case timeoutHandledByElse(
            observation: RepeatUntilObservation?,
            expectation: ExpectationResult,
            iterationCount: Int,
            iterationNodes: [HeistExecutionStepResult],
            elseChildren: [HeistExecutionStepResult]
        )
        case timeoutElseFailed(
            observation: RepeatUntilObservation?,
            expectation: ExpectationResult,
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

        var status: HeistExecutionStepStatus {
            switch self {
            case .predicateMet, .timeoutHandledByElse:
                return .passed
            case .timedOut, .initialObservationUnavailable, .bodyFailed, .timeoutElseFailed:
                return .failed
            }
        }

        var abortedAtChildPath: String? {
            switch self {
            case .predicateMet, .timedOut, .initialObservationUnavailable, .timeoutHandledByElse:
                return nil
            case .bodyFailed(_, _, _, let childPath, _),
                 .timeoutElseFailed(_, _, _, _, _, let childPath):
                return childPath
            }
        }

        func expectation(step: ResolvedRepeatUntilStep) -> ExpectationResult {
            switch self {
            case .predicateMet(let check, _, _):
                return check.expectation
            case .timedOut(_, let expectation, _, _),
                 .bodyFailed(_, let expectation, _, _, _),
                 .timeoutHandledByElse(_, let expectation, _, _, _),
                 .timeoutElseFailed(_, let expectation, _, _, _, _):
                return expectation
            case .initialObservationUnavailable(let receipt):
                return receipt.expectation.met
                    ? ExpectationResult(met: false, predicate: step.predicate, actual: "initial observation unavailable")
                    : receipt.expectation
            }
        }

        func lastObservedSummary() -> String? {
            switch self {
            case .predicateMet(let check, _, _):
                return check.observation.summary
            case .timedOut(let observation, _, _, _),
                 .timeoutHandledByElse(let observation, _, _, _, _),
                 .timeoutElseFailed(let observation, _, _, _, _, _):
                return observation?.summary
            case .bodyFailed(let observation, _, _, _, _):
                return observation.summary
            case .initialObservationUnavailable(let receipt):
                return receipt.observationSummary
            }
        }

        func iterationCount() -> Int {
            switch self {
            case .predicateMet(_, let iterationCount, _),
                 .timedOut(_, _, let iterationCount, _),
                 .timeoutHandledByElse(_, _, let iterationCount, _, _),
                 .timeoutElseFailed(_, _, let iterationCount, _, _, _):
                return iterationCount
            case .bodyFailed(_, _, let iterationIndex, _, _):
                return iterationIndex + 1
            case .initialObservationUnavailable:
                return 0
            }
        }

        func failureReason(step: ResolvedRepeatUntilStep) -> String? {
            switch self {
            case .predicateMet:
                return nil
            case .timedOut(_, let expectation, _, _),
                 .timeoutHandledByElse(_, let expectation, _, _, _),
                 .timeoutElseFailed(_, let expectation, _, _, _, _):
                return RepeatUntilTerminal.timeoutReason(step: step, expectation: expectation)
            case .initialObservationUnavailable:
                return "could not observe settled semantic hierarchy before evaluating repeat_until"
            case .bodyFailed(_, _, let iterationIndex, let childPath, _):
                return "iteration \(iterationIndex) failed at \(childPath)"
            }
        }

        private static func timeoutReason(
            step: ResolvedRepeatUntilStep,
            expectation: ExpectationResult
        ) -> String {
            let timeout = String(
                format: "%.1f",
                locale: Locale(identifier: "en_US_POSIX"),
                PredicateWait.clampedWaitTimeout(step.timeout)
            )
            return [
                "timed out after \(timeout)s waiting for repeat_until predicate",
                "expected: \(step.predicate.description)",
                "last result: \(expectation.actual ?? "not met")",
            ].joined(separator: "; ")
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
        let failureExpectation: ExpectationResult
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
                event: .deadlineElapsed(ExpectationResult(
                    met: false,
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
                expectation: postBody.expectation,
                observation: postBody.observation,
                abortedAtChildPath: nil,
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
                event: .deadlineElapsed(ExpectationResult(
                    met: false,
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
        let failureExpectation = ExpectationResult(
            met: false,
            predicate: step.predicate,
            actual: "iteration body failed before predicate evaluation"
        )
        let predicateMetExpectation = postBody?.expectation ?? failureExpectation
        let predicateMetIterationNode = repeatUntilIterationResult(
            frame: frame,
            step: step,
            expectation: predicateMetExpectation,
            observation: postBody?.observation,
            abortedAtChildPath: nil,
            children: repeatUntilIterationResultsDroppingRedundantFailure(
                iterationResults,
                failedPath: failedStep.path
            )
        )
        let failedIterationNode = repeatUntilIterationResult(
            frame: frame,
            step: step,
            expectation: failureExpectation,
            observation: running.currentCheck.observation,
            abortedAtChildPath: failedStep.path,
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
              failedStep.actionEvidence?.actionResult?.success == false else {
            return false
        }
        switch failedStep.actionEvidence?.actionResult?.errorKind {
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
            return .deadlineElapsed(ExpectationResult(
                met: false,
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
        guard receipt.succeeded,
              let check = RepeatUntilCheck(receipt: receipt, expectation: expectation) else {
            let noProgressExpectation = expectation.met
                ? ExpectationResult(
                    met: false,
                    predicate: step.predicate,
                    actual: receipt.observedSequence == nil
                        ? "repeat_until post-body check matched without settled observation"
                        : (expectation.actual ?? "repeat_until post-body check made no progress")
                )
                : expectation
            return .noProgress(
                observation: RepeatUntilObservation(receipt),
                expectation: noProgressExpectation,
                receipt: receipt
            )
        }
        return expectation.met ? .changedMet(check) : .changedUnmet(check)
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
            preconditionFailure("repeat_until execution ended without terminal state")
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
            preconditionFailure("repeat_until result requires terminal state")
        }
        let failureReason = terminal.failureReason(step: step)
        let failure = repeatUntilFailure(
            terminal: terminal,
            step: step,
            failureReason: failureReason
        )
        return repeatUntilResult(
            context: context,
            step: step,
            terminal: terminal,
            evidence: repeatUntilEvidence(
                terminal: terminal,
                step: step,
                failureReason: failureReason
            ),
            failure: failure,
            failureReason: failureReason
        )
    }

    private func repeatUntilResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        terminal: RepeatUntilTerminal,
        evidence: HeistRepeatUntilEvidence,
        failure: HeistFailureDetail?,
        failureReason _: String?
    ) -> HeistExecutionStepResult {
        return heistLoopReceipt(
            path: context.path,
            kind: .repeatUntil,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: .repeatUntil(
                predicate: step.predicate.description,
                timeout: step.timeout
            ),
            evidence: .repeatUntil(evidence),
            failure: failure,
            abortedAtChildPath: terminal.abortedAtChildPath,
            children: terminal.children
        )
    }

    private func repeatUntilEvidence(
        terminal: RepeatUntilTerminal,
        step: ResolvedRepeatUntilStep,
        failureReason: String?
    ) -> HeistRepeatUntilEvidence {
        let evidence: HeistRepeatUntilEvidence?
        switch terminal {
        case .predicateMet(let check, let iterationCount, _):
            evidence = HeistRepeatUntilEvidence.predicateMet(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: iterationCount,
                expectation: check.expectation,
                lastObservedSummary: check.observation.summary
            )
        case .timedOut(let observation, let expectation, let iterationCount, _):
            evidence = HeistRepeatUntilEvidence.timedOut(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: iterationCount,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: failureReason ?? "repeat_until timed out"
            )
        case .initialObservationUnavailable(let receipt):
            evidence = HeistRepeatUntilEvidence.initialObservationUnavailable(
                predicate: step.predicate,
                timeout: step.timeout,
                expectation: terminal.expectation(step: step),
                lastObservedSummary: receipt.observationSummary,
                failureReason: failureReason ?? "could not observe settled semantic hierarchy before evaluating repeat_until"
            )
        case .bodyFailed(let observation, let expectation, _, _, _):
            evidence = HeistRepeatUntilEvidence.bodyFailed(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: terminal.iterationCount(),
                expectation: expectation,
                lastObservedSummary: observation.summary,
                failureReason: failureReason ?? "repeat_until body failed"
            )
        case .timeoutHandledByElse(let observation, let expectation, let iterationCount, _, _):
            evidence = HeistRepeatUntilEvidence.timeoutHandledByElse(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: iterationCount,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: failureReason
            )
        case .timeoutElseFailed(let observation, let expectation, let iterationCount, _, _, _):
            evidence = HeistRepeatUntilEvidence.timeoutHandledByElse(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: iterationCount,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: failureReason
            )
        }
        guard let evidence else {
            preconditionFailure("Invalid repeat_until terminal evidence")
        }
        return evidence
    }

    private func repeatUntilFailure(
        terminal: RepeatUntilTerminal,
        step: ResolvedRepeatUntilStep,
        failureReason: String?
    ) -> HeistFailureDetail? {
        guard terminal.status == .failed else { return nil }
        if case .bodyFailed = terminal {
            return repeatUntilFailureDetail(step: step, failureReason: failureReason)
        }
        if let abortedAtChildPath = terminal.abortedAtChildPath {
            return childFailureDetail(category: .loop, childPath: abortedAtChildPath)
        }
        return repeatUntilFailureDetail(step: step, failureReason: failureReason)
    }

    private func repeatUntilFailureDetail(
        step: ResolvedRepeatUntilStep,
        failureReason: String?
    ) -> HeistFailureDetail? {
        return failureReason.map {
            HeistFailureDetail(
                category: .loop,
                contract: "repeat_until predicate is met before timeout",
                observed: $0,
                expected: step.predicate.description
            )
        }
    }

    private func repeatUntilIterationResult(
        frame: RepeatUntilIterationFrame,
        step: ResolvedRepeatUntilStep,
        expectation: ExpectationResult,
        observation: RepeatUntilObservation?,
        abortedAtChildPath: String?,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        let evidence: HeistRepeatUntilEvidence?
        if let abortedAtChildPath {
            evidence = HeistRepeatUntilEvidence.failedIteration(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary,
                failureReason: "child failed at \(abortedAtChildPath)"
            )
        } else if expectation.met {
            evidence = HeistRepeatUntilEvidence.predicateMet(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary
            )
        } else {
            evidence = HeistRepeatUntilEvidence.continued(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: frame.count,
                iterationOrdinal: frame.index,
                expectation: expectation,
                lastObservedSummary: observation?.summary
            )
        }
        guard let evidence else {
            preconditionFailure("Invalid repeat_until iteration evidence")
        }
        return heistLoopIterationReceipt(
            path: frame.path,
            kind: .repeatUntilIteration,
            durationMs: elapsedMilliseconds(since: frame.start),
            intent: .repeatUntil(
                predicate: step.predicate.description,
                timeout: step.timeout
            ),
            evidence: .repeatUntil(evidence),
            abortedAtChildPath: abortedAtChildPath,
            children: children
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
