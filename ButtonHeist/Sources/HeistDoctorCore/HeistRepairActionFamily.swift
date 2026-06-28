import Foundation
import ThePlans
import TheScore

enum RepairActionFamily: Sendable, Equatable {
    case activate
    case increment
    case decrement
    case customAction(String?)
    case rotor
    case textInput
    case unknown

    init(actionIdentity: HeistRepairActionIdentity) {
        switch actionIdentity.commandType {
        case .activate, .oneFingerTap, .longPress:
            self = .activate
        case .increment:
            self = .increment
        case .decrement:
            self = .decrement
        case .performCustomAction:
            self = .customAction(actionIdentity.customActionName)
        case .rotor:
            self = .rotor
        case .typeText:
            self = .textInput
        default:
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
            let customActions = element.actions.compactMap { action -> String? in
                if case .custom(let name) = action { return name }
                return nil
            }
            guard let name, !name.isEmpty else {
                return !customActions.isEmpty
            }
            return customActions.contains { ElementPredicate.stringEquals($0, name) }
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
