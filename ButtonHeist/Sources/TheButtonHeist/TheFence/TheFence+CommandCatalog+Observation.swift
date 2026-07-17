import TheScore
import ThePlans

extension TheFence.Command {
    func makeObservationDescriptor() -> FenceCommandDescriptor {
        switch self {
        case .getInterface:
            return makeDescriptor(
                family: .observation,
                parameters: [
                    FenceParameterBlocks.interfaceSubtree,
                    FenceParameters.interfaceDetail.spec,
                    FenceParameters.maxScrollsPerContainer.spec,
                    FenceParameters.maxScrollsPerDiscovery.spec,
                ],
                timeout: .fixed(.explore),
                projection: .cliAndMCP(
                    """
                    Read the app accessibility hierarchy, optionally scoped to a subtree.

                    Build DSL targets from returned accessibility language: `.label("Pay")`,
                    `.identifier("pay_button")`, `.value("Milk")`, `.element(.label("Pay"),
                    .traits([.button]))`, or `.target(..., ordinal: n)` for duplicates.
                    Pass `subtree` a canonical accessibility target. Element target checks use
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
            return makeDescriptor(
                family: .observation,
                parameters: [FenceParameters.output.spec, FenceParameters.inlineData.spec, FenceParameters.screenMode.spec],
                timeout: .fixed(.screenCapture),
                projection: .cliAndMCP(
                    "Capture a PNG screenshot with visible interface state. Pass mode=accessibility to render accessibility markers and legend.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .getPasteboard:
            return makeDescriptor(
                family: .observation,
                timeout: .fixed(.health),
                projection: .cliAndMCP(
                    "Read text from the general pasteboard.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true)
                )
            )
        case .getAnnouncements:
            return makeDescriptor(
                family: .observation,
                timeout: .fixed(.health),
                projection: .cliAndMCP(
                    "Read recent spoken accessibility text captured from announcement, elementChanged, valueChanged, or screenChanged notifications.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            )
        case .ping, .listDevices, .getSessionState, .connect, .listTargets, .wait,
             .oneFingerTap, .longPress, .swipe, .drag, .scroll, .scrollToVisible, .scrollToEdge,
             .activate, .rotor, .typeText, .editAction, .setPasteboard, .dismissKeyboard,
             .perform, .runHeist, .validateHeist, .listHeists, .describeHeist:
            preconditionFailure("\(rawValue) is not an observation command")
        }
    }
}

extension TheFence.Command {
    func makeAssertionDescriptor() -> FenceCommandDescriptor {
        guard self == .wait else {
            preconditionFailure("\(rawValue) is not an assertion command")
        }
        return makeDescriptor(
            family: .assertion,
            parameters: FenceParameterBlocks.wait,
            timeout: .wait,
            projection: .cliOnly(
                "Assert that an accessibility predicate is satisfied within timeout "
                    + "by evaluating settled accessibility state.",
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true)
            )
        )
    }
}
