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
            Command.scroll,
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
            Command.scrollToVisible,
            .viewportScrollToVisible(try input.requiredAccessibilityTarget(command: .scrollToVisible)),
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
            Command.scrollToEdge,
            .viewportScrollToEdge(ScrollToEdgeTarget(
                selection: try input.scrollContainerSelection(),
                edge: edge
            )),
            expectationPayload: expectationPayload
        )
    }
}
