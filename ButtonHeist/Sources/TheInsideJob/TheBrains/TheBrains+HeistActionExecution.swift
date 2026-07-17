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
        start: CFAbsoluteTime,
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
            return actionReceipt(
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
        let receipt = await runtime.wait(.actionEndpoint(
            resolvedWait,
            trace: settledTrace,
            baseline: execution.expectationBaseline
        ))
        return actionExpectationReceipt(
            command: step.command,
            actionResult: actionResult,
            wait: expectation,
            receipt: receipt,
            path: path,
            start: start
        )
    }

    private func actionReceipt(
        command: HeistActionCommand,
        actionResult: ActionResult,
        path: HeistExecutionPath,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        let evidence = HeistActionEvidence.dispatch(dispatchResult: actionResult)
        let completion: HeistActionCompletion?
        switch actionResult.outcome {
        case .success:
            completion = HeistPassedActionEvidence(evidence).map {
                .passed(evidence: $0)
            }
        case .failure:
            completion = HeistFailedActionEvidence(evidence).map {
                .failed(
                    evidence: $0,
                    failure: actionDispatchFailureDetail(command: command, result: actionResult)
                )
            }
        }
        return actionReceipt(
            command: command,
            completion: completion,
            path: path,
            start: start
        )
    }

    private func actionExpectationReceipt(
        command: HeistActionCommand,
        actionResult: ActionResult,
        wait: WaitStep,
        receipt: HeistWaitReceipt,
        path: HeistExecutionPath,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        let completion: HeistActionCompletion?
        switch receipt.result {
        case .matched(let expectationResult, let expectation):
            let evidence = HeistActionEvidence.expectation(
                dispatchResult: actionResult,
                expectationResult: expectationResult,
                expectation: expectation.result
            )
            completion = HeistPassedActionEvidence(evidence).map {
                .passed(evidence: $0)
            }
        case .unmatched(let expectationResult, let expectation):
            let evidence = HeistActionEvidence.expectation(
                dispatchResult: actionResult,
                expectationResult: expectationResult,
                expectation: expectation.result
            )
            completion = HeistFailedActionEvidence(evidence).map {
                .failed(
                    evidence: $0,
                    failure: actionExpectationFailureDetail(wait: wait, receipt: receipt)
                )
            }
        }
        return actionReceipt(
            command: command,
            completion: completion,
            path: path,
            start: start
        )
    }

    private func actionReceipt(
        command: HeistActionCommand,
        completion: HeistActionCompletion?,
        path: HeistExecutionPath,
        start: CFAbsoluteTime
    ) -> HeistExecutionStepResult {
        let durationMs = elapsedMilliseconds(since: start)
        let admittedCompletion = requireAdmitted(
            completion,
            "action receipt evidence must match the receipt command"
        )
        return requireAdmitted(
            HeistExecutionStepResult.action(
                path: path,
                durationMs: durationMs,
                command: command,
                completion: admittedCompletion
            ),
            "action receipt evidence must match the receipt command"
        )
    }

    internal func failureScreenshotStep(
        runtime: HeistExecutionRuntime,
        failedPath: HeistExecutionPath,
        mode: ScreenCaptureMode
    ) async -> HeistExecutionStepResult? {
        let start = CFAbsoluteTimeGetCurrent()
        let result = mode == .raw
            ? await runtime.execute(.takeScreenshot, nil).result
            : await executeTakeScreenshot(mode: mode)
        guard result.method == .takeScreenshot else { return nil }

        let command = HeistActionCommand.takeScreenshot
        let evidence = HeistActionEvidence.dispatch(dispatchResult: result)
        let completion: HeistActionCompletion?
        switch result.outcome {
        case .success:
            completion = HeistPassedActionEvidence(evidence).map {
                .passed(evidence: $0)
            }
        case .failure:
            completion = HeistFailedActionEvidence(evidence).map {
                .failed(evidence: $0, failure: failureScreenshotDetail(for: result))
            }
        }
        let path = failedPath.failureAction(at: 0)
        let durationMs = elapsedMilliseconds(since: start)
        let admittedCompletion = requireAdmitted(
            completion,
            "failure screenshot receipt evidence must match the screenshot command"
        )
        return requireAdmitted(
            HeistExecutionStepResult.action(
                path: path,
                durationMs: durationMs,
                command: command,
                completion: admittedCompletion
            ),
            "failure screenshot receipt evidence must match the screenshot command"
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
