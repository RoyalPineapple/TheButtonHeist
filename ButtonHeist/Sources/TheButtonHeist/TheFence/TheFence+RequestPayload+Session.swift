import Foundation

extension TheFence {

    func decodeSessionDispatch(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .runBatch:
            let request = try decodeRunBatchRequest(arguments)
            return DecodedRequestDispatch { fence, _ in try await fence.handleRunBatch(request) }
        case .connect:
            let request = try decodeConnectRequest(arguments)
            return DecodedRequestDispatch { fence, _ in try await fence.handleConnect(request) }
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

    private func decodeConnectRequest(_ arguments: CommandArgumentEnvelope) throws -> ConnectRequest {
        ConnectRequest(
            targetName: try arguments.schemaString("target"),
            device: try arguments.schemaString("device"),
            token: try arguments.schemaString("token")
        )
    }

}
