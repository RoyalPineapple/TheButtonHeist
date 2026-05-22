import Foundation

import TheScore

extension TheFence {

    struct BatchStepActionPlan {
        let action: TheScore.Action
        let expectation: ActionExpectation?
        let timeout: Double?

        init(
            action: TheScore.Action,
            expectation: ActionExpectation? = nil,
            timeout: Double? = nil
        ) {
            self.action = action
            self.expectation = expectation
            self.timeout = timeout
        }
    }

    struct BatchStepPlanningContext {
        let originalIndex: Int
        let operation: NormalizedOperation
        let request: ParsedRequest
        let expectation: ActionExpectation?
        let timeout: Double?

        init(originalIndex: Int, operation: NormalizedOperation, request: ParsedRequest) {
            self.originalIndex = originalIndex
            self.operation = operation
            self.request = request
            expectation = request.expectationPayload.expectation
            timeout = request.expectationPayload.timeout
        }

        func plan(_ actionPlan: BatchStepActionPlan) -> RunBatchPreparedStep {
            let stepTimeout = actionPlan.timeout ?? timeout
            return RunBatchPreparedStep(
                originalIndex: originalIndex,
                commandName: request.command.rawValue,
                action: actionPlan.action,
                expectation: actionPlan.expectation ?? expectation ?? actionPlan.action.defaultExpectation,
                deadline: deadline(for: actionPlan.action, timeout: stepTimeout)
            )
        }

        private func deadline(for action: TheScore.Action, timeout: Double?) -> TheScore.Deadline {
            timeout.map(TheScore.Deadline.init(timeout:)) ?? action.defaultDeadline
        }
    }
}
