import Foundation

extension TheFence {

    static func decodeRunBatchCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodeRunBatchRequest(arguments)
        return DecodedRequestDispatch { dispatchFence, _ in try await dispatchFence.handleRunBatch(request) }
    }

    static func decodeConnectCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodeConnectRequest(arguments)
        return DecodedRequestDispatch { dispatchFence, _ in try await dispatchFence.handleConnect(request) }
    }

    static func decodeStartHeistRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = StartHeistRequest(
            app: try arguments.schemaString("app") ?? "com.buttonheist.testapp",
            identifier: try arguments.schemaString("identifier") ?? "heist"
        )
        return DecodedRequestDispatch { fence, _ in try fence.handleStartHeist(request) }
    }

    static func decodeStopHeistRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = StopHeistRequest(
            outputPath: try arguments.requiredSchemaString("output")
        )
        return DecodedRequestDispatch { fence, _ in try fence.handleStopHeist(request) }
    }

    static func decodePlayHeistRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = PlayHeistRequest(
            inputPath: try arguments.requiredSchemaString("input")
        )
        return DecodedRequestDispatch { fence, _ in try await fence.handlePlayHeist(request) }
    }

    private func decodeConnectRequest(_ arguments: CommandArgumentEnvelope) throws -> ConnectRequest {
        ConnectRequest(
            targetName: try arguments.schemaString("target"),
            device: try arguments.schemaString("device"),
            token: try arguments.schemaString("token")
        )
    }

}
