import ThePlans
import Foundation

public extension ClientMessage {
    var isHeistActionCommand: Bool {
        switch self {
        case .activate, .increment, .decrement, .performCustomAction, .rotor,
             .oneFingerTap, .longPress, .swipe, .drag, .typeText, .editAction,
             .setPasteboard, .resignFirstResponder:
            return true
        case .scroll, .scrollToVisible, .scrollToEdge:
            return false
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .getPasteboard, .requestScreen, .wait, .heistPlan:
            return false
        }
    }
}
