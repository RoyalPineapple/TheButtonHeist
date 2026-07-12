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
        if let abortedAtPath = remoteResult.abortedAtPath {
            return .failed(
                steps: remoteResult.steps,
                durationMs: totalMs,
                abortedAtPath: abortedAtPath
            )
        } else {
            return .passed(
                steps: remoteResult.steps,
                durationMs: totalMs
            )
        }
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
              actionResults.allSatisfy({ $0.accessibilityTrace != nil && $0.settled != false })
        else { return nil }
        let traces = result.traceResultsInExecutionOrder.compactMap(\.accessibilityTrace)
        return AccessibilityTrace.combinedTrace(from: traces)
    }
}

extension TheFence {

    // MARK: - Heist Execution and Session State

    func handleRunHeist(_ request: RunHeistRequest) async throws -> FenceResponse {
        try await runHeistPlan(
            request.plan,
            argument: request.argument,
            timeout: Command.runHeist.descriptor.timeout.requiredFixedSeconds
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
        case .wait(_, let step):
            return try HeistPlan(body: [.wait(step)])
        case .actions(_, let actions, let expectationPayload):
            let expectationStep = expectationPayload.expectation.map {
                WaitStep(predicate: $0, timeout: min(expectationPayload.timeout ?? defaultActionExpectationTimeout, defaultWaitTimeout))
            }

            var steps: [HeistStep] = []
            let commands = actions.values
            for (index, command) in commands.enumerated() {
                let expectationPolicy: ActionExpectationPolicy
                if index == commands.count - 1, let expectationStep {
                    expectationPolicy = .expect(try ActionExpectation(expectationStep))
                } else {
                    expectationPolicy = .default
                }
                steps.append(.action(try ActionStep(command: command, expectationPolicy: expectationPolicy)))
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
        case .wait(_, let wait):
            return wait.timeout + config.postActionExpectationTimeoutBuffer
        case .actions(let command, _, let expectationPayload):
            actionBudget = command.descriptor.timeout.requiredSingleStepBaseSeconds
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
            let actionBudget = performActionTimeout(for: action.command)
            guard let expectation = action.expectationPolicy.expectedStep else { return actionBudget }
            return actionBudget + min(expectation.timeout, defaultWaitTimeout) + config.postActionExpectationTimeoutBuffer
        }
    }

    private func performActionTimeout(for action: HeistActionCommand) -> TimeInterval {
        performActionCommand(for: action).descriptor.timeout.requiredSingleStepBaseSeconds
    }

    private func performActionCommand(for action: HeistActionCommand) -> Command {
        switch action {
        case .typeText:
            return .typeText
        case .mechanicalTap:
            return .oneFingerTap
        case .mechanicalLongPress:
            return .longPress
        case .mechanicalSwipe:
            return .swipe
        case .mechanicalDrag:
            return .drag
        case .rotor:
            return .rotor
        case .editAction:
            return .editAction
        case .setPasteboard:
            return .setPasteboard
        case .dismissKeyboard:
            return .dismissKeyboard
        case .activate, .increment, .decrement, .customAction, .dismiss, .magicTap, .takeScreenshot,
             .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge:
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
        let connection = sessionConnectionSnapshot
        return SessionStatePayload(
            state: connection.state,
            actionTimeoutSeconds: Command.activate.descriptor.timeout.requiredSingleStepBaseSeconds,
            longActionTimeoutSeconds: Command.typeText.descriptor.timeout.requiredSingleStepBaseSeconds
        )
    }
}
