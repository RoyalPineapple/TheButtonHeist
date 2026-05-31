extension TheFence.Command {
    static var sessionCommandDescriptors: [FenceCommandDescriptor] {
        [
            commandDescriptor(
                .ping, requestDecoder: TheFence.decodePingRequest,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Check connection health without reading accessibility state."
            ),
            commandDescriptor(
                .listDevices, requestDecoder: TheFence.decodeListDevicesRequest,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List discovered iOS devices and configured connection targets."
            ),
            commandDescriptor(
                .getSessionState, requestDecoder: TheFence.decodeGetSessionStateRequest,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Inspect connection, device, and last-action session state."
            ),
            commandDescriptor(
                .connect, requestDecoder: TheFence.decodeConnectCommandRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.target, .string), param(.device, .string), param(.token, .string)],
                description: "Establish or switch the active connection to a Button Heist app."
            ),
            commandDescriptor(
                .listTargets, requestDecoder: TheFence.decodeListTargetsRequest,
                requiresConnectionBeforeDispatch: false,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "List configured connection targets and the default target."
            ),
            commandDescriptor(
                .startHeist, requestDecoder: TheFence.decodeStartHeistRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.app, .string), param(.identifier, .string)],
                description: "Start recording replayable heist steps from successful commands."
            ),
            commandDescriptor(
                .stopHeist, requestDecoder: TheFence.decodeStopHeistRequest,
                requiresConnectionBeforeDispatch: false,
                parameters: [param(.output, .string, required: true)],
                description: "Stop heist recording and save a deterministic heist fixture."
            ),
            commandDescriptor(
                .playHeist, requestDecoder: TheFence.decodePlayHeistRequest,
                parameters: [param(.input, .string, required: true)],
                description: "Play back a heist file and return step diagnostics on failure."
            ),
        ]
    }
}
