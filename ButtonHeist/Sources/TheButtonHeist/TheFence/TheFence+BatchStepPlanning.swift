import Foundation

import TheScore

extension TheFence {

    struct RunBatchPreparedStep {
        let originalIndex: Int
        let command: Command
        let typedStep: TheScore.BatchStep

        init(
            originalIndex: Int,
            command: Command,
            typedStep: TheScore.BatchStep
        ) {
            self.originalIndex = originalIndex
            self.command = command
            self.typedStep = typedStep
        }
    }

    struct BatchStepPlanBuildError: Error {
        let message: String
    }

    func batchPreparedStep(originalIndex: Int, request: ParsedRequest) throws -> RunBatchPreparedStep {
        let messages = try executableActionMessages(for: request)
        guard let message = messages.first, messages.count == 1 else {
            let commandName = request.command.rawValue
            throw BatchStepPlanBuildError(
                message: """
                run_batch step command "\(commandName)" expands to \(messages.count) actions; \
                express repeats as separate ordered steps
                """
            )
        }
        let typedStep = TheScore.BatchStep(
            command: message,
            expectation: batchExpectation(for: message, request: request),
            deadline: batchDeadline(for: message, request: request)
        )
        return RunBatchPreparedStep(
            originalIndex: originalIndex,
            command: request.command,
            typedStep: typedStep
        )
    }

}

private extension TheFence {

    func batchExpectation(for message: ClientMessage, request: ParsedRequest) -> ActionExpectation? {
        if let explicit = request.expectationPayload.expectation {
            return explicit
        }

        switch message {
        case .waitFor(let target):
            guard let matcher = target.elementTarget.batchExpectationMatcher else {
                return nil
            }
            return target.resolvedAbsent
                ? .elementDisappeared(matcher)
                : .elementAppeared(matcher)
        case .waitForChange(let target):
            return target.expect ?? .screenChanged
        default:
            return nil
        }
    }

    func batchDeadline(for message: ClientMessage, request: ParsedRequest) -> Deadline {
        if let timeout = request.expectationPayload.timeout {
            return Deadline(timeout: timeout)
        }

        switch message {
        case .waitFor(let target):
            return Deadline(timeout: target.resolvedTimeout)
        case .waitForChange(let target):
            return Deadline(timeout: target.resolvedTimeout)
        default:
            return Deadline()
        }
    }

}

private extension ElementTarget {
    var batchExpectationMatcher: ElementMatcher? {
        switch self {
        case .heistId:
            return nil
        case .matcher(let matcher, _):
            return matcher
        }
    }
}
