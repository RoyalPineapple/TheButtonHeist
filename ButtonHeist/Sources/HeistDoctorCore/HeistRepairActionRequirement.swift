import ThePlans
import TheScore

enum RepairActionRequirement: Sendable, Equatable {
    case activate
    case increment
    case decrement
    case customAction(CustomActionName)
    case rotor
    case textInput
    case unknown

    init(command: HeistActionCommand) {
        switch command.core {
        case .activate, .mechanicalTap, .mechanicalLongPress:
            self = .activate
        case .increment:
            self = .increment
        case .decrement:
            self = .decrement
        case .customAction(let name, _):
            self = .customAction(name)
        case .rotor:
            self = .rotor
        case .typeText:
            self = .textInput
        case .dismiss, .magicTap, .mechanicalSwipe, .mechanicalDrag,
             .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge,
             .editAction, .setPasteboard, .takeScreenshot, .dismissKeyboard:
            self = .unknown
        }
    }

    var isKnown: Bool {
        self != .unknown
    }

    func isSupported(by element: HeistElement) -> Bool {
        switch self {
        case .activate:
            return element.actions.contains(.activate)
                || element.respondsToUserInteraction
                || !Set(element.traits).isDisjoint(with: AccessibilityPolicy.interactiveTraits)
        case .increment:
            return element.actions.contains(.increment) || element.traits.contains(.adjustable)
        case .decrement:
            return element.actions.contains(.decrement) || element.traits.contains(.adjustable)
        case .customAction(let name):
            return element.actions.contains { action in
                guard case .custom(let candidateName) = action else { return false }
                return ElementPredicate.stringEquals(candidateName.description, name.description)
            }
        case .rotor:
            return element.rotors?.isEmpty == false
        case .textInput:
            return element.traits.contains(.textEntry)
                || element.traits.contains(.searchField)
                || element.traits.contains(.textArea)
                || element.traits.contains(.secureTextField)
        case .unknown:
            return true
        }
    }
}
