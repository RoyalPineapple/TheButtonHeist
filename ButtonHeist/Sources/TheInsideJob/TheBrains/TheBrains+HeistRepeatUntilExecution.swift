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

    private struct RepeatUntilProgress {
        let iterationCount: Int
        let expectation: ExpectationResult
        let waitOutcome: HeistWaitOutcome?
        let lastObservedSummary: String?
        let iterationNodes: [HeistExecutionStepResult]

        func withIterationNodes(_ iterationNodes: [HeistExecutionStepResult]) -> RepeatUntilProgress {
            RepeatUntilProgress(
                iterationCount: iterationCount,
                expectation: expectation,
                waitOutcome: waitOutcome,
                lastObservedSummary: lastObservedSummary,
                iterationNodes: iterationNodes
            )
        }
    }

    private enum RepeatUntilReceiptOutcome {
        case predicateMet(RepeatUntilProgress)
        case timedOut(RepeatUntilProgress)
        case initialObservationUnavailable(RepeatUntilProgress)
        case bodyFailed(progress: RepeatUntilProgress, iterationIndex: Int, childPath: String)
        case timedOutHandledByElse(progress: RepeatUntilProgress, elseChildren: [HeistExecutionStepResult])

        var progress: RepeatUntilProgress {
            switch self {
            case .predicateMet(let progress),
                 .timedOut(let progress),
                 .initialObservationUnavailable(let progress),
                 .bodyFailed(let progress, _, _),
                 .timedOutHandledByElse(let progress, _):
                return progress
            }
        }

        var children: [HeistExecutionStepResult] {
            switch self {
            case .timedOutHandledByElse(let progress, let elseChildren):
                return progress.iterationNodes + elseChildren
            case .predicateMet(let progress),
                 .timedOut(let progress),
                 .initialObservationUnavailable(let progress),
                 .bodyFailed(let progress, _, _):
                return progress.iterationNodes
            }
        }

        var status: HeistExecutionStepStatus {
            switch self {
            case .predicateMet:
                return .passed
            case .timedOutHandledByElse(_, let elseChildren):
                return elseChildren.firstFailedStep == nil ? .passed : .failed
            case .timedOut, .initialObservationUnavailable, .bodyFailed:
                return .failed
            }
        }

        var evidenceOutcome: HeistPredicateEvidenceOutcome {
            switch self {
            case .predicateMet:
                return .matched
            case .timedOutHandledByElse:
                return .handledElse
            case .timedOut, .initialObservationUnavailable, .bodyFailed:
                return .failed
            }
        }

        var abortedAtChildPath: String? {
            switch self {
            case .predicateMet, .timedOut, .initialObservationUnavailable:
                return nil
            case .bodyFailed(_, _, let childPath):
                return childPath
            case .timedOutHandledByElse(_, let elseChildren):
                return elseChildren.firstFailedStep?.path
            }
        }

        func failureReason(
            step: ResolvedRepeatUntilStep
        ) -> String? {
            switch self {
            case .predicateMet:
                return nil
            case .timedOut(let progress),
                 .timedOutHandledByElse(let progress, _):
                return RepeatUntilReceiptOutcome.timeoutReason(step: step, expectation: progress.expectation)
            case .initialObservationUnavailable:
                return "could not observe settled semantic hierarchy before evaluating repeat_until"
            case .bodyFailed(_, let iterationIndex, let childPath):
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

    private enum RepeatUntilWaitProgress {
        case observed(HeistWaitOutcome)
        case deadlineElapsed

        var observedSequence: SettledObservationSequence? {
            switch self {
            case .observed(let outcome):
                return outcome.observedSequence
            case .deadlineElapsed:
                return nil
            }
        }

        var observedTrace: AccessibilityTrace? {
            switch self {
            case .observed(let outcome):
                return outcome.accessibilityTrace
            case .deadlineElapsed:
                return nil
            }
        }

        var lastObservedSummary: String? {
            switch self {
            case .observed(let outcome):
                return outcome.observationSummary
            case .deadlineElapsed:
                return nil
            }
        }

        var shouldContinue: Bool {
            switch self {
            case .observed(let outcome):
                return outcome.succeeded
            case .deadlineElapsed:
                return false
            }
        }

        var heistWaitOutcome: HeistWaitOutcome? {
            switch self {
            case .observed(let outcome):
                return outcome
            case .deadlineElapsed:
                return nil
            }
        }
    }

    private struct RepeatUntilPostBodyResult {
        let waitProgress: RepeatUntilWaitProgress
        let expectation: ExpectationResult

        var observedSequence: SettledObservationSequence? {
            waitProgress.observedSequence
        }

        var observedTrace: AccessibilityTrace? {
            waitProgress.observedTrace
        }

        var lastObservedSummary: String? {
            waitProgress.lastObservedSummary
        }
    }

    private struct RepeatUntilLoopState {
        var observedSequence: SettledObservationSequence
        var observedTrace: AccessibilityTrace?
        var lastObservedSummary: String?
        var lastExpectation: ExpectationResult
        var lastWaitOutcome: HeistWaitOutcome?
        var iterationNodes: [HeistExecutionStepResult] = []

        init(
            initialObservedSequence: SettledObservationSequence,
            initialProgress: RepeatUntilProgress
        ) {
            observedSequence = initialObservedSequence
            observedTrace = initialProgress.waitOutcome?.accessibilityTrace
            lastObservedSummary = initialProgress.lastObservedSummary
            lastExpectation = initialProgress.expectation
            lastWaitOutcome = initialProgress.waitOutcome
        }

        mutating func applyPostBody(_ postBody: RepeatUntilPostBodyResult) {
            if let sequence = postBody.observedSequence {
                observedSequence = sequence
            }
            if let trace = postBody.observedTrace {
                observedTrace = trace
            }
            lastObservedSummary = postBody.lastObservedSummary ?? lastObservedSummary
            lastExpectation = postBody.expectation
            lastWaitOutcome = postBody.waitProgress.heistWaitOutcome ?? lastWaitOutcome
        }

        func progress(iterationCount: Int) -> RepeatUntilProgress {
            RepeatUntilProgress(
                iterationCount: iterationCount,
                expectation: lastExpectation,
                waitOutcome: lastWaitOutcome,
                lastObservedSummary: lastObservedSummary,
                iterationNodes: iterationNodes
            )
        }
    }

    private struct RepeatUntilIterationFrame {
        let path: String
        let start: CFAbsoluteTime
        let index: Int
        let count: Int
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
        guard let initialSequence = initialReceipt.observedSequence else {
            let initialProgress = repeatUntilInitialProgress(receipt: initialReceipt)
            return repeatUntilResult(
                context: context,
                step: resolved,
                outcome: .initialObservationUnavailable(initialProgress)
            )
        }

        let initialProgress = repeatUntilInitialProgress(receipt: initialReceipt)
        guard !initialProgress.expectation.met else {
            return repeatUntilResult(
                context: context,
                step: resolved,
                outcome: .predicateMet(initialProgress)
            )
        }

        let timeout = PredicateWait.clampedWaitTimeout(resolved.timeout)
        guard timeout > 0 else {
            return await repeatUntilTimeoutResult(
                context: context,
                step: resolved,
                progress: initialProgress
            )
        }

        return await repeatUntilLoopResult(
            context: context,
            step: resolved,
            initialObservedSequence: initialSequence,
            initialProgress: initialProgress,
            timeout: timeout
        )
    }

    private func repeatUntilInitialProgress(
        receipt: HeistWaitReceipt
    ) -> RepeatUntilProgress {
        return RepeatUntilProgress(
            iterationCount: 0,
            expectation: receipt.expectation,
            waitOutcome: receipt.waitOutcome,
            lastObservedSummary: receipt.observationSummary,
            iterationNodes: []
        )
    }

    private func repeatUntilLoopResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        initialObservedSequence: SettledObservationSequence,
        initialProgress: RepeatUntilProgress,
        timeout: Double
    ) async -> HeistExecutionStepResult {
        let deadline = context.start + timeout
        var state = RepeatUntilLoopState(
            initialObservedSequence: initialObservedSequence,
            initialProgress: initialProgress
        )

        while CFAbsoluteTimeGetCurrent() < deadline {
            let iterationIndex = state.iterationNodes.count
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
                return await repeatUntilResultAfterBodyFailure(
                    context: context,
                    step: step,
                    frame: frame,
                    failedStep: failedStep,
                    iterationResults: iterationResults,
                    deadline: deadline,
                    state: &state
                )
            }

            let postBody = await repeatUntilPostBodyResult(
                context: context,
                step: step,
                observedSequence: state.observedSequence,
                observedTrace: state.observedTrace,
                deadline: deadline
            )
            state.applyPostBody(postBody)

            let iterationProgress = state.progress(iterationCount: frame.count).withIterationNodes([])
            state.iterationNodes.append(repeatUntilIterationResult(
                path: frame.path,
                start: frame.start,
                step: step,
                iterationIndex: frame.index,
                progress: iterationProgress,
                abortedAtChildPath: nil,
                children: iterationResults
            ))

            if state.lastExpectation.met {
                return repeatUntilResult(
                    context: context,
                    step: step,
                    outcome: .predicateMet(iterationProgress.withIterationNodes(state.iterationNodes))
                )
            }
            if !postBody.waitProgress.shouldContinue {
                break
            }
            if postBody.observedSequence == nil {
                break
            }
        }

        return await repeatUntilTimeoutResult(
            context: context,
            step: step,
            progress: state.progress(iterationCount: state.iterationNodes.count)
        )
    }

    private func repeatUntilBodyFailureResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        frame: RepeatUntilIterationFrame,
        lastObservedSummary: String?,
        abortedAtChildPath: String,
        iterationResults: [HeistExecutionStepResult],
        previousIterationNodes: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        var iterationNodes = previousIterationNodes
        let expectation = ExpectationResult(
            met: false,
            predicate: step.predicate,
            actual: "iteration body failed before predicate evaluation"
        )
        iterationNodes.append(repeatUntilIterationResult(
            path: frame.path,
            start: frame.start,
            step: step,
            iterationIndex: frame.index,
            progress: RepeatUntilProgress(
                iterationCount: frame.count,
                expectation: expectation,
                waitOutcome: nil,
                lastObservedSummary: lastObservedSummary,
                iterationNodes: []
            ),
            abortedAtChildPath: abortedAtChildPath,
            children: iterationResults
        ))
        return repeatUntilResult(
            context: context,
            step: step,
            outcome: .bodyFailed(
                progress: RepeatUntilProgress(
                    iterationCount: frame.count,
                    expectation: expectation,
                    waitOutcome: nil,
                    lastObservedSummary: lastObservedSummary,
                    iterationNodes: iterationNodes
                ),
                iterationIndex: frame.index,
                childPath: abortedAtChildPath
            )
        )
    }

    private func repeatUntilResultAfterBodyFailure(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        frame: RepeatUntilIterationFrame,
        failedStep: HeistExecutionStepResult,
        iterationResults: [HeistExecutionStepResult],
        deadline: CFAbsoluteTime,
        state: inout RepeatUntilLoopState
    ) async -> HeistExecutionStepResult {
        if repeatUntilShouldCheckStopPredicate(afterBodyFailure: failedStep, in: iterationResults) {
            let postBody = await repeatUntilPostBodyResult(
                context: context,
                step: step,
                observedSequence: state.observedSequence,
                observedTrace: state.observedTrace,
                deadline: deadline
            )
            state.applyPostBody(postBody)

            if state.lastExpectation.met {
                let iterationProgress = state.progress(iterationCount: frame.count).withIterationNodes([])
                state.iterationNodes.append(repeatUntilIterationResult(
                    path: frame.path,
                    start: frame.start,
                    step: step,
                    iterationIndex: frame.index,
                    progress: iterationProgress,
                    abortedAtChildPath: nil,
                    children: repeatUntilIterationResultsDroppingRedundantFailure(
                        iterationResults,
                        failedPath: failedStep.path
                    )
                ))
                return repeatUntilResult(
                    context: context,
                    step: step,
                    outcome: .predicateMet(iterationProgress.withIterationNodes(state.iterationNodes))
                )
            }
        }

        return repeatUntilBodyFailureResult(
            context: context,
            step: step,
            frame: frame,
            lastObservedSummary: state.lastObservedSummary,
            abortedAtChildPath: failedStep.path,
            iterationResults: iterationResults,
            previousIterationNodes: state.iterationNodes
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

    private func repeatUntilPostBodyResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        observedSequence: SettledObservationSequence,
        observedTrace: AccessibilityTrace?,
        deadline: CFAbsoluteTime
    ) async -> RepeatUntilPostBodyResult {
        let remaining = deadline - CFAbsoluteTimeGetCurrent()
        guard remaining > 0 else {
            let expectation = ExpectationResult(met: false, predicate: step.predicate, actual: "repeat_until deadline elapsed")
            return RepeatUntilPostBodyResult(
                waitProgress: .deadlineElapsed,
                expectation: expectation
            )
        }
        let progressTimeout = min(defaultActionExpectationTimeout, remaining)
        let receipt = await context.runtime.wait(.afterObservation(
            ResolvedWaitStep(predicate: .change(), timeout: progressTimeout),
            baselineTrace: observedTrace,
            sequence: observedSequence
        ))
        let expectation = repeatUntilStopExpectation(
            step.predicate,
            trace: receipt.waitOutcome.accessibilityTrace,
            fallback: receipt.waitOutcome.message ?? receipt.expectation.actual
        )
        return RepeatUntilPostBodyResult(
            waitProgress: .observed(receipt.waitOutcome),
            expectation: expectation
        )
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

    private func repeatUntilTimeoutResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        progress: RepeatUntilProgress
    ) async -> HeistExecutionStepResult {
        guard let elseBody = step.elseBody else {
            return repeatUntilResult(context: context, step: step, outcome: .timedOut(progress))
        }

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
            outcome: .timedOutHandledByElse(progress: progress, elseChildren: elseChildren)
        )
    }

    private func repeatUntilResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        outcome: RepeatUntilReceiptOutcome
    ) -> HeistExecutionStepResult {
        let failureReason = outcome.failureReason(step: step)
        let failure = repeatUntilFailure(
            outcome: outcome,
            step: step,
            failureReason: failureReason
        )
        return heistLoopReceipt(
            path: context.path,
            kind: .repeatUntil,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: .repeatUntil(
                predicate: step.predicate.description,
                timeout: step.timeout
            ),
            evidence: .repeatUntil(HeistRepeatUntilEvidence(
                outcome: outcome.evidenceOutcome,
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: outcome.progress.iterationCount,
                expectation: outcome.progress.expectation,
                actionResult: nil,
                lastObservedSummary: outcome.progress.lastObservedSummary,
                failureReason: failureReason
            )),
            failure: failure,
            abortedAtChildPath: outcome.abortedAtChildPath,
            children: outcome.children
        )
    }

    private func repeatUntilFailure(
        outcome: RepeatUntilReceiptOutcome,
        step: ResolvedRepeatUntilStep,
        failureReason: String?
    ) -> HeistFailureDetail? {
        guard outcome.status == .failed else { return nil }
        if case .bodyFailed = outcome {
            return repeatUntilFailureDetail(step: step, failureReason: failureReason)
        }
        if let abortedAtChildPath = outcome.abortedAtChildPath {
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
        path: String,
        start: CFAbsoluteTime,
        step: ResolvedRepeatUntilStep,
        iterationIndex: Int,
        progress: RepeatUntilProgress,
        abortedAtChildPath: String?,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        heistLoopIterationReceipt(
            path: path,
            kind: .repeatUntilIteration,
            durationMs: elapsedMilliseconds(since: start),
            intent: .repeatUntil(
                predicate: step.predicate.description,
                timeout: step.timeout
            ),
            evidence: .repeatUntil(HeistRepeatUntilEvidence(
                outcome: abortedAtChildPath == nil
                    ? (progress.expectation.met ? .matched : .continued)
                    : .failed,
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: progress.iterationCount,
                iterationOrdinal: iterationIndex,
                expectation: progress.expectation,
                actionResult: nil,
                lastObservedSummary: progress.lastObservedSummary,
                failureReason: abortedAtChildPath.map { "child failed at \($0)" }
            )),
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
