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
        case .oneFingerTap: return .oneFingerTap
        case .longPress: return .longPress
        case .swipe: return .swipe
        case .drag: return .drag
        case .typeText: return .typeText
        case .editAction: return .editAction
        case .scroll: return .scroll
        case .scrollToVisible: return .scrollToVisible
        case .scrollToEdge: return .scrollToEdge
        case .dismissKeyboard: return .dismissKeyboard
        case .setPasteboard: return .setPasteboard
        case .takeScreenshot: return .takeScreenshot
        }
    }
}
