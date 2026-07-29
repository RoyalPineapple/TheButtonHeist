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
        switch command {
        case .activate, .oneFingerTap, .longPress:
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
        case .dismiss, .magicTap, .swipe, .drag,
             .scroll, .scrollToVisible, .scrollToEdge,
             .editAction, .setPasteboard, .takeScreenshot, .dismissKeyboard:
            self = .unknown
        }
    }

    var isKnown: Bool {
        self != .unknown
    }

    func isSupported(by element: HeistElement) -> Bool {
        let assertable = element.semantics.assertable
        switch self {
        case .activate:
            return assertable.actions.contains(.activate)
                || element.semantics.respondsToUserInteraction
                || !assertable.traits.isDisjoint(with: AccessibilityPolicy.interactiveTraits)
        case .increment:
            return assertable.actions.contains(.increment) || assertable.traits.contains(.adjustable)
        case .decrement:
            return assertable.actions.contains(.decrement) || assertable.traits.contains(.adjustable)
        case .customAction(let name):
            return assertable.actions.contains { action in
                guard case .custom(let candidateName) = action else { return false }
                return ElementPredicate.stringEquals(candidateName.description, name.description)
            }
        case .rotor:
            return !assertable.rotors.isEmpty
        case .textInput:
            return assertable.traits.contains(.textEntry)
                || assertable.traits.contains(.searchField)
                || assertable.traits.contains(.textArea)
                || assertable.traits.contains(.secureTextField)
        case .unknown:
            return true
        }
    }
}
