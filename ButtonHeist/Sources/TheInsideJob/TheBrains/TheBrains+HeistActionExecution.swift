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
        let resolvedExpectation: Settlement.ActionExpectation?
        do {
            resolvedExpectation = try expectation.map {
                let resolved = try $0.resolve(in: environment)
                return Settlement.ActionExpectation(
                    authored: $0.predicate,
                    resolved: resolved.predicate,
                    timeout: resolved.timeout
                )
            }
        } catch {
            guard let expectation else {
                preconditionFailure("Expectation resolution failed without an authored expectation")
            }
            let observed = "could not resolve heist expectation: \(error)"
            return expectationResolutionFailureResult(
                HeistExpectationResolutionFailure(
                    wait: expectation,
                    errorDescription: String(describing: error)
                ),
                command: step.command,
                actionResult: .failure(
                    payload: resolvedCommand.actionResultPayload,
                    failureKind: .validationError,
                    message: observed
                ),
                path: path,
                start: start
            )
        }

        let execution = await runtime.execute(resolvedCommand, resolvedExpectation)
        return actionStepResult(
            command: step.command,
            evidence: execution.evidence,
            expectation: expectation,
            path: path,
            start: start
        )
    }

    private func actionStepResult(
        command: HeistActionCommand,
        evidence: HeistActionEvidence,
        expectation: WaitStep?,
        path: HeistExecutionPath,
        start: RuntimeElapsed.Instant
    ) -> HeistExecutionStepResult {
        let execution: HeistActionExecution
        guard let result = evidence.result else {
            preconditionFailure("Resolved action execution requires action result evidence")
        }
        if !result.outcome.isSuccess, let expectation, evidence.expectation != nil {
            execution = .failed(
                command: command,
                evidence: .init(admitted: evidence),
                failure: actionExpectationFailureDetail(
                    wait: expectation,
                    evidence: evidence
                )
            )
        } else if !result.outcome.isSuccess {
            execution = .failed(
                command: command,
                evidence: .init(admitted: evidence),
                failure: actionDispatchFailureDetail(command: command, result: result)
            )
        } else {
            execution = .passed(command: command, evidence: .init(admitted: evidence))
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
            : await executeTakeScreenshot(mode: mode).result
        guard result.method == .takeScreenshot else { return nil }

        let command = HeistActionCommand.takeScreenshot
        let evidence = HeistActionEvidence.completed(result: result, expectation: nil)
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
