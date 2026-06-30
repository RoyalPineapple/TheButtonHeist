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
        appInteractionDispatch(
            SpatialActionCommand.oneFingerTap.command,
            .mechanicalTap(try fence.decodeTapTarget(arguments))
        )
    }

    static func decodeLongPressRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(
            SpatialActionCommand.longPress.command,
            .mechanicalLongPress(try fence.decodeLongPressTarget(arguments))
        )
    }

    static func decodeSwipeRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(
            SpatialActionCommand.swipe.command,
            .mechanicalSwipe(try fence.decodeSwipeTarget(arguments))
        )
    }

    static func decodeDragRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(
            SpatialActionCommand.drag.command,
            .mechanicalDrag(try fence.decodeDragTarget(arguments))
        )
    }
}
