import Foundation

import ThePlans
import TheScore

extension TheFence {

    // MARK: - Heist Execution and Session State

    func handleRunHeist(_ request: RunHeistRequest) async throws -> FenceResponse {
        try await runHeistPlan(request.plan, argument: request.argument, timeout: Timeouts.longActionSeconds)
    }

    func handleListHeists(_ request: ListHeistsRequest) -> FenceResponse {
        .heistCatalog(request.catalog)
    }

    func handleDescribeHeist(_ request: DescribeHeistRequest) -> FenceResponse {
        .heistDescription(request.description)
    }

    /// Dispatch a `HeistPlan` to the device and project its execution into a
    /// `.heistExecution` response. Single commands and composed heists share
    /// this one path — a single command is just a one-step plan.
    func runHeistPlan(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: TimeInterval
    ) async throws -> FenceResponse {
        let heistStart = CFAbsoluteTimeGetCurrent()
        let executionResult = try await sendAndAwaitHeistExecution(plan, argument: argument, timeout: timeout)
        let totalMs = Int((CFAbsoluteTimeGetCurrent() - heistStart) * 1000)
        let result = HeistExecutionResult(
            steps: executionResult.steps,
            durationMs: totalMs,
            abortedAtPath: executionResult.abortedAtPath
        )
        let accessibilityTrace = Self.heistAccessibilityTrace(plan: plan, result: result)
        return .heistExecution(
            plan: plan,
            result: result,
            accessibilityTrace: accessibilityTrace
        )
    }

    // MARK: - Single-Step Execution

    /// Build a one-step `HeistPlan` for a single executable command, or `nil`
    /// when the command is not an action/wait (e.g. the `get_pasteboard` read,
    /// interface/screen/session commands) and must use its dedicated handler.
    ///
    /// A `wait` command becomes a single wait step; UI action commands become
    /// action steps carrying the request's `expect` predicate on the final
    /// step. Any non-heist-valid message falls back to the direct path.
    func singleStepHeistPlan(for parsed: ParsedRequest) throws -> HeistPlan? {
        guard let messages = parsed.executableMessages, !messages.isEmpty else { return nil }

        if messages.count == 1, case .wait(let target) = messages[0] {
            return try HeistPlan(body: [.wait(WaitStep(predicate: target.predicate, timeout: target.resolvedTimeout))])
        }

        let expectationStep = parsed.expectationPayload.expectation.map {
            WaitStep(predicate: $0, timeout: min(parsed.expectationPayload.timeout ?? 10, 30))
        }

        var steps: [HeistStep] = []
        for (index, message) in messages.enumerated() {
            let actionCommand: HeistActionCommand
            do {
                actionCommand = try HeistActionCommand(clientMessage: message)
            } catch {
                // Not representable as a heist action (e.g. a pure read) —
                // use the direct path.
                return nil
            }
            // Any executable command runs through the one pipeline, including
            // viewport commands. Heist execution no longer enforces durability
            // (that is a recording/DSL concern), so a single command and a
            // composed heist share the same executor.
            let expectation = index == messages.count - 1 ? expectationStep : nil
            steps.append(.action(try ActionStep(command: actionCommand, expectation: expectation)))
        }
        return try HeistPlan(body: steps)
    }

    func executeSingleStepHeist(_ parsed: ParsedRequest, plan: HeistPlan) async throws -> FenceResponse {
        let response = try await runHeistPlan(plan, timeout: singleStepTimeout(for: parsed))
        if case .heistExecution(_, let result, _) = response {
            let step = result.steps.last
            recordHeistStep(parsed, actionResult: step?.dispatchedActionResult, expectation: step?.reportExpectation)
        }
        return response
    }

    private func singleStepTimeout(for parsed: ParsedRequest) -> TimeInterval {
        let messages = parsed.executableMessages ?? []
        let actionBudget: TimeInterval
        switch messages.first {
        case .wait(let target):
            return target.resolvedTimeout + config.postActionExpectationTimeoutBuffer
        case .typeText:
            actionBudget = Timeouts.longActionSeconds
        default:
            actionBudget = Timeouts.actionSeconds
        }
        guard parsed.expectationPayload.expectation != nil else { return actionBudget }
        let expectationTimeout = min(parsed.expectationPayload.timeout ?? 10, 30)
        return actionBudget + expectationTimeout + config.postActionExpectationTimeoutBuffer
    }

    private static func heistAccessibilityTrace(
        plan _: HeistPlan,
        result: HeistExecutionResult
    ) -> AccessibilityTrace? {
        // Don't emit a net trace if an action step ran without producing a
        // trace — a partial action trace would be misleading. Wait steps then
        // contribute their settled-state trace when available; `endpointTrace`
        // returns nil unless at least two distinct captures survive.
        let actionResults = result.dispatchedActionResults
        guard !actionResults.isEmpty,
              actionResults.allSatisfy({ $0.accessibilityTrace != nil })
        else { return nil }
        let traces = result.traceResultsInExecutionOrder.compactMap(\.accessibilityTrace)
        return AccessibilityTrace.endpointTrace(from: traces)
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
