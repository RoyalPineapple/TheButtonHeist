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
        let result: HeistExecutionResult
        if let abortedAtPath = executionResult.abortedAtPath {
            result = .failed(
                steps: executionResult.steps,
                durationMs: totalMs,
                abortedAtPath: abortedAtPath
            )
        } else {
            result = .passed(
                steps: executionResult.steps,
                durationMs: totalMs
            )
        }
        HeistReceiptRecorder.recordIfEnabled(result, plan: plan)
        let accessibilityTrace = Self.heistAccessibilityTrace(plan: plan, result: result)
        return .heistExecution(
            plan: plan,
            result: result,
            accessibilityTrace: accessibilityTrace
        )
    }

    // MARK: - Single-Step Execution

    /// Build the one-step `HeistPlan` for a request already classified as a
    /// durable heist dispatch.
    func singleStepHeistPlan(for request: SingleStepHeistRequest) throws -> HeistPlan {
        switch request {
        case .wait(let step):
            return try HeistPlan(body: [.wait(step)])
        case .actions(let actions, let expectationPayload):
            let expectationStep = expectationPayload.expectation.map {
                WaitStep(predicate: $0, timeout: min(expectationPayload.timeout ?? defaultActionExpectationTimeout, defaultWaitTimeout))
            }

            var steps: [HeistStep] = []
            let commands = actions.values
            for (index, command) in commands.enumerated() {
                let expectation = index == commands.count - 1 ? expectationStep : nil
                steps.append(.action(try ActionStep(command: command, expectation: expectation)))
            }
            return try HeistPlan(body: steps)
        }
    }

    func executeSingleStepHeist(_ request: SingleStepHeistRequest) async throws -> FenceResponse {
        try await runHeistPlan(
            singleStepHeistPlan(for: request),
            timeout: singleStepTimeout(for: request)
        )
    }

    private func singleStepTimeout(for request: SingleStepHeistRequest) -> TimeInterval {
        let actionBudget: TimeInterval
        switch request {
        case .wait(let wait):
            return wait.timeout + config.postActionExpectationTimeoutBuffer
        case .actions(let actions, let expectationPayload):
            switch actions.first {
            case .typeText:
                actionBudget = Timeouts.longActionSeconds
            default:
                actionBudget = Timeouts.actionSeconds
            }
            guard expectationPayload.expectation != nil else {
                return max(actionBudget, expectationPayload.timeout.map { min($0, defaultWaitTimeout) } ?? actionBudget)
            }
            let expectationTimeout = min(expectationPayload.timeout ?? defaultActionExpectationTimeout, defaultWaitTimeout)
            return actionBudget + expectationTimeout + config.postActionExpectationTimeoutBuffer
        }
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
            state: connection.state,
            actionTimeoutSeconds: Timeouts.actionSeconds,
            longActionTimeoutSeconds: Timeouts.longActionSeconds
        )
    }
}
