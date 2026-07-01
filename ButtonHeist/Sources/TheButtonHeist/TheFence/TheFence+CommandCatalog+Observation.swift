import TheScore
import ThePlans

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
                    Direct matcher fields `label`, `identifier`, and `value` accept StringMatch
                    objects like `{ "mode": "exact|contains|prefix|suffix", "value": "..." }`,
                    or an array of those objects when one property needs multiple checks.
                    Prefer `checks` when order matters or traits belong in the same predicate
                    chain; each item is `{ "kind": "label|identifier|value|traits|excludeTraits",
                    "match": StringMatch }` or `{ "kind": "traits|excludeTraits", "values": [...] }`.
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
                parameters: [FenceParameters.output.spec, FenceParameters.inlineData.spec],
                projection: .cliAndMCP(
                    "Capture a PNG screenshot with visible interface state.",
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
