import Foundation

extension TheFence {

    func decodeSessionPayload(
        command: Command,
        request: [String: Any]
    ) throws -> RequestPayload {
        switch command {
        case .startRecording:
            return .startRecording(try decodeRecordingConfig(request))
        case .runBatch:
            return .runBatch(try decodeRunBatchRequest(request))
        case .connect:
            return .connect(try decodeConnectRequest(request))
        case .archiveSession:
            return .archiveSession(ArchiveSessionRequest(
                deleteSource: try request.schemaBoolean("delete_source") ?? false
            ))
        case .startHeist:
            return .startHeist(StartHeistRequest(
                app: try request.schemaString("app") ?? "com.buttonheist.testapp",
                identifier: try request.schemaString("identifier") ?? "heist"
            ))
        case .stopHeist:
            return .stopHeist(StopHeistRequest(
                outputPath: try request.requiredSchemaString("output")
            ))
        case .playHeist:
            return .playHeist(PlayHeistRequest(
                inputPath: try request.requiredSchemaString("input")
            ))
        default:
            throw FenceError.invalidRequest("Unexpected session command: \(command.rawValue)")
        }
    }

    private func decodeRecordingConfig(_ request: [String: Any]) throws -> RecordingConfig {
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

    private func decodeRunBatchRequest(_ request: [String: Any]) throws -> RunBatchRequest {
        try Self.validateJSONEnvelope(
            request,
            field: "run_batch",
            maxBytes: DecodeLimits.maxRunBatchRequestBytes,
            maxDepth: DecodeLimits.maxRunBatchNestingDepth
        )
        let rawSteps = try request.requiredSchemaDictionaryArray("steps")
        guard !rawSteps.isEmpty else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count 0",
                expected: "array count 1...\(DecodeLimits.maxRunBatchSteps)"
            )
        }
        guard rawSteps.count <= DecodeLimits.maxRunBatchSteps else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count \(rawSteps.count)",
                expected: "array count 1...\(DecodeLimits.maxRunBatchSteps)"
            )
        }
        return RunBatchRequest(
            steps: rawSteps.enumerated().map { index, step in
                decodeRunBatchStep(step, index: index)
            },
            policy: try request.schemaEnum("policy", as: BatchPolicy.self) ?? .stopOnError
        )
    }

    private func decodeConnectRequest(_ request: [String: Any]) throws -> ConnectRequest {
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
            if let failure = batchBoundedResponseFailure(operation: operation, index: index) {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: failure
                )
            }
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
                    message: fenceError.coreMessage,
                    details: fenceError.failureDetails,
                    includeDetailsInResult: false
                )
            )
        }
    }

    private func batchBoundedResponseFailure(
        operation: NormalizedOperation,
        index: Int
    ) -> BatchStepDecodeFailure? {
        guard operation.command == .getScreen,
              operation.arguments["inlineData"] as? Bool == true
        else { return nil }

        let error = SchemaValidationError(
            field: "steps[\(index)].inlineData",
            observed: true,
            expected: "not allowed for get_screen inside run_batch; omit inlineData or call get_screen outside run_batch"
        )
        return BatchStepDecodeFailure(
            message: error.message,
            details: nil,
            includeDetailsInResult: true
        )
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

private extension TheFence {

    static func validateJSONEnvelope(
        _ value: Any,
        field: String,
        maxBytes: Int,
        maxDepth: Int
    ) throws {
        let byteCount = try jsonEncodedSize(
            of: value,
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
        of value: Any,
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

        if let dictionary = value as? [String: Any] {
            var size = 2
            for (index, entry) in dictionary.enumerated() {
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

        if let array = value as? [Any] {
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
        }

        if let string = value as? String {
            return try bounded(jsonStringEncodedSize(string))
        }

        if let bool = value as? Bool {
            return bool ? 4 : 5
        }

        if value is NSNull {
            return 4
        }

        if let number = value as? NSNumber {
            guard number.doubleValue.isFinite else {
                throw SchemaValidationError(field: field, observed: number, expected: "finite JSON number")
            }
            return try bounded(String(describing: number).utf8.count)
        }

        throw SchemaValidationError(field: field, observed: value, expected: "JSON value")
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
