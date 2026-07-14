#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains {
    internal func executeRepeatUntilStep(
        _ step: RepeatUntilStep,
        index _: Int,
        path: String,
        start: CFAbsoluteTime,
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

        let initialReceipt = await runtime.wait(
            .immediate(ResolvedWaitRuntimeInput(
                repeatUntil: resolved,
                timeout: immediateTimeout
            ))
        )
        var state = RepeatUntil.LoopState.reduce(
            .awaitingInitial,
            event: .initial(RepeatUntil.InitialCheck.make(receipt: initialReceipt))
        )
        let timeout = PredicateWait.clampedWaitTimeout(resolved.timeout)

        if case .running = state, timeout <= 0 {
            state = RepeatUntil.LoopState.reduce(
                state,
                event: .deadlineElapsed(ExpectationResult.Unmet(
                    predicate: resolved.predicateExpression,
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
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        state initialState: RepeatUntil.LoopState,
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
            let frame = RepeatUntil.IterationFrame(
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
                state = RepeatUntil.LoopState.reduce(state, event: .iterationFailed(event))
                break
            }

            let postBody = await repeatUntilPostBodyCheck(
                context: context,
                step: step,
                observation: running.currentCheck.observation,
                iterationResults: iterationResults,
                deadline: deadline
            )
            let iterationNode = repeatUntilIterationResult(
                frame: frame,
                step: step,
                outcome: postBody.iterationOutcome,
                observation: postBody.observation,
                children: iterationResults
            )
            state = RepeatUntil.LoopState.reduce(
                state,
                event: .iterationPassed(RepeatUntil.PassedIterationEvent(
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
        failedStep: HeistExecutionStepResult,
        iterationResults: [HeistExecutionStepResult],
        deadline: CFAbsoluteTime,
        running: RepeatUntil.RunningState
    ) async -> RepeatUntil.FailedIterationEvent {
        let postBody: RepeatUntil.PostBodyCheck?
        if repeatUntilShouldCheckStopPredicate(afterBodyFailure: failedStep, in: iterationResults) {
            postBody = await repeatUntilPostBodyCheck(
                context: context,
                step: step,
                observation: running.currentCheck.observation,
                iterationResults: iterationResults,
                deadline: deadline
            )
        } else {
            postBody = nil
        }
        let failureExpectation = ExpectationResult.Unmet(
            predicate: step.predicateExpression,
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
        return RepeatUntil.FailedIterationEvent(
            frame: frame,
            failedStep: failedStep,
            postBody: postBody,
            failureExpectation: failureExpectation,
            predicateMetIterationNode: predicateMetIterationNode,
            failedIterationNode: failedIterationNode
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
