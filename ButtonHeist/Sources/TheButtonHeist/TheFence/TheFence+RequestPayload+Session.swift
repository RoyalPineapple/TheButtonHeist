import Foundation

extension TheFence {

    func decodeSessionPayload(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws -> RequestPayload {
        switch command {
        case .startRecording:
            return .startRecording(try decodeRecordingConfig(arguments))
        case .runBatch:
            let request = arguments.decodeEdgeRawDictionary()
            return .runBatch(try decodeRunBatchRequest(request))
        case .connect:
            return .connect(try decodeConnectRequest(arguments))
        case .archiveSession:
            return .archiveSession(ArchiveSessionRequest(
                deleteSource: try arguments.schemaBoolean("delete_source") ?? false
            ))
        case .startHeist:
            return .startHeist(StartHeistRequest(
                app: try arguments.schemaString("app") ?? "com.buttonheist.testapp",
                identifier: try arguments.schemaString("identifier") ?? "heist"
            ))
        case .stopHeist:
            return .stopHeist(StopHeistRequest(
                outputPath: try arguments.requiredSchemaString("output")
            ))
        case .playHeist:
            return .playHeist(PlayHeistRequest(
                inputPath: try arguments.requiredSchemaString("input")
            ))
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
