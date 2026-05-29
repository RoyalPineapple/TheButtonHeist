import Foundation

import TheScore

extension TheFence {

    // MARK: - Batch Execution and Session State

    func handleRunBatch(_ request: RunBatchRequest) async throws -> FenceResponse {
        let batchStart = CFAbsoluteTimeGetCurrent()
        var outcomesByIndex: [Int: BatchStepOutcome] = [:]
        let plannedSteps = request.steps

        if !plannedSteps.isEmpty {
            let plan = TheScore.BatchPlan(
                steps: plannedSteps.map(\.typedStep),
                policy: request.policy
            )
            let result = try await sendAndAwaitBatchExecution(plan, timeout: Timeouts.longActionSeconds)
            mergeBatchExecutionResult(
                result,
                plannedSteps: plannedSteps,
                outcomesByIndex: &outcomesByIndex
            )
        }

        let stoppedIndex = stoppedIndex(
            outcomesByIndex: outcomesByIndex,
            policy: request.policy
        )
        if let stoppedIndex, request.policy == .stopOnError {
            for index in request.steps.indices where index > stoppedIndex {
                outcomesByIndex[index] = BatchStepOutcome.skipped(
                    command: request.steps[index].commandName,
                    afterFailedIndex: stoppedIndex
                )
            }
        }

        let outcomes = request.steps.indices.compactMap { outcomesByIndex[$0] }
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - batchStart) * 1000)
        let accessibilityTrace = Self.batchAccessibilityTrace(outcomes: outcomes)
        return .batch(
            outcomes: outcomes,
            totalTimingMs: totalMs,
            accessibilityTrace: accessibilityTrace
        )
    }

    private func mergeBatchExecutionResult(
        _ result: BatchExecutionResult,
        plannedSteps: [RunBatchPreparedStep],
        outcomesByIndex: inout [Int: BatchStepOutcome]
    ) {
        for stepResult in result.steps {
            guard plannedSteps.indices.contains(stepResult.index) else { continue }
            let plannedStep = plannedSteps[stepResult.index]
            let outcome = batchStepOutcome(
                from: stepResult,
                plannedStep: plannedStep,
                plannedSteps: plannedSteps
            )
            outcomesByIndex[plannedStep.originalIndex] = outcome
        }
    }

    private func batchStepOutcome(
        from stepResult: BatchExecutionStepResult,
        plannedStep: RunBatchPreparedStep,
        plannedSteps: [RunBatchPreparedStep]
    ) -> BatchStepOutcome {
        if let skipped = stepResult.skipped {
            let afterFailedIndex = plannedSteps.indices.contains(skipped.afterFailedIndex)
                ? plannedSteps[skipped.afterFailedIndex].originalIndex
                : skipped.afterFailedIndex
            return BatchStepOutcome.skipped(
                command: skipped.actionName ?? skipped.expectationName ?? plannedStep.commandName,
                afterFailedIndex: afterFailedIndex
            )
        }

        if let actionResult = stepResult.actionResult ?? stepResult.expectationActionResult {
            let finalResult = stepResult.expectationActionResult ?? actionResult
            commandExecutionState.completeAction(finalResult)
            return BatchStepOutcome(
                command: plannedStep.commandName,
                response: .action(
                    command: plannedStep.command,
                    result: finalResult,
                    expectation: stepResult.expectation ?? validatedExpectation(
                        for: plannedStep.typedStep,
                        result: finalResult
                    )
                ),
                stopsBatch: stepResult.stopsBatch
            )
        }

        return BatchStepOutcome(
            command: plannedStep.commandName,
            response: .error("typed batch step produced no action result"),
            stopsBatch: stepResult.stopsBatch
        )
    }

    private func validatedExpectation(
        for step: TheScore.BatchStep,
        result: ActionResult
    ) -> ExpectationResult? {
        step.expectation.validate(against: result)
    }

    private func stoppedIndex(
        outcomesByIndex: [Int: BatchStepOutcome],
        policy: BatchExecutionPolicy
    ) -> Int? {
        guard policy == .stopOnError else { return nil }
        return outcomesByIndex
            .filter { $0.value.stopsBatch }
            .map(\.key)
            .min()
    }

    private static func batchAccessibilityTrace(
        outcomes: [BatchStepOutcome]
    ) -> AccessibilityTrace? {
        let actionOutcomeCount = outcomes.count(where: \.hasActionResult)
        let stepAccessibilityTraces = outcomes.compactMap(\.accessibilityTrace)
        guard actionOutcomeCount > 0,
              stepAccessibilityTraces.count == actionOutcomeCount
        else { return nil }
        return AccessibilityTrace.endpointTraceProjection(from: stepAccessibilityTraces)
    }

    // MARK: - Session State

    func currentSessionState() -> SessionStatePayload {
        let connection = sessionConnectionSnapshot
        let recording = recordingSnapshot
        return SessionStatePayload(
            connected: connection.connected,
            phase: connection.phase,
            device: connection.device,
            isRecording: recording.isRecording,
            actionTimeoutSeconds: Timeouts.actionSeconds,
            longActionTimeoutSeconds: Timeouts.longActionSeconds,
            lastFailure: connection.lastFailure,
            lastAction: commandExecutionState.lastAction.sessionPayload
        )
    }
}
