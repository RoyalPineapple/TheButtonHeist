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

    private func decodeConnectRequest(_ request: [String: Any]) throws -> ConnectRequest {
        ConnectRequest(
            targetName: try request.schemaString("target"),
            device: try request.schemaString("device"),
            token: try request.schemaString("token")
        )
    }

}
