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
            SpatialActionCommand.oneFingerTap.command,
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
            SpatialActionCommand.longPress.command,
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
            SpatialActionCommand.swipe.command,
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
            SpatialActionCommand.drag.command,
            .mechanicalDrag(try fence.decodeDragTarget(arguments)),
            expectationPayload: expectationPayload
        )
    }
}
