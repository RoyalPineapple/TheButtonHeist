import Foundation

extension TheFence {

    struct ConnectRequest {
        let targetName: TargetName?
        let device: String?
        let token: String?
    }

    static func decodePingRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence in try await fence.handlePing() }
    }

    static func decodeListDevicesRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence in try await fence.handleListDevices() }
    }

    static func decodeGetSessionStateRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence in .sessionState(payload: fence.currentSessionState()) }
    }

    static func decodeListTargetsRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        DecodedRequestDispatch { fence in fence.handleListTargets() }
    }

    static func decodeRunHeistCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodeRunHeistRequest(arguments)
        return DecodedRequestDispatch { dispatchFence in try await dispatchFence.handleRunHeist(request) }
    }

    static func decodePerformCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodePerformRequest(arguments)
        return DecodedRequestDispatch { dispatchFence in try await dispatchFence.handlePerform(request) }
    }

    static func decodeListHeistsCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodeListHeistsRequest(arguments)
        return DecodedRequestDispatch { dispatchFence in dispatchFence.handleListHeists(request) }
    }

    static func decodeDescribeHeistCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodeDescribeHeistRequest(arguments)
        return DecodedRequestDispatch { dispatchFence in dispatchFence.handleDescribeHeist(request) }
    }

    static func decodeConnectCommandRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.decodeConnectRequest(arguments)
        return DecodedRequestDispatch { dispatchFence in try await dispatchFence.handleConnect(request) }
    }

    private func decodeConnectRequest(_ arguments: CommandArgumentEnvelope) throws -> ConnectRequest {
        ConnectRequest(
            targetName: try arguments.value(FenceParameters.connectionTarget).map(TargetName.init(rawValue:)),
            device: try arguments.value(FenceParameters.device),
            token: try arguments.value(FenceParameters.token)
        )
    }

}
