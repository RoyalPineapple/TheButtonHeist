#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension TheBrains {
    internal struct HeistActionResolutionFailure {
        let command: HeistActionCommand
        let errorDescription: String
    }

    internal struct HeistExpectationResolutionFailure {
        let wait: WaitStep
        let errorDescription: String
    }

    func executeActionStep(
        _ step: ActionStep,
        index _: Int,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant,
        runtime: HeistExecutionRuntime,
        environment: HeistExecutionEnvironment
    ) async -> HeistExecutionStepResult {
        let resolvedCommand: ResolvedHeistActionCommand
        do {
            resolvedCommand = try step.command.resolve(in: environment)
        } catch {
            return actionResolutionFailureResult(
                HeistActionResolutionFailure(
                    command: step.command,
                    errorDescription: String(describing: error)
                ),
                path: path,
                start: start
            )
        }

        let expectation = step.expectationPolicy.expectedStep
        let baselineScope = expectation?.predicate.requiresChangeBaseline == true
            ? SemanticObservationScope.visible
            : nil
        let execution = await runtime.execute(resolvedCommand, baselineScope)
        let actionResult = execution.result
        guard actionResult.outcome.isSuccess, let expectation else {
            return actionStepResult(
                command: step.command,
                actionResult: actionResult,
                path: path,
                start: start
            )
        }

        let resolvedWait: ResolvedWaitRuntimeInput
        do {
            resolvedWait = try ResolvedWaitRuntimeInput(resolving: expectation, in: environment)
        } catch {
            return expectationResolutionFailureResult(
                HeistExpectationResolutionFailure(
                    wait: expectation,
                    errorDescription: String(describing: error)
                ),
                command: step.command,
                actionResult: actionResult,
                path: path,
                start: start
            )
        }

        let settledTrace = actionResult.settled == true
            ? actionResult.accessibilityTrace
            : nil
        let result = await runtime.wait(.actionEndpoint(
            resolvedWait,
            trace: settledTrace,
            baseline: execution.expectationBaseline
        ))
        return actionExpectationStepResult(
            command: step.command,
            actionResult: actionResult,
            wait: expectation,
            result: result,
            path: path,
            start: start
        )
    }

    private func actionStepResult(
        command: HeistActionCommand,
        actionResult: ActionResult,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant
    ) -> HeistExecutionStepResult {
        let evidence = HeistActionEvidence.dispatch(dispatchResult: actionResult)
        let execution: HeistActionExecution
        switch actionResult.outcome {
        case .success:
            execution = .passed(command: command, evidence: .init(admitted: evidence))
        case .failure:
            execution = .failed(
                command: command,
                evidence: .init(admitted: evidence),
                failure: actionDispatchFailureDetail(command: command, result: actionResult)
            )
        }
        return actionStepResult(
            execution: execution,
            path: path,
            start: start
        )
    }

    private func actionExpectationStepResult(
        command: HeistActionCommand,
        actionResult: ActionResult,
        wait: WaitStep,
        result: HeistWaitResult,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant
    ) -> HeistExecutionStepResult {
        let execution: HeistActionExecution
        switch result.outcome {
        case .matched(let expectationResult, let expectation):
            let evidence = HeistActionEvidence.expectation(
                dispatchResult: actionResult,
                expectationResult: expectationResult,
                expectation: expectation.result
            )
            execution = .passed(command: command, evidence: .init(admitted: evidence))
        case .unmatched(let expectationResult, let expectation):
            let evidence = HeistActionEvidence.expectation(
                dispatchResult: actionResult,
                expectationResult: expectationResult,
                expectation: expectation.result
            )
            execution = .failed(
                command: command,
                evidence: .init(admitted: evidence),
                failure: actionExpectationFailureDetail(wait: wait, result: result)
            )
        }
        return actionStepResult(
            execution: execution,
            path: path,
            start: start
        )
    }

    private func actionStepResult(
        execution: HeistActionExecution,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        return .action(
            path: path,
            durationMs: durationMs,
            execution: execution
        )
    }

    internal func failureScreenshotStep(
        runtime: HeistExecutionRuntime,
        failedPath: HeistExecutionPath,
        mode: ScreenCaptureMode
    ) async -> HeistExecutionStepResult? {
        let start = RuntimeElapsed.now
        let result = mode == .raw
            ? await runtime.execute(.takeScreenshot, nil).result
            : await executeTakeScreenshot(mode: mode)
        guard result.method == .takeScreenshot else { return nil }

        let command = HeistActionCommand.takeScreenshot
        let evidence = HeistActionEvidence.dispatch(dispatchResult: result)
        let execution: HeistActionExecution
        switch result.outcome {
        case .success:
            execution = .passed(command: command, evidence: .init(admitted: evidence))
        case .failure:
            execution = .failed(
                command: command,
                evidence: .init(admitted: evidence),
                failure: failureScreenshotDetail(for: result)
            )
        }
        let path = failedPath.failureAction(at: 0)
        let durationMs = elapsedMilliseconds(since: start)
        return .action(
            path: path,
            durationMs: durationMs,
            execution: execution
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
