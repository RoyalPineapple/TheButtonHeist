import Foundation

extension TheFence {

    func decodeRecordingConfig(_ request: [String: Any]) throws -> RecordingConfig {
        let fps = try request.schemaInteger("fps")
        if let fps, fps < 1 || fps > 15 {
            throw SchemaValidationError(field: "fps", observed: fps, expected: "integer in 1...15")
        }
        let scale = try request.schemaNumber("scale")
        if let scale, scale < 0.25 || scale > 1.0 {
            throw SchemaValidationError(field: "scale", observed: scale, expected: "number in 0.25...1.0")
        }
        return RecordingConfig(
            fps: fps,
            scale: scale,
            inactivityTimeout: try request.schemaNumber("inactivity_timeout"),
            maxDuration: try request.schemaNumber("max_duration")
        )
    }

    func decodeRunBatchRequest(_ request: [String: Any]) throws -> RunBatchRequest {
        let rawSteps = try request.requiredSchemaDictionaryArray("steps")
        guard !rawSteps.isEmpty else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count 0",
                expected: "array count >= 1"
            )
        }
        return RunBatchRequest(
            steps: rawSteps.enumerated().map { index, step in
                decodeRunBatchStep(step, index: index)
            },
            policy: try request.schemaEnum("policy", as: BatchPolicy.self) ?? .stopOnError
        )
    }

    func decodeConnectRequest(_ request: [String: Any]) throws -> ConnectRequest {
        ConnectRequest(
            targetName: try request.schemaString("target"),
            device: try request.schemaString("device"),
            token: try request.schemaString("token")
        )
    }

    private func decodeRunBatchStep(_ step: [String: Any], index: Int) -> RunBatchStepRequest {
        let originalCommandName = step["command"] as? String ?? "?"
        switch FenceOperationCatalog.normalizeBatchStep(step) {
        case .success(let operation):
            do {
                return .decoded(try parseRequest(
                    command: operation.command,
                    request: operation.requestDictionary
                ))
            } catch let error as SchemaValidationError {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: BatchStepDecodeFailure(
                        message: error.message,
                        details: nil,
                        includeDetailsInResult: true
                    )
                )
            } catch let error as MissingElementTarget {
                let response = missingElementTargetResponse(command: error.command)
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: batchStepFailure(from: response)
                )
            } catch let error as FenceError {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: BatchStepDecodeFailure(
                        message: error.coreMessage,
                        details: error.failureDetails,
                        includeDetailsInResult: true
                    )
                )
            } catch {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: BatchStepDecodeFailure(
                        message: error.localizedDescription,
                        details: nil,
                        includeDetailsInResult: false
                    )
                )
            }

        case .failure(let error):
            let fenceError = FenceError.invalidRequest("run_batch step \(index): \(error.message)")
            return .invalid(
                commandName: originalCommandName,
                failure: BatchStepDecodeFailure(
                    message: fenceError.localizedDescription,
                    details: fenceError.failureDetails,
                    includeDetailsInResult: false
                )
            )
        }
    }

    private func batchStepFailure(from response: FenceResponse) -> BatchStepDecodeFailure {
        guard case .error(let message, let details) = response else {
            return BatchStepDecodeFailure(
                message: response.humanFormatted(),
                details: nil,
                includeDetailsInResult: false
            )
        }
        return BatchStepDecodeFailure(
            message: message,
            details: details,
            includeDetailsInResult: true
        )
    }
}
