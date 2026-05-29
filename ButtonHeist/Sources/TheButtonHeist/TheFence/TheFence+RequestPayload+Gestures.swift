import Foundation

import TheScore

extension TheFence {

    func decodeGestureAction(
        command: Command,
        request: CommandArgumentEnvelope
    ) throws -> DecodedRequestDispatch {
        switch command {
        case .oneFingerTap:
            return decodedGestureAction(.oneFingerTap(try decodeTapTarget(request)))
        case .longPress:
            return decodedGestureAction(.longPress(try decodeLongPressTarget(request)))
        case .swipe:
            return decodedGestureAction(.swipe(try decodeSwipeTarget(request)))
        case .drag:
            return decodedGestureAction(.drag(try decodeDragTarget(request)))
        case .pinch:
            return decodedGestureAction(.pinch(try decodePinchTarget(request)))
        case .rotate:
            return decodedGestureAction(.rotate(try decodeRotateTarget(request)))
        case .twoFingerTap:
            return decodedGestureAction(.twoFingerTap(try decodeTwoFingerTapTarget(request)))
        case .drawPath:
            return decodedGestureAction(.drawPath(try decodeDrawPathTarget(request)))
        case .drawBezier:
            return decodedGestureAction(.drawBezier(try decodeDrawBezierTarget(request)))
        default:
            throw FenceError.invalidRequest("Unexpected gesture command: \(command.rawValue)")
        }
    }

    private func decodedGestureAction(_ message: ClientMessage) -> DecodedRequestDispatch {
        Self.clientActionDispatch([message])
    }
}
