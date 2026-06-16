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
                requiresConnectionBeforeDispatch: false,
                projection: .cliOnly(
                    "Check connection health without reading accessibility state.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .listDevices:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodeListDevicesRequest,
                requiresConnectionBeforeDispatch: false,
                projection: .cliOnly(
                    "List discovered iOS devices and configured connection targets.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .getSessionState:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodeGetSessionStateRequest,
                requiresConnectionBeforeDispatch: false,
                projection: .cliAndMCP(
                    "Inspect connection, device, and last-action session state.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .connect:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodeConnectCommandRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.target, .string), param(.device, .string), param(.token, .string)],
                projection: .cliAndMCP("Establish or switch the active connection to a Button Heist app.")
            )
        case .listTargets:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodeListTargetsRequest,
                requiresConnectionBeforeDispatch: false,
                projection: .cliOnly(
                    "List configured connection targets and the default target.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        }
    }
}
