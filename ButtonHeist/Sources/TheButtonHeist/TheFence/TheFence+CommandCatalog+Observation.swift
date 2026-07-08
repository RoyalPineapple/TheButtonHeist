import TheScore
import ThePlans

enum ObservationCommand: String, CaseIterable, FenceCommand {
    case getInterface = "get_interface"
    case getScreen = "get_screen"
    case getPasteboard = "get_pasteboard"
    case getAnnouncements = "get_announcements"

    var descriptor: FenceCommandDescriptor {
        switch self {
        case .getInterface:
            return TheFence.Command.commandDescriptor(
                command, family: .observation,
                requestDecoder: TheFence.decodeGetInterfaceRequest,
                parameters: FenceParameterBlocks.elementFilter + [
                    FenceParameterBlocks.interfaceSubtree,
                    FenceParameters.interfaceDetail.spec,
                    FenceParameters.maxScrollsPerContainer.spec,
                    FenceParameters.maxScrollsPerDiscovery.spec,
                ],
                projection: .cliAndMCP(
                    """
                    Read the app accessibility hierarchy, optionally scoped to a subtree.

                    Build DSL targets from returned accessibility language: `.label("Pay")`,
                    `.identifier("pay_button")`, `.value("Milk")`, `.element(.label("Pay"),
                    .traits([.button]))`, or `.target(..., ordinal: n)` for duplicates.
                    Filter with `checks`; each item is
                    `{ "kind": "label|identifier|value|hint|customContent", "match": ... }`,
                    `{ "kind": "traits|actions|rotors", "values": [...] }`, or
                    `{ "kind": "exclude", "check": { ... } }`.
                    Custom actions use `{ "custom": "Sub" }`.
                    `containerName` is for inspection and viewport/debug commands only; it is
                    not a semantic target or durable heist selector.
                    `maxScrollsPerContainer` and `maxScrollsPerDiscovery` bound the command-owned
                    interface discovery pass; omit them to use Inside Job runtime defaults.
                    """,
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .getScreen:
            return TheFence.Command.commandDescriptor(
                command, family: .observation,
                requestDecoder: TheFence.decodeGetScreenRequest,
                parameters: [FenceParameters.output.spec, FenceParameters.inlineData.spec, FenceParameters.screenMode.spec],
                projection: .cliAndMCP(
                    "Capture a PNG screenshot with visible interface state. Pass mode=accessibility to render accessibility markers and legend.",
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
        case .getAnnouncements:
            return TheFence.Command.commandDescriptor(
                command, family: .observation,
                requestDecoder: TheFence.decodeGetAnnouncementsRequest,
                projection: .cliAndMCP(
                    "Read recent spoken accessibility text captured from announcement, elementChanged, or screenChanged notifications.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        }
    }
}

enum AssertionCommand: String, CaseIterable, FenceCommand {
    case wait

    var descriptor: FenceCommandDescriptor {
        TheFence.Command.commandDescriptor(
            command, family: .assertion,
            requestDecoder: TheFence.decodeWaitRequest,
            parameters: FenceParameterBlocks.wait,
            execution: [.heistPrimitive],
            projection: .cliOnly(
                "Assert that an accessibility predicate is satisfied within timeout "
                    + "by evaluating settled accessibility state.",
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true)
            )
        )
    }
}
