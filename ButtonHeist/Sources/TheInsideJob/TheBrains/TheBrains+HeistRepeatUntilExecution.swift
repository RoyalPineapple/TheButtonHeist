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

    private struct RepeatUntilOutcome {
        let iterationCount: Int
        let expectation: ExpectationResult
        let waitOutcome: HeistWaitOutcome?
        let lastObservedSummary: String?
        let failureReason: String?
        let iterationNodes: [HeistExecutionStepResult]

        func withIterationNodes(_ iterationNodes: [HeistExecutionStepResult]) -> RepeatUntilOutcome {
            RepeatUntilOutcome(
                iterationCount: iterationCount,
                expectation: expectation,
                waitOutcome: waitOutcome,
                lastObservedSummary: lastObservedSummary,
                failureReason: failureReason,
                iterationNodes: iterationNodes
            )
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
        var iterationCount = 0

        init(
            initialObservedSequence: SettledObservationSequence,
            initialOutcome: RepeatUntilOutcome
        ) {
            observedSequence = initialObservedSequence
            observedTrace = initialOutcome.waitOutcome?.accessibilityTrace
            lastObservedSummary = initialOutcome.lastObservedSummary
            lastExpectation = initialOutcome.expectation
            lastWaitOutcome = initialOutcome.waitOutcome
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

        func outcome(failureReason: String? = nil) -> RepeatUntilOutcome {
            RepeatUntilOutcome(
                iterationCount: iterationCount,
                expectation: lastExpectation,
                waitOutcome: lastWaitOutcome,
                lastObservedSummary: lastObservedSummary,
                failureReason: failureReason,
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

    private struct RepeatUntilResultOverride {
        let status: HeistExecutionStepStatus?
        let failure: HeistFailureDetail?
        let abortedAtChildPath: String?

        init(
            status: HeistExecutionStepStatus? = nil,
            failure: HeistFailureDetail? = nil,
            abortedAtChildPath: String? = nil
        ) {
            self.status = status
            self.failure = failure
            self.abortedAtChildPath = abortedAtChildPath
        }
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
            ResolvedWaitStep(predicate: resolved.predicate, timeout: immediateTimeout),
            nil,
            nil
        )
        guard let initialSequence = initialReceipt.observedSequence else {
            let failureReason = "could not observe settled semantic hierarchy before evaluating repeat_until"
            return repeatUntilResult(
                context: context,
                step: resolved,
                outcome: RepeatUntilOutcome(
                    iterationCount: 0,
                    expectation: initialReceipt.expectation,
                    waitOutcome: initialReceipt.waitOutcome,
                    lastObservedSummary: nil,
                    failureReason: failureReason,
                    iterationNodes: []
                )
            )
        }

        let initialOutcome = repeatUntilInitialOutcome(receipt: initialReceipt)
        guard !initialOutcome.expectation.met else {
            return repeatUntilResult(
                context: context,
                step: resolved,
                outcome: initialOutcome
            )
        }

        let timeout = PredicateWait.clampedWaitTimeout(resolved.timeout)
        guard timeout > 0 else {
            return await repeatUntilTimeoutResult(
                context: context,
                step: resolved,
                outcome: RepeatUntilOutcome(
                    iterationCount: 0,
                    expectation: initialOutcome.expectation,
                    waitOutcome: initialOutcome.waitOutcome,
                    lastObservedSummary: initialOutcome.lastObservedSummary,
                    failureReason: repeatUntilTimeoutReason(step: resolved, expectation: initialOutcome.expectation),
                    iterationNodes: []
                )
            )
        }

        return await repeatUntilLoopResult(
            context: context,
            step: resolved,
            initialObservedSequence: initialSequence,
            initialOutcome: initialOutcome,
            timeout: timeout
        )
    }

    private func repeatUntilInitialOutcome(
        receipt: HeistWaitReceipt
    ) -> RepeatUntilOutcome {
        return RepeatUntilOutcome(
            iterationCount: 0,
            expectation: receipt.expectation,
            waitOutcome: receipt.waitOutcome,
            lastObservedSummary: receipt.observationSummary,
            failureReason: nil,
            iterationNodes: []
        )
    }

    private func repeatUntilLoopResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        initialObservedSequence: SettledObservationSequence,
        initialOutcome: RepeatUntilOutcome,
        timeout: Double
    ) async -> HeistExecutionStepResult {
        let deadline = context.start + timeout
        var state = RepeatUntilLoopState(
            initialObservedSequence: initialObservedSequence,
            initialOutcome: initialOutcome
        )

        while CFAbsoluteTimeGetCurrent() < deadline {
            let iterationIndex = state.iterationCount
            let iterationStart = CFAbsoluteTimeGetCurrent()
            let iterationPath = "\(context.path).repeat_until.iterations[\(iterationIndex)]"
            let iterationResults = await executeHeistSteps(
                step.body,
                runtime: context.runtime,
                environment: context.environment,
                scope: context.scope,
                path: "\(iterationPath).body"
            )
            state.iterationCount += 1
            let frame = RepeatUntilIterationFrame(
                path: iterationPath,
                start: iterationStart,
                index: iterationIndex,
                count: state.iterationCount
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

            let iterationOutcome = state.outcome().withIterationNodes([])
            state.iterationNodes.append(repeatUntilIterationResult(
                path: frame.path,
                start: frame.start,
                step: step,
                iterationIndex: frame.index,
                outcome: iterationOutcome,
                abortedAtChildPath: nil,
                children: iterationResults
            ))

            if state.lastExpectation.met {
                return repeatUntilResult(
                    context: context,
                    step: step,
                    outcome: iterationOutcome.withIterationNodes(state.iterationNodes)
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
            outcome: state.outcome(
                failureReason: repeatUntilTimeoutReason(step: step, expectation: state.lastExpectation)
            )
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
            outcome: RepeatUntilOutcome(
                iterationCount: frame.count,
                expectation: expectation,
                waitOutcome: nil,
                lastObservedSummary: lastObservedSummary,
                failureReason: "child failed at \(abortedAtChildPath)",
                iterationNodes: []
            ),
            abortedAtChildPath: abortedAtChildPath,
            children: iterationResults
        ))
        return repeatUntilResult(
            context: context,
            step: step,
            outcome: RepeatUntilOutcome(
                iterationCount: frame.count,
                expectation: expectation,
                waitOutcome: nil,
                lastObservedSummary: lastObservedSummary,
                failureReason: "iteration \(frame.index) failed at \(abortedAtChildPath)",
                iterationNodes: iterationNodes
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
                let iterationOutcome = state.outcome().withIterationNodes([])
                state.iterationNodes.append(repeatUntilIterationResult(
                    path: frame.path,
                    start: frame.start,
                    step: step,
                    iterationIndex: frame.index,
                    outcome: iterationOutcome,
                    abortedAtChildPath: nil,
                    children: repeatUntilIterationResultsDroppingRedundantFailure(
                        iterationResults,
                        failedPath: failedStep.path
                    )
                ))
                return repeatUntilResult(
                    context: context,
                    step: step,
                    outcome: iterationOutcome.withIterationNodes(state.iterationNodes)
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
        case .some(.elementNotFound), .some(.timeout), .some(.validationError), .some(.authFailure), .some(.general):
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
        let receipt = await context.runtime.wait(
            ResolvedWaitStep(predicate: .change(), timeout: progressTimeout),
            observedTrace,
            observedSequence
        )
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
        outcome: RepeatUntilOutcome
    ) async -> HeistExecutionStepResult {
        guard let elseBody = step.elseBody else {
            return repeatUntilResult(context: context, step: step, outcome: outcome)
        }

        let elseChildren = await executeHeistSteps(
            elseBody,
            runtime: context.runtime,
            environment: context.environment,
            scope: context.scope,
            path: "\(context.path).repeat_until.else_body"
        )
        let abortedAtChildPath = elseChildren.firstFailedStep?.path
        return repeatUntilResult(
            context: context,
            step: step,
            outcome: outcome,
            override: RepeatUntilResultOverride(
                status: abortedAtChildPath == nil ? .passed : .failed,
                failure: abortedAtChildPath.map {
                    childFailureDetail(category: .loop, childPath: $0)
                },
                abortedAtChildPath: abortedAtChildPath
            ),
            children: outcome.iterationNodes + elseChildren
        )
    }

    private func repeatUntilResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        outcome: RepeatUntilOutcome,
        override: RepeatUntilResultOverride = RepeatUntilResultOverride(),
        children explicitChildren: [HeistExecutionStepResult]? = nil
    ) -> HeistExecutionStepResult {
        let status = override.status ?? (outcome.failureReason == nil ? .passed : .failed)
        let children = explicitChildren ?? outcome.iterationNodes
        let abortedAtChildPath = override.abortedAtChildPath ?? children.firstFailedStep?.path
        let failure = override.failure ?? (status == .failed ? outcome.failureReason.map {
            HeistFailureDetail(
                category: .loop,
                contract: "repeat_until predicate is met before timeout",
                observed: $0,
                expected: step.predicate.description
            )
        } : nil)
        return HeistExecutionStepResult(
            path: context.path,
            kind: .repeatUntil,
            status: status,
            durationMs: elapsedMilliseconds(since: context.start),
            intent: .repeatUntil(
                predicate: step.predicate.description,
                timeout: step.timeout
            ),
            evidence: .repeatUntil(HeistRepeatUntilEvidence(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: outcome.iterationCount,
                expectation: outcome.expectation,
                actionResult: nil,
                lastObservedSummary: outcome.lastObservedSummary,
                failureReason: outcome.failureReason
            )),
            failure: failure,
            abortedAtChildPath: abortedAtChildPath,
            children: children
        )
    }

    private func repeatUntilIterationResult(
        path: String,
        start: CFAbsoluteTime,
        step: ResolvedRepeatUntilStep,
        iterationIndex: Int,
        outcome: RepeatUntilOutcome,
        abortedAtChildPath: String?,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .repeatUntilIteration,
            status: abortedAtChildPath == nil ? .passed : .failed,
            durationMs: elapsedMilliseconds(since: start),
            intent: .repeatUntil(
                predicate: step.predicate.description,
                timeout: step.timeout
            ),
            evidence: .repeatUntil(HeistRepeatUntilEvidence(
                predicate: step.predicate,
                timeout: step.timeout,
                iterationCount: outcome.iterationCount,
                iterationOrdinal: iterationIndex,
                expectation: outcome.expectation,
                actionResult: nil,
                lastObservedSummary: outcome.lastObservedSummary,
                failureReason: outcome.failureReason
            )),
            failure: abortedAtChildPath.map {
                childFailureDetail(category: .loop, childPath: $0)
            },
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
        HeistExecutionStepResult(
            path: path,
            kind: .repeatUntil,
            status: .failed,
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

    private func repeatUntilTimeoutReason(
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

#endif // DEBUG
#endif // canImport(UIKit)
