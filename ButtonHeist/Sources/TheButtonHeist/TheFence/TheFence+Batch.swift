import Foundation

import TheScore

extension TheFence {

    // MARK: - Batch Execution and Session State

    func handleRunBatch(_ request: RunBatchRequest) async throws -> FenceResponse {
        let batchStart = CFAbsoluteTimeGetCurrent()
        let plannedSteps = request.steps
        let typedSteps = plannedSteps.map(\.typedStep)
        let commands = plannedSteps.map(\.command)

        let executionResult: BatchExecutionResult
        if plannedSteps.isEmpty {
            executionResult = BatchExecutionResult(
                policy: request.policy,
                steps: [],
                totalTimingMs: 0
            )
        } else {
            let plan = TheScore.BatchPlan(
                steps: typedSteps,
                policy: request.policy
            )
            executionResult = try await sendAndAwaitBatchExecution(plan, timeout: Timeouts.longActionSeconds)
        }

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - batchStart) * 1000)
        let result = BatchExecutionResult(
            policy: executionResult.policy,
            steps: executionResult.steps,
            totalTimingMs: totalMs,
            failedIndex: executionResult.failedIndex
        )
        let accessibilityTrace = Self.batchAccessibilityTrace(result)
        return .batch(
            commands: commands,
            steps: typedSteps,
            result: result,
            accessibilityTrace: accessibilityTrace
        )
    }

    private static func batchAccessibilityTrace(
        _ result: BatchExecutionResult
    ) -> AccessibilityTrace? {
        let actionOutcomeCount = result.steps.count { $0.finalActionResult() != nil }
        let stepAccessibilityTraces = result.steps.compactMap { $0.finalActionResult()?.accessibilityTrace }
        guard actionOutcomeCount > 0,
              stepAccessibilityTraces.count == actionOutcomeCount
        else { return nil }
        return AccessibilityTrace.endpointTraceProjection(from: stepAccessibilityTraces)
    }

    // MARK: - Session State

    func currentSessionState() -> SessionStatePayload {
        let connection = sessionConnectionSnapshot
        return SessionStatePayload(
            connected: connection.connected,
            phase: connection.phase,
            device: connection.device,
            actionTimeoutSeconds: Timeouts.actionSeconds,
            longActionTimeoutSeconds: Timeouts.longActionSeconds,
            lastFailure: connection.lastFailure
        )
    }
}
