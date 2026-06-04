import TheScore

enum ObservationCommand: String, CaseIterable, FenceCommandFamilyCase {
    static let family: FenceCommandFamily = .observation

    case getInterface = "get_interface"
    case getScreen = "get_screen"
    case getPasteboard = "get_pasteboard"
    case wait

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .getInterface:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeGetInterfaceRequest,
                parameters: FenceParameterBlocks.elementFilter + [
                    FenceParameterBlocks.interfaceSubtree,
                    param(.detail, .string, enumValues: fenceEnumValues(InterfaceDetail.self)),
                ],
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: """
                    Read the app accessibility hierarchy, optionally scoped to a subtree.

                    containerName is ButtonHeist's generated name for a container in the current interface capture. \
                    It is useful for inspection and viewport/debug commands. It is not a semantic target and is not \
                    recorded into heists.
                    """
            )
        case .getScreen:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeGetScreenRequest,
                parameters: [param(.output, .string), param(.inlineData, .boolean), param(.includeInterface, .boolean)],
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true),
                description: "Capture a PNG screenshot with optional inline data and interface state."
            )
        case .getPasteboard:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeGetPasteboardRequest,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true),
                description: "Read text from the general pasteboard."
            )
        case .wait:
            return TheFence.Command.commandDescriptor(
                command, family: Self.family,
                requestDecoder: TheFence.decodeWaitRequest,
                parameters: FenceParameterBlocks.wait,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true),
                description: "Wait until an accessibility predicate is satisfied within timeout "
                    + "by evaluating settled semantic observations."
            )
        }
    }
}
