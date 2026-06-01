import Foundation

import TheScore

extension TheFence {

    func decodeRunBatchRequest(_ arguments: CommandArgumentEnvelope) throws -> RunBatchRequest {
        try CommandArgumentEnvelopeLimits.validate(
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
            steps: try batchStepDecodeInputs.enumerated().map { index, stepDecodeInput in
                try decodeRunBatchStep(stepDecodeInput, index: index)
            },
            policy: try arguments.schemaEnum("policy", as: BatchExecutionPolicy.self) ?? .stopOnError
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

}
