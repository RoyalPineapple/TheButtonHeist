import Foundation

import TheScore

extension TheFence {

    struct RunBatchRequest {
        let steps: [RunBatchPreparedStep]
        let policy: BatchExecutionPolicy
    }

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

    func decodeRunBatchRequest(_ arguments: CommandArgumentEnvelope) throws -> RunBatchRequest {
        try CommandArgumentEnvelopeLimits.validateRunBatch(arguments)
        let batchStepDecodeInputs = try arguments.requiredSchemaObjectArray("steps")
        guard !batchStepDecodeInputs.isEmpty else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count 0",
                expected: "array count 1...\(DecodeLimits.maxRunBatchSteps)"
            )
        }
        guard batchStepDecodeInputs.count <= DecodeLimits.maxRunBatchSteps else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count \(batchStepDecodeInputs.count)",
                expected: "array count 1...\(DecodeLimits.maxRunBatchSteps)"
            )
        }
        return RunBatchRequest(
            steps: try batchStepDecodeInputs.enumerated().map { index, stepDecodeInput in
                try decodeRunBatchStep(stepDecodeInput, index: index)
            },
            policy: try arguments.schemaEnum("policy", as: BatchExecutionPolicy.self) ?? .stopOnError
        )
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

    func decodeRunBatchStep(_ step: CommandArgumentEnvelope, index: Int) throws -> RunBatchPreparedStep {
        switch TheFence.Command.routeBatchStep(step) {
        case .success(let routed):
            return try decodeRunBatchStep(command: routed.command, arguments: routed.arguments, index: index)

        case .failure(let error):
            throw FenceError.invalidRequest("run_batch step \(index): \(error.message)")
        }
    }

    func decodeRunBatchStep(command: Command, arguments: CommandArgumentEnvelope, index: Int) throws -> RunBatchPreparedStep {
        do {
            let request = try parseRequest(command: command, arguments: arguments)
            return try batchPreparedStep(originalIndex: index, request: request)
        } catch let error as SchemaValidationError {
            throw FenceError.invalidRequest(error.message)
        } catch let error as MissingElementTarget {
            throw FenceError.invalidRequest(missingElementTargetResponse(command: error.command).humanFormatted())
        } catch let error as FenceError {
            throw error
        } catch let error as BatchStepPlanBuildError {
            throw FenceError.invalidRequest(error.message)
        } catch {
            throw FenceError.invalidRequest(error.localizedDescription)
        }
    }

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
