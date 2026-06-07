enum SessionCommand: String, CaseIterable, FenceCommand {
    case ping
    case listDevices = "list_devices"
    case getSessionState = "get_session_state"
    case connect
    case listTargets = "list_targets"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .ping:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodePingRequest,
                mcpExposure: .notExposed,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Check connection health without reading accessibility state."
            )
        case .listDevices:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodeListDevicesRequest,
                mcpExposure: .notExposed,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List discovered iOS devices and configured connection targets."
            )
        case .getSessionState:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodeGetSessionStateRequest,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Inspect connection, device, and last-action session state."
            )
        case .connect:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodeConnectCommandRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.target, .string), param(.device, .string), param(.token, .string)],
                description: "Establish or switch the active connection to a Button Heist app."
            )
        case .listTargets:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodeListTargetsRequest,
                mcpExposure: .notExposed,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List configured connection targets and the default target."
            )
        }
    }
}
