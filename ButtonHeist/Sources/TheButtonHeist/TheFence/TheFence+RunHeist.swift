import Foundation

import ThePlans
import TheScore

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
        let result = try await sendAndAwaitHeistExecution(
            plan,
            argument: argument,
            timeout: timeout
        )
        HeistResultRecording.recordIfEnabled(result, plan: plan)
        return .heistExecution(
            plan: plan,
            report: HeistReport.project(result: result)
        )
    }

    // MARK: - Single-Step Execution

    /// Project an admitted single-step execution onto the canonical plan runtime.
    func singleStepHeistPlan(for execution: SingleStepHeistExecution) throws -> HeistPlan {
        switch execution {
        case .wait(let step):
            return try HeistPlan(version: HeistPlan.currentVersion, body: [.wait(step)])
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
            return try HeistPlan(version: HeistPlan.currentVersion, body: [
                .action(ActionStep(command: action.action, expectationPolicy: expectationPolicy))
            ])
        }
    }

    func executeSingleStepHeist(_ execution: SingleStepHeistExecution) async throws -> FenceResponse {
        try await runHeistPlan(
            singleStepHeistPlan(for: execution),
            timeout: singleStepTimeout(for: execution)
        )
    }

    private func singleStepTimeout(for execution: SingleStepHeistExecution) -> TimeInterval {
        switch execution {
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
        case .dismissKeyboard:
            return .dismissKeyboard
        case .activate, .increment, .decrement, .performCustomAction, .dismiss, .magicTap, .takeScreenshot,
             .scroll, .scrollToVisible, .scrollToEdge:
            return .activate
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
