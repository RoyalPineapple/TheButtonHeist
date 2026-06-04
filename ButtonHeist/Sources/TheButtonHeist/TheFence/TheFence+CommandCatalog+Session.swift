enum SessionCommand: String, CaseIterable, FenceCommandFamilyCase {
    static let family: FenceCommandFamily = .session

    case ping
    case listDevices = "list_devices"
    case getSessionState = "get_session_state"
    case connect
    case listTargets = "list_targets"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .ping:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodePingRequest,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Check connection health without reading accessibility state."
            )
        case .listDevices:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeListDevicesRequest,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List discovered iOS devices and configured connection targets."
            )
        case .getSessionState:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeGetSessionStateRequest,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Inspect connection, device, and last-action session state."
            )
        case .connect:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeConnectCommandRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.target, .string), param(.device, .string), param(.token, .string)],
                description: "Establish or switch the active connection to a Button Heist app."
            )
        case .listTargets:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeListTargetsRequest,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List configured connection targets and the default target."
            )
        }
    }
}

enum HeistRecordingCommand: String, CaseIterable, FenceCommandFamilyCase {
    static let family: FenceCommandFamily = .heistRecording

    case startHeist = "start_heist"
    case stopHeist = "stop_heist"
    case playHeist = "play_heist"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .startHeist:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeStartHeistRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.app, .string), param(.identifier, .string)],
                description: "Start composing successful interactions into a semantic heist test."
            )
        case .stopHeist:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeStopHeistRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.output, .string, required: true)],
                description: "Stop heist recording and save a deterministic semantic heist fixture."
            )
        case .playHeist:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodePlayHeistRequest,
                parameters: [param(.input, .string, required: true)],
                description: "Play back a heist file and return step diagnostics on failure."
            )
        }
    }
}
