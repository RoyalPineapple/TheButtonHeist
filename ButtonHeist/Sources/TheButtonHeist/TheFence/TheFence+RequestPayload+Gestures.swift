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
        default:
            throw FenceError.invalidRequest("Unexpected gesture command: \(command.rawValue)")
        }
    }

    private func decodedGestureAction(_ message: ClientMessage) -> DecodedRequestDispatch {
        Self.clientActionDispatch([message])
    }
}
