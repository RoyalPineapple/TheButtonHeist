import ThePlans

package extension ResolvedHeistActionCommand {
    var runtimeType: HeistActionCommandType {
        switch self {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .customAction: return .performCustomAction
        case .rotor: return .rotor
        case .dismiss: return .dismiss
        case .magicTap: return .magicTap
        case .mechanicalTap: return .oneFingerTap
        case .mechanicalLongPress: return .longPress
        case .mechanicalSwipe: return .swipe
        case .mechanicalDrag: return .drag
        case .typeText: return .typeText
        case .editAction: return .editAction
        case .viewportScroll: return .scroll
        case .viewportScrollToVisible: return .scrollToVisible
        case .viewportScrollToEdge: return .scrollToEdge
        case .dismissKeyboard: return .resignFirstResponder
        case .setPasteboard: return .setPasteboard
        case .takeScreenshot: return .takeScreenshot
        }
    }
}
