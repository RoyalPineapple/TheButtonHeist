import Foundation

import TheScore

extension TheFence {

    // MARK: - Heist Execution and Session State

    func handleRunHeist(_ request: RunHeistRequest) async throws -> FenceResponse {
        let heistStart = CFAbsoluteTimeGetCurrent()
        let executionResult = try await sendAndAwaitHeistExecution(
            request.plan,
            timeout: Timeouts.longActionSeconds
        )
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - heistStart) * 1000)
        let result = HeistExecutionResult(
            steps: executionResult.steps,
            totalTimingMs: totalMs,
            failedIndex: executionResult.failedIndex
        )
        let accessibilityTrace = Self.heistAccessibilityTrace(plan: request.plan, result: result)
        return .heistExecution(
            plan: request.plan,
            result: result,
            accessibilityTrace: accessibilityTrace
        )
    }

    private static func heistAccessibilityTrace(
        plan _: HeistPlan,
        result: HeistExecutionResult
    ) -> AccessibilityTrace? {
        let actionResults = result.finalActionResultsInExecutionOrder
        let actionOutcomeCount = actionResults.count
        let stepAccessibilityTraces = actionResults.compactMap(\.accessibilityTrace)
        guard actionOutcomeCount > 0,
              stepAccessibilityTraces.count == actionOutcomeCount
        else { return nil }
        return AccessibilityTrace.endpointTrace(from: stepAccessibilityTraces)
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
