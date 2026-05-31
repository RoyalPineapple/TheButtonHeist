import TheScore

extension TheFence {

    static func decodeScrollRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let direction = try input.schemaEnum("direction", as: ScrollDirection.self) ?? .down
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

    static func decodeElementSearchRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try decodedExecutablePayload(.elementSearch(ElementSearchTarget(
            elementTarget: input.requiredElementTarget(command: .elementSearch),
            direction: input.schemaEnum("direction", as: ScrollDirection.self) ?? .down
        )))
    }

    static func decodeScrollToEdgeRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let edge = try input.schemaEnum("edge", as: ScrollEdge.self) ?? .top
        return try decodedExecutablePayload(.scrollToEdge(ScrollToEdgeTarget(
            selection: input.scrollContainerSelection(),
            edge: edge
        )))
    }
}
