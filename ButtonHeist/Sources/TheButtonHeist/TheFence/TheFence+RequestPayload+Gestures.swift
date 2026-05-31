import Foundation

import TheScore

extension TheFence {

    static func decodeOneFingerTapRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        decodedGestureAction(.oneFingerTap(try fence.decodeTapTarget(arguments)))
    }

    static func decodeLongPressRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        decodedGestureAction(.longPress(try fence.decodeLongPressTarget(arguments)))
    }

    static func decodeSwipeRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        decodedGestureAction(.swipe(try fence.decodeSwipeTarget(arguments)))
    }

    static func decodeDragRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        decodedGestureAction(.drag(try fence.decodeDragTarget(arguments)))
    }

    private static func decodedGestureAction(_ message: ClientMessage) -> DecodedRequestDispatch {
        Self.clientActionDispatch([message])
    }
}
