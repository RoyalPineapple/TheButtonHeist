import Foundation

extension TheFence {

    struct ConnectRequest {
        let targetName: String?
        let device: String?
        let token: String?
    }

    struct StartHeistRequest {
        let app: String
        let identifier: String
    }

    struct StopHeistRequest {
        let outputPath: String
        let swiftOutputPath: String?
        let sampleRewrite: RecordedHeistSwiftExport.SampleRewrite?
    }

    static func decodePingRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence, _ in try await fence.handlePing() }
    }

    static func decodeListDevicesRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence, _ in try await fence.handleListDevices() }
    }

    static func decodeGetSessionStateRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence, _ in .sessionState(payload: fence.currentSessionState()) }
    }

    static func decodeListTargetsRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence, _ in fence.handleListTargets() }
    }

    static func decodeRunHeistCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodeRunHeistRequest(arguments)
        return DecodedRequestDispatch { dispatchFence, _ in try await dispatchFence.handleRunHeist(request) }
    }

    static func decodeListHeistsCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodeListHeistsRequest(arguments)
        return DecodedRequestDispatch { dispatchFence, _ in dispatchFence.handleListHeists(request) }
    }

    static func decodeDescribeHeistCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodeDescribeHeistRequest(arguments)
        return DecodedRequestDispatch { dispatchFence, _ in dispatchFence.handleDescribeHeist(request) }
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
        let swiftOutputPath = try arguments.schemaString("swiftOutput")
        let sampleParameter = try arguments.schemaString("sampleParameter")
        let sampleValue = try arguments.schemaString("sampleValue")
        guard (sampleParameter == nil) == (sampleValue == nil) else {
            throw FenceError.invalidRequest("sample rewrite requires both sampleParameter and sampleValue")
        }
        let sampleRewrite: RecordedHeistSwiftExport.SampleRewrite?
        if let sampleParameter, let sampleValue {
            guard swiftOutputPath != nil else {
                throw FenceError.invalidRequest("sample rewrite requires swiftOutput")
            }
            guard HeistParameterName.isValid(sampleParameter) else {
                throw FenceError.invalidRequest("sample rewrite parameter must be a Swift-style identifier")
            }
            guard !sampleValue.isEmpty else {
                throw FenceError.invalidRequest("sample rewrite value must not be empty")
            }
            sampleRewrite = RecordedHeistSwiftExport.SampleRewrite(
                parameterName: sampleParameter,
                sampleValue: sampleValue
            )
        } else {
            sampleRewrite = nil
        }
        let request = StopHeistRequest(
            outputPath: try arguments.requiredSchemaString("output"),
            swiftOutputPath: swiftOutputPath,
            sampleRewrite: sampleRewrite
        )
        return DecodedRequestDispatch { fence, _ in try fence.handleStopHeist(request) }
    }

    private func decodeConnectRequest(_ arguments: CommandArgumentEnvelope) throws -> ConnectRequest {
        ConnectRequest(
            targetName: try arguments.schemaString("target"),
            device: try arguments.schemaString("device"),
            token: try arguments.schemaString("token")
        )
    }

}
