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
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Check connection health without reading accessibility state."
            )
        case .listDevices:
            return TheFence.Command.commandDescriptor(
                command, family: .session,
                requestDecoder: TheFence.decodeListDevicesRequest,
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
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List configured connection targets and the default target."
            )
        }
    }
}

enum HeistRecordingCommand: String, CaseIterable, FenceCommand {
    case startHeist = "start_heist"
    case stopHeist = "stop_heist"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .startHeist:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRecording,
                requestDecoder: TheFence.decodeStartHeistRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.app, .string), param(.identifier, .string)],
                description: "Start composing successful interactions into a semantic heist test."
            )
        case .stopHeist:
            return TheFence.Command.commandDescriptor(
                command, family: .heistRecording,
                requestDecoder: TheFence.decodeStopHeistRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.output, .string, required: true)],
                description: "Stop heist recording and save a deterministic semantic heist fixture."
            )
        }
    }
}
