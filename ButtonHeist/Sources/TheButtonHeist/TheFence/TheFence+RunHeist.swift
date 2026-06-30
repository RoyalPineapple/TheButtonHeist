import Foundation

import ThePlans
import TheScore

extension TheFence {

    // MARK: - Heist Execution and Session State

    func handleRunHeist(_ request: RunHeistRequest) async throws -> FenceResponse {
        try await runHeistPlan(request.plan, argument: request.argument, timeout: Timeouts.longActionSeconds)
    }

    func handlePerform(_ request: PerformRequest) async throws -> FenceResponse {
        try await runHeistPlan(request.plan, timeout: performTimeout(for: request.step))
    }

    func handleListHeists(_ request: ListHeistsRequest) -> FenceResponse {
        .heistCatalog(request.catalog)
    }

    func handleDescribeHeist(_ request: DescribeHeistRequest) -> FenceResponse {
        .heistDescription(request.description)
    }

    /// Dispatch a `HeistPlan` to the device and project its execution into a
    /// `.heistExecution` response. Durable single commands and composed heists
    /// share this one path; transient commands use direct client dispatch.
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
        HeistReceiptRecorder.recordIfEnabled(result, plan: plan)
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
    /// interface/screen/session commands) or when it is a transient action that
    /// must use direct client dispatch.
    ///
    /// A `wait` command becomes a single wait step; UI action commands become
    /// action steps carrying the request's `expect` predicate on the final
    /// step. Any non-durable or otherwise non-heist-valid command falls back to
    /// the direct path.
    func singleStepHeistPlan(for parsed: ParsedRequest) throws -> HeistPlan? {
        guard let executable = parsed.executableRequest else { return nil }
        if case .wait(let step) = executable {
            return try HeistPlan(body: [.wait(step)])
        }
        guard case .actions(let actions) = executable else { return nil }

        let expectationStep = parsed.expectationPayload.expectation.map {
            WaitStep(predicate: $0, timeout: min(parsed.expectationPayload.timeout ?? defaultActionExpectationTimeout, defaultWaitTimeout))
        }

        var steps: [HeistStep] = []
        let commands = actions.values
        for (index, command) in commands.enumerated() {
            guard command.durableHeistActionFailure == nil else {
                return nil
            }
            let expectation = index == commands.count - 1 ? expectationStep : nil
            steps.append(.action(try ActionStep(command: command, expectation: expectation)))
        }
        return try HeistPlan(body: steps)
    }

    func executeSingleStepHeist(_ parsed: ParsedRequest, plan: HeistPlan) async throws -> FenceResponse {
        try await runHeistPlan(
            plan,
            timeout: singleStepTimeout(for: parsed)
        )
    }

    private func singleStepTimeout(for parsed: ParsedRequest) -> TimeInterval {
        guard let executable = parsed.executableRequest else {
            preconditionFailure("singleStepTimeout requires executable request dispatch")
        }
        let actionBudget: TimeInterval
        switch executable {
        case .wait(let wait):
            return wait.timeout + config.postActionExpectationTimeoutBuffer
        case .actions(let actions):
            switch actions.first {
            case .typeText:
                actionBudget = Timeouts.longActionSeconds
            default:
                actionBudget = Timeouts.actionSeconds
            }
        }
        guard parsed.expectationPayload.expectation != nil else {
            return max(actionBudget, explicitSingleActionTimeout(for: parsed) ?? actionBudget)
        }
        let expectationTimeout = min(parsed.expectationPayload.timeout ?? defaultActionExpectationTimeout, defaultWaitTimeout)
        return actionBudget + expectationTimeout + config.postActionExpectationTimeoutBuffer
    }

    private func explicitSingleActionTimeout(for parsed: ParsedRequest) -> TimeInterval? {
        parsed.expectationPayload.timeout.map { min($0, defaultWaitTimeout) }
    }

    private func performTimeout(for step: PerformableHeistStep) -> TimeInterval {
        switch step {
        case .wait(let wait):
            return wait.timeout + config.postActionExpectationTimeoutBuffer
        case .action(let action):
            let actionBudget: TimeInterval
            switch action.command {
            case .typeText:
                actionBudget = Timeouts.longActionSeconds
            default:
                actionBudget = Timeouts.actionSeconds
            }
            guard let expectation = action.expectation else { return actionBudget }
            return actionBudget + min(expectation.timeout, defaultWaitTimeout) + config.postActionExpectationTimeoutBuffer
        }
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
