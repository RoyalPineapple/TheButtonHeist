import Foundation

extension TheFence {

    func decodeSessionDispatch(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .startRecording:
            let config = try decodeRecordingConfig(arguments)
            return DecodedRequestDispatch { fence, _ in try await fence.handleStartRecording(config) }
        case .runBatch:
            let request = try decodeRunBatchRequest(arguments)
            return DecodedRequestDispatch { fence, _ in try await fence.handleRunBatch(request) }
        case .connect:
            let request = try decodeConnectRequest(arguments)
            return DecodedRequestDispatch { fence, _ in try await fence.handleConnect(request) }
        case .archiveSession:
            let request = ArchiveSessionRequest(
                deleteSource: try arguments.schemaBoolean("delete_source") ?? false
            )
            return DecodedRequestDispatch { fence, _ in try await fence.handleArchiveSession(request) }
        case .startHeist:
            let request = StartHeistRequest(
                app: try arguments.schemaString("app") ?? "com.buttonheist.testapp",
                identifier: try arguments.schemaString("identifier") ?? "heist"
            )
            return DecodedRequestDispatch { fence, _ in try fence.handleStartHeist(request) }
        case .stopHeist:
            let request = StopHeistRequest(
                outputPath: try arguments.requiredSchemaString("output")
            )
            return DecodedRequestDispatch { fence, _ in try fence.handleStopHeist(request) }
        case .playHeist:
            let request = PlayHeistRequest(
                inputPath: try arguments.requiredSchemaString("input")
            )
            return DecodedRequestDispatch { fence, _ in try await fence.handlePlayHeist(request) }
        default:
            throw FenceError.invalidRequest("Unexpected session command: \(command.rawValue)")
        }
    }

    private func decodeRecordingConfig(_ arguments: CommandArgumentEnvelope) throws -> RecordingConfig {
        let fps = try arguments.schemaInteger("fps")
        if let fps, fps < 1 || fps > 15 {
            throw SchemaValidationError(field: "fps", observed: fps, expected: "integer in 1...15")
        }
        let scale = try arguments.schemaNumber("scale")
        if let scale, scale < 0.25 || scale > 1.0 {
            throw SchemaValidationError(field: "scale", observed: scale, expected: "number in 0.25...1.0")
        }
        return RecordingConfig(
            fps: fps,
            scale: scale,
            inactivityTimeout: try arguments.schemaNumber("inactivity_timeout"),
            maxDuration: try arguments.schemaNumber("max_duration")
        )
    }

    private func decodeConnectRequest(_ arguments: CommandArgumentEnvelope) throws -> ConnectRequest {
        ConnectRequest(
            targetName: try arguments.schemaString("target"),
            device: try arguments.schemaString("device"),
            token: try arguments.schemaString("token")
        )
    }

}
