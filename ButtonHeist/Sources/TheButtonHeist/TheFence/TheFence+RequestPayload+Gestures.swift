import Foundation

@_spi(ButtonHeistInternals) import TheScore

extension TheFence {

    static func decodeOneFingerTapRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(
            SpatialActionCommand.oneFingerTap,
            [.oneFingerTap(try fence.decodeTapTarget(arguments))]
        )
    }

    static func decodeLongPressRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(
            SpatialActionCommand.longPress,
            [.longPress(try fence.decodeLongPressTarget(arguments))]
        )
    }

    static func decodeSwipeRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(
            SpatialActionCommand.swipe,
            [.swipe(try fence.decodeSwipeTarget(arguments))]
        )
    }

    static func decodeDragRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        appInteractionDispatch(
            SpatialActionCommand.drag,
            [.drag(try fence.decodeDragTarget(arguments))]
        )
    }
}
