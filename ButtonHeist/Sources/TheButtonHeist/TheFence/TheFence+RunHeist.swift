import Foundation

import ThePlans
import TheScore

struct HeistRunProjection {
    enum Effect: Sendable, Equatable {
        case recordReceipt(result: HeistExecutionResult, plan: HeistPlan)
    }

    let projectedResult: HeistExecutionResult
    let response: FenceResponse
    let effects: [Effect]

    init(
        plan: HeistPlan,
        remoteResult: HeistExecutionResult,
        totalMs: Int
    ) {
        let result = Self.project(remoteResult: remoteResult, totalMs: totalMs)
        projectedResult = result
        response = .heistExecution(
            plan: plan,
            result: result,
            accessibilityTrace: Self.heistAccessibilityTrace(result: result)
        )
        effects = [.recordReceipt(result: result, plan: plan)]
    }

    private static func project(
        remoteResult: HeistExecutionResult,
        totalMs: Int
    ) -> HeistExecutionResult {
        HeistExecutionResult(steps: remoteResult.steps, durationMs: totalMs)
    }

    private static func heistAccessibilityTrace(
        result: HeistExecutionResult
    ) -> AccessibilityTrace? {
        // Don't emit a net trace if an action step ran without producing a
        // trace — a partial action trace would be misleading. Wait steps then
        // contribute their settled-state trace when available; `combinedTrace`
        // returns nil unless at least two distinct captures survive.
        let actionResults = result.dispatchedActionResults
        guard !actionResults.isEmpty,
              actionResults.allSatisfy({ $0.traceEvidence?.isComplete == true })
        else { return nil }
        let traceResults = result.traceResultsInExecutionOrder
        guard traceResults.allSatisfy({ $0.traceEvidence?.isComplete == true }) else { return nil }
        let traces = traceResults.compactMap(\.accessibilityTrace)
        return AccessibilityTrace.combinedTrace(from: traces)
    }
}

extension TheFence {

    // MARK: - Heist Execution and Session State

    func handleRunHeist(_ request: RunHeistRequest, timeout: TimeInterval) async throws -> FenceResponse {
        try await runHeistPlan(
            request.plan,
            argument: request.argument,
            timeout: timeout
        )
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

        let projection = HeistRunProjection(
            plan: plan,
            remoteResult: executionResult,
            totalMs: totalMs
        )
        interpret(projection.effects)
        return projection.response
    }

    // MARK: - Single-Step Execution

    /// Build the one-step `HeistPlan` for a request already classified as a
    /// durable heist dispatch.
    func singleStepHeistPlan(for request: SingleStepHeistRequest) throws -> HeistPlan {
        switch request {
        case .wait(let step):
            return try HeistPlan(body: [.wait(step)])
        case .action(let action, let expectationPayload, _):
            let expectationStep = expectationPayload.expectation.map {
                WaitStep(
                    predicate: $0,
                    timeout: expectationPayload.timeout ?? defaultActionExpectationTimeout
                )
            }

            let expectationPolicy: ActionExpectationPolicy = try expectationStep.map {
                .expect(try ActionExpectation($0))
            } ?? .default
            return try HeistPlan(body: [
                .action(ActionStep(command: action.action, expectationPolicy: expectationPolicy))
            ])
        }
    }

    func executeSingleStepHeist(_ request: SingleStepHeistRequest) async throws -> FenceResponse {
        try await runHeistPlan(
            singleStepHeistPlan(for: request),
            timeout: singleStepTimeout(for: request)
        )
    }

    private func singleStepTimeout(for request: SingleStepHeistRequest) -> TimeInterval {
        switch request {
        case .wait(let wait):
            return wait.timeout.seconds + config.postActionExpectationTimeoutBuffer
        case .action(_, let expectationPayload, let actionBudget):
            guard expectationPayload.expectation != nil else {
                return max(
                    actionBudget,
                    expectationPayload.timeout?.seconds ?? actionBudget
                )
            }
            let expectationTimeout = expectationPayload.timeout ?? defaultActionExpectationTimeout
            return actionBudget + expectationTimeout.seconds + config.postActionExpectationTimeoutBuffer
        }
    }

    private func performTimeout(for step: PerformableHeistStep) -> TimeInterval {
        switch step {
        case .wait(let wait):
            return wait.timeout.seconds + config.postActionExpectationTimeoutBuffer
        case .action(let action):
            let actionBudget = performActionTimeout(for: action.command)
            guard let expectation = action.expectationPolicy.expectedStep else { return actionBudget }
            return actionBudget
                + expectation.timeout.seconds
                + config.postActionExpectationTimeoutBuffer
        }
    }

    private func performActionTimeout(for action: HeistActionCommand) -> TimeInterval {
        guard let timeout = performActionCommand(for: action).descriptor.timeout.singleStepBaseSeconds else {
            preconditionFailure("Perform action command must carry single-step action timeout policy")
        }
        return timeout
    }

    private func performActionCommand(for action: HeistActionCommand) -> Command {
        switch action.wireType {
        case .typeText:
            return .typeText
        case .oneFingerTap:
            return .oneFingerTap
        case .longPress:
            return .longPress
        case .swipe:
            return .swipe
        case .drag:
            return .drag
        case .rotor:
            return .rotor
        case .editAction:
            return .editAction
        case .setPasteboard:
            return .setPasteboard
        case .resignFirstResponder:
            return .dismissKeyboard
        case .activate, .increment, .decrement, .performCustomAction, .dismiss, .magicTap, .takeScreenshot,
             .scroll, .scrollToVisible, .scrollToEdge:
            return .activate
        }
    }

    private func interpret(_ effects: [HeistRunProjection.Effect]) {
        for effect in effects {
            interpret(effect)
        }
    }

    private func interpret(_ effect: HeistRunProjection.Effect) {
        switch effect {
        case .recordReceipt(let result, let plan):
            HeistReceiptRecorder.recordIfEnabled(result, plan: plan)
        }
    }

    // MARK: - Session State

    func currentSessionState() -> SessionStatePayload {
        return SessionStatePayload(
            state: sessionConnectionState,
            actionTimeoutSeconds: FenceCommandFixedTimeout.standardAction.seconds,
            longActionTimeoutSeconds: FenceCommandFixedTimeout.longAction.seconds
        )
    }
}
