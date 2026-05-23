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
        let request: ParsedRequest
        let expectation: ActionExpectation?
        let timeout: Double?

        init(originalIndex: Int, request: ParsedRequest) {
            self.originalIndex = originalIndex
            self.request = request
            expectation = request.expectationPayload.expectation
            timeout = request.expectationPayload.timeout
        }

        func plan(_ actionPlan: BatchStepActionPlan) -> RunBatchPreparedStep {
            let stepTimeout = actionPlan.timeout ?? timeout
            let typedStep = TheScore.BatchStep.action(
                actionPlan.action,
                expect: actionPlan.expectation ?? expectation,
                deadline: stepTimeout.map(TheScore.Deadline.init(timeout:))
            )
            return RunBatchPreparedStep(
                originalIndex: originalIndex,
                commandName: request.command.rawValue,
                action: typedStep.action,
                expectation: typedStep.expectation,
                deadline: typedStep.deadline
            )
        }
    }
}
