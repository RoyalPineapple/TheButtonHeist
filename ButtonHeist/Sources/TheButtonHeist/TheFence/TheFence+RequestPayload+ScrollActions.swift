import TheScore

extension TheFence {

    static func decodeScrollRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let direction = try input.schemaEnum("direction", as: ScrollDirection.self)
            ?? Command.scroll.descriptor.requiredDefaultEnumValue(for: .direction, as: ScrollDirection.self)
        return try decodedExecutablePayload(.scroll(ScrollTarget(
            selection: input.scrollContainerSelection(),
            direction: direction
        )))
    }

    static func decodeScrollToVisibleRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try decodedExecutablePayload(.scrollToVisible(ScrollToVisibleTarget(
            elementTarget: input.requiredElementTarget(command: .scrollToVisible)
        )))
    }

    static func decodeScrollToEdgeRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let edge = try input.schemaEnum("edge", as: ScrollEdge.self)
            ?? Command.scrollToEdge.descriptor.requiredDefaultEnumValue(for: .edge, as: ScrollEdge.self)
        return try decodedExecutablePayload(.scrollToEdge(ScrollToEdgeTarget(
            selection: input.scrollContainerSelection(),
            edge: edge
        )))
    }
}
