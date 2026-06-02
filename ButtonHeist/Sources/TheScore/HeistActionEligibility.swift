import Foundation

public extension ClientMessage {
    var isHeistActionCommand: Bool {
        switch self {
        case .activate, .increment, .decrement, .performCustomAction, .rotor,
             .oneFingerTap, .longPress, .swipe, .drag, .typeText, .editAction,
             .setPasteboard, .scroll, .scrollToVisible, .scrollToEdge,
             .resignFirstResponder:
            return true
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .getPasteboard, .requestScreen, .wait, .heistPlan:
            return false
        }
    }
}
