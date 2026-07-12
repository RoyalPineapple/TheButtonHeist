import Foundation

import ThePlans
import TheScore

extension TheFence {

    static func decodeOneFingerTapRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            Command.oneFingerTap,
            .mechanicalTap(try fence.decodeTapTarget(arguments)),
            expectationPayload: expectationPayload
        )
    }

    static func decodeLongPressRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            Command.longPress,
            .mechanicalLongPress(try fence.decodeLongPressTarget(arguments)),
            expectationPayload: expectationPayload
        )
    }

    static func decodeSwipeRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            Command.swipe,
            .mechanicalSwipe(try fence.decodeSwipeTarget(arguments)),
            expectationPayload: expectationPayload
        )
    }

    static func decodeDragRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        try appInteractionDispatch(
            Command.drag,
            .mechanicalDrag(try fence.decodeDragTarget(arguments)),
            expectationPayload: expectationPayload
        )
    }
}
