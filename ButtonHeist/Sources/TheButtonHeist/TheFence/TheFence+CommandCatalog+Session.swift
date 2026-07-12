extension TheFence.Command {
    func makeSessionDescriptor() -> FenceCommandDescriptor {
        switch self {
        case .ping:
            return makeDescriptor(
                family: .session,
                requestDecoder: TheFence.decodePingRequest,
                requiresConnectionBeforeDispatch: false,
                timeout: .fixed(.health),
                responseProjection: .pong,
                projection: .cliOnly(
                    "Check connection health without reading accessibility state.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .listDevices:
            return makeDescriptor(
                family: .session,
                requestDecoder: TheFence.decodeListDevicesRequest,
                requiresConnectionBeforeDispatch: false,
                responseProjection: .devices,
                projection: .cliOnly(
                    "List discovered iOS devices and configured connection targets.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .getSessionState:
            return makeDescriptor(
                family: .session,
                requestDecoder: TheFence.decodeGetSessionStateRequest,
                requiresConnectionBeforeDispatch: false,
                responseProjection: .sessionState,
                projection: .cliAndMCP(
                    "Inspect connection, device, and last-action session state.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .connect:
            return makeDescriptor(
                family: .session,
                requestDecoder: TheFence.decodeConnectCommandRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [
                    FenceParameters.connectionTarget.spec,
                    FenceParameters.device.spec,
                    FenceParameters.token.spec,
                ],
                responseProjection: .sessionState,
                projection: .cliAndMCP("Establish or switch the active connection to an app running The Button Heist.")
            )
        case .listTargets:
            return makeDescriptor(
                family: .session,
                requestDecoder: TheFence.decodeListTargetsRequest,
                requiresConnectionBeforeDispatch: false,
                responseProjection: .targets,
                projection: .cliOnly(
                    "List configured connection targets and the default target.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .getInterface, .getScreen, .getPasteboard, .getAnnouncements, .wait,
             .oneFingerTap, .longPress, .swipe, .drag, .scroll, .scrollToVisible, .scrollToEdge,
             .activate, .rotor, .typeText, .editAction, .setPasteboard, .dismissKeyboard,
             .perform, .runHeist, .listHeists, .describeHeist:
            preconditionFailure("\(rawValue) is not a session command")
        }
    }
}
