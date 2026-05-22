import Foundation

import TheScore

extension TheFence {

    // MARK: - Batch Execution and Session State

    public enum BatchPolicy: String, CaseIterable, Sendable {
        case stopOnError = "stop_on_error"
        case continueOnError = "continue_on_error"
    }

    private struct PlannedDispatchStep {
        let originalIndex: Int
        let plan: RunBatchPreparedStep
        let step: TheScore.BatchStep
    }

    func handleRunBatch(_ request: RunBatchRequest) async throws -> FenceResponse {
        let batchStart = CFAbsoluteTimeGetCurrent()
        var outcomesByIndex: [Int: BatchStepOutcome] = [:]
        var plannedSteps: [PlannedDispatchStep] = []
        var preDispatchStopIndex: Int?

        for (index, step) in request.steps.enumerated() {
            switch step {
            case .planned(let stepPlan):
                guard let typedStep = stepPlan.typedStep else {
                    outcomesByIndex[index] = BatchStepOutcome(
                        command: step.commandName,
                        response: .error("run_batch step command \"\(step.commandName)\" is not a complete batch operation"),
                        stopsBatch: request.policy == .stopOnError
                    )
                    if request.policy == .stopOnError {
                        preDispatchStopIndex = index
                        break
                    }
                    continue
                }
                plannedSteps.append(PlannedDispatchStep(
                    originalIndex: index,
                    plan: stepPlan,
                    step: typedStep
                ))

            case .invalid(let commandName, let failure):
                outcomesByIndex[index] = BatchStepOutcome(
                    command: commandName,
                    response: failure.resultResponse,
                    diagnosticDetails: failure.details,
                    stopsBatch: request.policy == .stopOnError
                )
                if request.policy == .stopOnError {
                    preDispatchStopIndex = index
                    break
                }
            }
        }

        if !plannedSteps.isEmpty {
            let plan = TheScore.BatchPlan(
                steps: plannedSteps.map(\.step),
                policy: request.policy.batchExecutionPolicy
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
            preDispatchStopIndex: preDispatchStopIndex,
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
        plannedSteps: [PlannedDispatchStep],
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
        plannedStep: PlannedDispatchStep,
        plannedSteps: [PlannedDispatchStep]
    ) -> BatchStepOutcome {
        if let skipped = stepResult.skipped {
            let afterFailedIndex = plannedSteps.indices.contains(skipped.afterFailedIndex)
                ? plannedSteps[skipped.afterFailedIndex].originalIndex
                : skipped.afterFailedIndex
            return BatchStepOutcome.skipped(
                command: skipped.actionName ?? skipped.expectationName ?? plannedStep.plan.commandName,
                afterFailedIndex: afterFailedIndex
            )
        }

        if let actionResult = stepResult.actionResult ?? stepResult.expectationActionResult {
            let finalResult = stepResult.expectationActionResult ?? actionResult
            recordCompletedAction(finalResult)
            return BatchStepOutcome(
                command: plannedStep.plan.commandName,
                response: .action(
                    result: finalResult,
                    expectation: stepResult.expectation ?? validatedExpectation(
                        for: plannedStep.step,
                        result: finalResult
                    )
                ),
                stopsBatch: stepResult.stopsBatch
            )
        }

        return BatchStepOutcome(
            command: plannedStep.plan.commandName,
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
        preDispatchStopIndex: Int?,
        policy: BatchPolicy
    ) -> Int? {
        guard policy == .stopOnError else { return nil }
        let outcomeStopIndex = outcomesByIndex
            .filter { $0.value.stopsBatch }
            .map(\.key)
            .min()
        switch (preDispatchStopIndex, outcomeStopIndex) {
        case (.some(let lhs), .some(let rhs)):
            return min(lhs, rhs)
        case (.some(let index), .none), (.none, .some(let index)):
            return index
        case (.none, .none):
            return nil
        }
    }

    private static func batchAccessibilityTrace(
        outcomes: [BatchStepOutcome]
    ) -> AccessibilityTrace? {
        let actionOutcomeCount = outcomes.count(where: \.hasActionResult)
        let stepAccessibilityTraces = outcomes.compactMap(\.accessibilityTrace)
        guard actionOutcomeCount > 0,
              stepAccessibilityTraces.count == actionOutcomeCount
        else { return nil }
        return AccessibilityTrace.captureEndpointTrace(from: stepAccessibilityTraces)
    }

    private func skippedStepOutcomes(
        steps: [RunBatchStep], afterFailedIndex failedIndex: Int
    ) -> [BatchStepOutcome] {
        steps.dropFirst(failedIndex + 1).map { step in
            BatchStepOutcome.skipped(command: step.commandName, afterFailedIndex: failedIndex)
        }
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

extension TheFence.BatchPolicy {
    var batchExecutionPolicy: BatchExecutionPolicy {
        switch self {
        case .stopOnError:
            return .stopOnError
        case .continueOnError:
            return .continueOnError
        }
    }
}
