import TheScore
import ThePlans

extension TheFence {

    static func decodeScrollRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let direction = try input.value(
            FenceParameters.scrollDirection,
            defaultFrom: Command.scroll.descriptor
        )
        return try appInteractionDispatch(
            ViewportDebugCommand.scroll.command,
            .viewportScroll(ScrollTarget(
                selection: try input.scrollContainerSelection(),
                direction: direction
            )),
            expectationPayload: expectationPayload
        )
    }

    static func decodeScrollToVisibleRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            ViewportDebugCommand.scrollToVisible.command,
            .viewportScrollToVisible(.target(try input.requiredElementTarget(command: .scrollToVisible))),
            expectationPayload: expectationPayload
        )
    }

    static func decodeScrollToEdgeRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let edge = try input.value(
            FenceParameters.scrollEdge,
            defaultFrom: Command.scrollToEdge.descriptor
        )
        return try appInteractionDispatch(
            ViewportDebugCommand.scrollToEdge.command,
            .viewportScrollToEdge(ScrollToEdgeTarget(
                selection: try input.scrollContainerSelection(),
                edge: edge
            )),
            expectationPayload: expectationPayload
        )
    }
}
