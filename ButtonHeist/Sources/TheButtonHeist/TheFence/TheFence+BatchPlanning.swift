import Foundation

import TheScore

extension TheFence {

    struct BatchStepPlanBuildError: Error {
        let message: String
    }

    func decodeRunBatchRequest(_ arguments: CommandArgumentEnvelope) throws -> RunBatchRequest {
        try Self.validateJSONEnvelope(
            arguments,
            field: "run_batch",
            maxBytes: DecodeLimits.maxRunBatchRequestBytes,
            maxDepth: DecodeLimits.maxRunBatchNestingDepth
        )
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
            steps: batchStepDecodeInputs.enumerated().map { index, stepDecodeInput in
                decodeRunBatchStep(stepDecodeInput, index: index)
            },
            policy: try arguments.schemaEnum("policy", as: BatchPolicy.self) ?? .stopOnError
        )
    }
}

private extension TheFence {

    func decodeRunBatchStep(_ step: CommandArgumentObject, index: Int) -> RunBatchStep {
        switch FenceOperationCatalog.normalizeBatchStep(step) {
        case .success(let operation):
            return decodeRunBatchStep(operation: operation, index: index)

        case .failure(let error):
            let fenceError = FenceError.invalidRequest("run_batch step \(index): \(error.message)")
            return .invalid(
                commandName: diagnosticCommandName(forBatchStep: step),
                failure: BatchStepFailure(
                    message: fenceError.coreMessage,
                    details: fenceError.failureDetails,
                    includeDetailsInResult: false
                )
            )
        }
    }

    func decodeRunBatchStep(operation: NormalizedOperation, index: Int) -> RunBatchStep {
        do {
            let request = try parseRequest(operation: operation)
            return .planned(try batchPreparedStep(originalIndex: index, request: request))
        } catch let error as SchemaValidationError {
            return invalidBatchStep(operation, message: error.message, includeDetailsInResult: true)
        } catch let error as MissingElementTarget {
            return .invalid(
                commandName: operation.command.rawValue,
                failure: batchStepFailure(from: missingElementTargetResponse(command: error.command))
            )
        } catch let error as FenceError {
            return .invalid(
                commandName: operation.command.rawValue,
                failure: BatchStepFailure(
                    message: error.coreMessage,
                    details: error.failureDetails,
                    includeDetailsInResult: true
                )
            )
        } catch let error as BatchStepPlanBuildError {
            return invalidBatchStep(operation, message: error.message)
        } catch {
            return invalidBatchStep(operation, message: error.localizedDescription)
        }
    }

    func batchPreparedStep(originalIndex: Int, request: ParsedRequest) throws -> RunBatchPreparedStep {
        let executionPlan = try clientMessageExecutionPlan(for: request)
        guard let message = executionPlan.messages.first, executionPlan.messages.count == 1 else {
            let commandName = executionPlan.messages.first?.canonicalName ?? request.command.rawValue
            throw BatchStepPlanBuildError(
                message: """
                run_batch step command "\(commandName)" expands to \(executionPlan.messages.count) actions; \
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
            commandName: request.command.rawValue,
            typedStep: typedStep
        )
    }

    func batchExpectation(for message: ClientMessage, request: ParsedRequest) -> ActionExpectation {
        if let explicit = request.expectationPayload.expectation {
            return explicit
        }

        switch message {
        case .waitFor(let target):
            return target.resolvedAbsent
                ? .elementDisappeared(target.elementTarget.batchExpectationMatcher)
                : .elementAppeared(target.elementTarget.batchExpectationMatcher)
        case .waitForChange(let target):
            return target.expect ?? .screenChanged
        default:
            return .delivery
        }
    }

    func batchDeadline(for message: ClientMessage, request: ParsedRequest) -> Deadline {
        if let timeout = request.expectationPayload.timeout {
            return Deadline(timeout: timeout)
        }

        switch message {
        case .waitForIdle(let target):
            return Deadline(timeout: target.timeout ?? 5)
        case .waitFor(let target):
            return Deadline(timeout: target.resolvedTimeout)
        case .waitForChange(let target):
            return Deadline(timeout: target.resolvedTimeout)
        default:
            return Deadline()
        }
    }

    func invalidBatchStep(
        _ operation: NormalizedOperation,
        message: String,
        includeDetailsInResult: Bool = false
    ) -> RunBatchStep {
        .invalid(
            commandName: operation.command.rawValue,
            failure: BatchStepFailure(
                message: message,
                details: nil,
                includeDetailsInResult: includeDetailsInResult
            )
        )
    }

    func batchStepFailure(from response: FenceResponse) -> BatchStepFailure {
        guard case .error(let message, let details) = response else {
            return BatchStepFailure(
                message: response.humanFormatted(),
                details: nil,
                includeDetailsInResult: false
            )
        }
        return BatchStepFailure(
            message: message,
            details: details,
            includeDetailsInResult: true
        )
    }

    func diagnosticCommandName(forBatchStep step: some CommandArgumentReadable) -> String {
        do {
            guard let commandName = try step.schemaString("command") else {
                return "?"
            }
            return commandName
        } catch {
            return "?"
        }
    }

    static func validateJSONEnvelope(
        _ arguments: some CommandArgumentReadable,
        field: String,
        maxBytes: Int,
        maxDepth: Int
    ) throws {
        let byteCount = try jsonEncodedSize(
            of: arguments.argumentValues,
            field: field,
            maxBytes: maxBytes,
            maxDepth: maxDepth
        )
        guard byteCount <= maxBytes else {
            throw SchemaValidationError(
                field: field,
                observed: "\(byteCount) bytes",
                expected: "JSON request <= \(maxBytes) bytes"
            )
        }
    }

    static func jsonEncodedSize(
        of object: [String: CommandArgumentValue],
        field: String,
        maxBytes: Int,
        maxDepth: Int,
        depth: Int = 1
    ) throws -> Int {
        guard depth <= maxDepth else {
            throw SchemaValidationError(
                field: field,
                observed: "nesting depth \(depth)",
                expected: "nesting depth <= \(maxDepth)"
            )
        }

        func bounded(_ size: Int) throws -> Int {
            guard size <= maxBytes else {
                throw SchemaValidationError(
                    field: field,
                    observed: "\(size) bytes",
                    expected: "JSON request <= \(maxBytes) bytes"
                )
            }
            return size
        }

        var size = 2
        for (index, entry) in object.enumerated() {
            if index > 0 { size = try bounded(size + 1) }
            size = try bounded(size + jsonStringEncodedSize(entry.key) + 1)
            let valueSize = try jsonEncodedSize(
                of: entry.value,
                field: field,
                maxBytes: maxBytes,
                maxDepth: maxDepth,
                depth: depth + 1
            )
            size = try bounded(size + valueSize)
        }
        return size
    }

    static func jsonEncodedSize(
        of value: CommandArgumentValue,
        field: String,
        maxBytes: Int,
        maxDepth: Int,
        depth: Int
    ) throws -> Int {
        guard depth <= maxDepth else {
            throw SchemaValidationError(
                field: field,
                observed: "nesting depth \(depth)",
                expected: "nesting depth <= \(maxDepth)"
            )
        }

        func bounded(_ size: Int) throws -> Int {
            guard size <= maxBytes else {
                throw SchemaValidationError(
                    field: field,
                    observed: "\(size) bytes",
                    expected: "JSON request <= \(maxBytes) bytes"
                )
            }
            return size
        }

        switch value {
        case .object(let object):
            return try jsonEncodedSize(
                of: object,
                field: field,
                maxBytes: maxBytes,
                maxDepth: maxDepth,
                depth: depth
            )

        case .array(let array):
            var size = 2
            for (index, item) in array.enumerated() {
                if index > 0 { size = try bounded(size + 1) }
                let itemSize = try jsonEncodedSize(
                    of: item,
                    field: field,
                    maxBytes: maxBytes,
                    maxDepth: maxDepth,
                    depth: depth + 1
                )
                size = try bounded(size + itemSize)
            }
            return size

        case .string(let string):
            return try bounded(jsonStringEncodedSize(string))

        case .bool(let bool):
            return bool ? 4 : 5

        case .null:
            return 4

        case .int(let number):
            return try bounded(String(number).utf8.count)

        case .double(let number):
            guard number.isFinite else {
                throw SchemaValidationError(field: field, observed: number, expected: "finite JSON number")
            }
            return try bounded(String(number).utf8.count)
        }
    }

    static func jsonStringEncodedSize(_ value: String) -> Int {
        var size = 2
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22, 0x5C:
                size += 2
            case 0x00...0x1F:
                size += 6
            default:
                size += scalar.utf8.count
            }
        }
        return size
    }

}

private extension ElementTarget {
    var batchExpectationMatcher: ElementMatcher {
        switch self {
        case .heistId(let heistId):
            return ElementMatcher(heistId: heistId)
        case .matcher(let matcher, _):
            return matcher
        }
    }
}
