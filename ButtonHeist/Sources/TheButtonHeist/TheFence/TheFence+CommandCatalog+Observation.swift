import TheScore

enum ObservationCommand: String, CaseIterable, FenceCommand {
    case getInterface = "get_interface"
    case getScreen = "get_screen"
    case getPasteboard = "get_pasteboard"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .getInterface:
            return TheFence.Command.commandDescriptor(
                command, family: .observation,
                requestDecoder: TheFence.decodeGetInterfaceRequest,
                parameters: FenceParameterBlocks.elementFilter + [
                    FenceParameterBlocks.interfaceSubtree,
                    param(.detail, .string, enumValues: fenceEnumValues(InterfaceDetail.self)),
                ],
                projection: .cliAndMCP(
                    """
                    Read the app accessibility hierarchy, optionally scoped to a subtree.

                    Build DSL targets from returned accessibility language: `.label("Pay")`,
                    `.identifier("pay_button")`, `.value("Milk")`, `.element(label: "Pay",
                    traits: [.button])`, or `.target(..., ordinal: n)` for duplicates.
                    `containerName` is for inspection and viewport/debug commands only; it is
                    not a semantic target or durable heist selector.
                    """,
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .getScreen:
            return TheFence.Command.commandDescriptor(
                command, family: .observation,
                requestDecoder: TheFence.decodeGetScreenRequest,
                parameters: [param(.output, .string), param(.inlineData, .boolean), param(.includeInterface, .boolean)],
                projection: .cliAndMCP(
                    "Capture a PNG screenshot with optional inline data and interface state.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .getPasteboard:
            return TheFence.Command.commandDescriptor(
                command, family: .observation,
                requestDecoder: TheFence.decodeGetPasteboardRequest,
                projection: .cliAndMCP(
                    "Read text from the general pasteboard.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true)
                )
            )
        }
    }
}

enum AssertionCommand: String, CaseIterable, FenceCommand, HeistPrimitiveCommand {
    case wait

    var descriptor: FenceCommandDescriptor {
        TheFence.Command.commandDescriptor(
            command, family: .assertion,
            requestDecoder: TheFence.decodeWaitRequest,
            parameters: FenceParameterBlocks.wait,
            projection: .cliOnly(
                "Assert that an accessibility predicate is satisfied within timeout "
                    + "by evaluating settled accessibility state.",
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true)
            )
        )
    }
}
