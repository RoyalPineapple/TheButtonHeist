#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    internal func executeRepeatUntilStep(
        _ step: RepeatUntilStep,
        index _: Int,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment,
        scope: HeistExecutionScope
    ) async -> HeistExecutionStepResult {
        let context = RepeatUntil.Context(
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

        let initialState = await runtime.settle(
            .currentState(scope: resolved.predicate.observationScope)
        )
        let state = RepeatUntil.LoopState.running(
            RepeatUntil.RunningState(
                currentObservation: RepeatUntil.ObservedState(initialState)
            )
        )
        return await repeatUntilLoopResult(
            context: context,
            step: resolved,
            state: state,
            timeout: resolved.timeout
        )
    }

    private func repeatUntilLoopResult(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        state initialState: RepeatUntil.LoopState,
        timeout: WaitTimeout
    ) async -> HeistExecutionStepResult {
        let deadline = SemanticObservationDeadline(
            start: context.start,
            timeoutSeconds: timeout.seconds
        )
        var state = initialState

        while case .running(let running) = state {
            guard running.iterationNodes.values.isEmpty || deadline.hasTimeRemaining(at: RuntimeElapsed.now) else {
                break
            }
            let iterationIndex = running.iterationNodes.values.count
            let iterationStart = RuntimeElapsed.now
            let iterationPath = context.path.repeatUntilIteration(at: iterationIndex)
            let iterationResults = await executeHeistSteps(
                step.body,
                runtime: context.runtime,
                environment: context.environment,
                scope: context.scope,
                path: iterationPath.iterationBody()
            )
            let frame = RepeatUntil.IterationFrame(
                path: iterationPath,
                start: iterationStart,
                index: iterationIndex,
                count: iterationIndex + 1
            )

            switch iterationResults {
            case .aborted(let children):
                let event = await repeatUntilFailedIterationEvent(
                    context: context,
                    step: step,
                    frame: frame,
                    children: children,
                    deadline: deadline,
                    running: running
                )
                state = RepeatUntil.LoopState.reduce(state, event: .iterationFailed(event))
            case .passed(let children):
                let postBody = await repeatUntilPostBodyCheck(
                    context: context,
                    step: step,
                    observation: running.currentObservation,
                    iterationResults: children,
                    deadline: deadline
                )
                let iteration = repeatUntilPassingIterationResult(
                    frame: frame,
                    step: step,
                    postBody: postBody,
                    children: children
                )
                state = RepeatUntil.LoopState.reduce(
                    state,
                    event: .iterationPassed(RepeatUntil.PassedIterationEvent(
                        frame: frame,
                        postBody: postBody,
                        iteration: iteration
                    ))
                )
            }
            if case .terminal = state {
                break
            }
        }

        if case .running = state {
            state = RepeatUntil.LoopState.reduce(
                state,
                event: .deadlineElapsed(ExpectationResult.Unmet(
                    predicate: step.predicateExpression,
                    actual: "repeat_until deadline elapsed"
                ))
            )
        }

        return await repeatUntilTerminalResult(context: context, step: step, state: state)
    }

    private func repeatUntilFailedIterationEvent(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        frame: RepeatUntil.IterationFrame,
        children: HeistAbortedChildren,
        deadline: SemanticObservationDeadline,
        running: RepeatUntil.RunningState
    ) async -> RepeatUntil.FailedIterationEvent {
        let failureExpectation = ExpectationResult.Unmet(
            predicate: step.predicateExpression,
            actual: "iteration body failed before predicate evaluation"
        )
        let predicateEvaluation: RepeatUntil.FailedBodyPredicateEvaluation
        switch repeatUntilBodyFailureDisposition(children) {
        case .checkPredicate(let predicateChildren):
            let postBody = await repeatUntilPostBodyCheck(
                context: context,
                step: step,
                observation: running.currentObservation,
                iterationResults: predicateChildren,
                deadline: deadline
            )
            let predicateMetIteration = repeatUntilPassingIterationResult(
                frame: frame,
                step: step,
                postBody: postBody,
                children: predicateChildren
            )
            predicateEvaluation = .checked(postBody, predicateMetIteration: predicateMetIteration)
        case .abort:
            predicateEvaluation = .notChecked
        }
        let failedIteration = repeatUntilFailedIterationResult(
            frame: frame,
            step: step,
            expectation: failureExpectation,
            observation: running.currentObservation,
            children: children
        )
        return RepeatUntil.FailedIterationEvent(
            frame: frame,
            predicateEvaluation: predicateEvaluation,
            failureExpectation: failureExpectation,
            failedIteration: failedIteration
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
