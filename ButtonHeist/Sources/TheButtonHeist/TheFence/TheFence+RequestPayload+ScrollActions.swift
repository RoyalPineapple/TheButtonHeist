import TheScore
import ThePlans

extension TheFence {

    static func decodeScrollRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let direction = try input.schemaEnum("direction", as: ScrollDirection.self)
            ?? Command.scroll.descriptor.requiredDefaultEnumValue(for: .direction, as: ScrollDirection.self)
        return appInteractionDispatch(
            ViewportDebugCommand.scroll.command,
            .viewportScroll(ScrollTarget(
                selection: try input.scrollContainerSelection(),
                direction: direction
            ))
        )
    }

    static func decodeScrollToVisibleRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(
            ViewportDebugCommand.scrollToVisible.command,
            .viewportScrollToVisible(.target(try input.requiredElementTarget(command: .scrollToVisible)))
        )
    }

    static func decodeScrollToEdgeRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let edge = try input.schemaEnum("edge", as: ScrollEdge.self)
            ?? Command.scrollToEdge.descriptor.requiredDefaultEnumValue(for: .edge, as: ScrollEdge.self)
        return appInteractionDispatch(
            ViewportDebugCommand.scrollToEdge.command,
            .viewportScrollToEdge(ScrollToEdgeTarget(
                selection: try input.scrollContainerSelection(),
                edge: edge
            ))
        )
    }
}
