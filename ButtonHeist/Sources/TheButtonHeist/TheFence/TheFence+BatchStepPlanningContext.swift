import Foundation

import TheScore

extension TheFence {

    struct BatchStepActionPlan {
        let command: ClientMessage
        let expectation: ActionExpectation?
        let timeout: Double?

        init(
            command: ClientMessage,
            expectation: ActionExpectation? = nil,
            timeout: Double? = nil
        ) {
            self.command = command
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
            let typedStep = TheScore.BatchStep.command(
                actionPlan.command,
                expect: actionPlan.expectation ?? expectation,
                deadline: stepTimeout.map(TheScore.Deadline.init(timeout:))
            )
            return RunBatchPreparedStep(
                originalIndex: originalIndex,
                commandName: request.command.rawValue,
                command: typedStep.command,
                expectation: typedStep.expectation,
                deadline: typedStep.deadline
            )
        }
    }
}
