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

    init(actionIdentity: HeistRepairActionIdentity?, actionKind: String, method: ActionMethod?) {
        if let actionIdentity {
            self = Self(actionIdentity: actionIdentity)
            return
        }
        self = Self(legacyActionKind: actionKind, method: method)
    }

    init(actionKind: String, method: ActionMethod?) {
        self = Self(legacyActionKind: actionKind, method: method)
    }

    private init(actionIdentity: HeistRepairActionIdentity) {
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

    private init(legacyActionKind actionKind: String, method: ActionMethod?) {
        if let method {
            self = Self(legacyMethod: method, actionKind: actionKind)
            return
        }
        self = Self(legacyActionKind: actionKind)
    }

    private init(legacyMethod method: ActionMethod, actionKind: String) {
        switch method {
        case .activate, .syntheticTap, .syntheticLongPress:
            self = .activate
        case .increment:
            self = .increment
        case .decrement:
            self = .decrement
        case .customAction:
            self = .customAction(Self.customActionName(from: actionKind))
        case .rotor:
            self = .rotor
        case .typeText:
            self = .textInput
        default:
            self = Self(legacyActionKind: actionKind)
        }
    }

    private init(legacyActionKind actionKind: String) {
        let normalized = actionKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "activate"
            || normalized == "onefingertap"
            || normalized == "one_finger_tap"
            || normalized == "longpress"
            || normalized == "long_press" {
            self = .activate
        } else if normalized == "increment" {
            self = .increment
        } else if normalized == "decrement" {
            self = .decrement
        } else if normalized == "performcustomaction"
            || normalized == "perform_custom_action"
            || normalized == "customaction"
            || normalized == "custom_action" {
            self = .customAction(nil)
        } else if normalized.hasPrefix("custom:") {
            self = .customAction(String(actionKind.dropFirst("custom:".count)))
        } else if normalized == "rotor" {
            self = .rotor
        } else if normalized == "typetext" || normalized == "type_text" {
            self = .textInput
        } else {
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

    private static func customActionName(from actionKind: String) -> String? {
        let separators = [":", "#"]
        for separator in separators where actionKind.contains(separator) {
            let suffix = actionKind.split(separator: Character(separator), maxSplits: 1).dropFirst().first
            return suffix.map(String.init)
        }
        return nil
    }
}
