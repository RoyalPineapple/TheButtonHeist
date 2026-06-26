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
        let actionResult: ActionResult?
        let lastObservedSummary: String?
        let failureReason: String?
        let iterationNodes: [HeistExecutionStepResult]

        func withIterationNodes(_ iterationNodes: [HeistExecutionStepResult]) -> RepeatUntilOutcome {
            RepeatUntilOutcome(
                iterationCount: iterationCount,
                expectation: expectation,
                actionResult: actionResult,
                lastObservedSummary: lastObservedSummary,
                failureReason: failureReason,
                iterationNodes: iterationNodes
            )
        }
    }

    private struct RepeatUntilPostBodyResult {
        let observation: HeistSemanticObservation?
        let observedSequence: UInt64?
        let expectation: ExpectationResult
        let actionResult: ActionResult
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

        guard let initialObservation = await runtime.observeSemanticState(
            resolved.predicate.observationScope,
            nil,
            0
        ) else {
            let expectation = ExpectationResult(
                met: false,
                predicate: resolved.predicate,
                actual: "no settled semantic observation available"
            )
            let failureReason = "could not observe settled semantic hierarchy before evaluating repeat_until"
            return repeatUntilResult(
                context: context,
                step: resolved,
                outcome: RepeatUntilOutcome(
                    iterationCount: 0,
                    expectation: expectation,
                    actionResult: repeatUntilActionResult(
                        observation: nil,
                        success: false,
                        message: failureReason
                    ),
                    lastObservedSummary: nil,
                    failureReason: failureReason,
                    iterationNodes: []
                )
            )
        }

        let initialOutcome = repeatUntilInitialOutcome(step: resolved, observation: initialObservation)
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
                    actionResult: initialOutcome.actionResult,
                    lastObservedSummary: initialOutcome.lastObservedSummary,
                    failureReason: repeatUntilTimeoutReason(step: resolved, expectation: initialOutcome.expectation),
                    iterationNodes: []
                )
            )
        }

        return await repeatUntilLoopResult(
            context: context,
            step: resolved,
            initialObservation: initialObservation,
            initialOutcome: initialOutcome,
            timeout: timeout
        )
    }

    private func repeatUntilInitialOutcome(
        step: ResolvedRepeatUntilStep,
        observation: HeistSemanticObservation
    ) -> RepeatUntilOutcome {
        let changeBaseline = step.predicate.requiresFutureSettledBaseline
            ? observation.event.sequence
            : nil
        let expectation = PredicateEvaluation.evaluate(
            step.predicate,
            in: observation,
            changeBaselineSequence: changeBaseline
        )
        return RepeatUntilOutcome(
            iterationCount: 0,
            expectation: expectation,
            actionResult: repeatUntilActionResult(
                observation: observation,
                success: expectation.met,
                message: expectation.met ? "predicate met before repeat_until body" : expectation.actual
            ),
            lastObservedSummary: observation.summary,
            failureReason: nil,
            iterationNodes: []
        )
    }

    private func repeatUntilLoopResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        initialObservation: HeistSemanticObservation,
        initialOutcome: RepeatUntilOutcome,
        timeout: Double
    ) async -> HeistExecutionStepResult {
        let deadline = context.start + timeout
        var observedSequence = initialObservation.event.sequence
        var lastObservation: HeistSemanticObservation? = initialObservation
        var lastExpectation = initialOutcome.expectation
        var lastActionResult = initialOutcome.actionResult
        var iterationNodes: [HeistExecutionStepResult] = []
        var iterationCount = 0

        while CFAbsoluteTimeGetCurrent() < deadline {
            let iterationIndex = iterationCount
            let iterationStart = CFAbsoluteTimeGetCurrent()
            let iterationPath = "\(context.path).repeat_until.iterations[\(iterationIndex)]"
            let iterationResults = await executeHeistSteps(
                step.body,
                runtime: context.runtime,
                environment: context.environment,
                scope: context.scope,
                path: "\(iterationPath).body"
            )
            iterationCount += 1
            let frame = RepeatUntilIterationFrame(
                path: iterationPath,
                start: iterationStart,
                index: iterationIndex,
                count: iterationCount
            )

            if let abortedAtChildPath = iterationResults.firstFailedStep?.path {
                return repeatUntilBodyFailureResult(
                    context: context,
                    step: step,
                    frame: frame,
                    lastObservedSummary: lastObservation?.summary,
                    abortedAtChildPath: abortedAtChildPath,
                    iterationResults: iterationResults,
                    previousIterationNodes: iterationNodes
                )
            }

            let postBody = await repeatUntilPostBodyResult(
                context: context,
                step: step,
                observedSequence: observedSequence,
                deadline: deadline
            )
            if let observation = postBody.observation {
                lastObservation = observation
            }
            if let sequence = postBody.observedSequence {
                observedSequence = sequence
            }
            lastExpectation = postBody.expectation
            lastActionResult = postBody.actionResult

            let iterationOutcome = RepeatUntilOutcome(
                iterationCount: iterationCount,
                expectation: lastExpectation,
                actionResult: lastActionResult,
                lastObservedSummary: lastObservation?.summary,
                failureReason: nil,
                iterationNodes: []
            )
            iterationNodes.append(repeatUntilIterationResult(
                path: frame.path,
                start: frame.start,
                step: step,
                iterationIndex: frame.index,
                outcome: iterationOutcome,
                abortedAtChildPath: nil,
                children: iterationResults
            ))

            if lastExpectation.met {
                return repeatUntilResult(
                    context: context,
                    step: step,
                    outcome: iterationOutcome.withIterationNodes(iterationNodes)
                )
            }
            if postBody.observation == nil {
                break
            }
        }

        return await repeatUntilTimeoutResult(
            context: context,
            step: step,
            outcome: RepeatUntilOutcome(
                iterationCount: iterationCount,
                expectation: lastExpectation,
                actionResult: lastActionResult,
                lastObservedSummary: lastObservation?.summary,
                failureReason: repeatUntilTimeoutReason(step: step, expectation: lastExpectation),
                iterationNodes: iterationNodes
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
                actionResult: nil,
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
                actionResult: nil,
                lastObservedSummary: lastObservedSummary,
                failureReason: "iteration \(frame.index) failed at \(abortedAtChildPath)",
                iterationNodes: iterationNodes
            )
        )
    }

    private func repeatUntilPostBodyResult(
        context: RepeatUntilExecutionContext,
        step: ResolvedRepeatUntilStep,
        observedSequence: UInt64,
        deadline: CFAbsoluteTime
    ) async -> RepeatUntilPostBodyResult {
        let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
        let observation = await context.runtime.observeSemanticState(
            step.predicate.observationScope,
            observedSequence,
            min(remaining, SemanticObservationTiming.defaultTimeout)
        )
        guard let observation else {
            let expectation = ExpectationResult(
                met: false,
                predicate: step.predicate,
                actual: "no settled semantic observation available"
            )
            return RepeatUntilPostBodyResult(
                observation: nil,
                observedSequence: nil,
                expectation: expectation,
                actionResult: repeatUntilActionResult(
                    observation: nil,
                    success: false,
                    message: expectation.actual
                )
            )
        }
        let expectation = PredicateEvaluation.evaluate(
            step.predicate,
            in: observation,
            changeBaselineSequence: step.predicate.requiresFutureSettledBaseline
                ? observedSequence
                : nil
        )
        return RepeatUntilPostBodyResult(
            observation: observation,
            observedSequence: observation.event.sequence,
            expectation: expectation,
            actionResult: repeatUntilActionResult(
                observation: observation,
                success: expectation.met,
                message: expectation.actual
            )
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
                actionResult: outcome.actionResult,
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
                actionResult: outcome.actionResult,
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

    private func repeatUntilActionResult(
        observation: HeistSemanticObservation?,
        success: Bool,
        message: String?
    ) -> ActionResult {
        ActionResult(
            success: success,
            method: .wait,
            message: message,
            errorKind: success ? nil : .timeout,
            accessibilityTrace: observation?.accessibilityTrace
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
