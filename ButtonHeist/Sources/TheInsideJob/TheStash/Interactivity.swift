#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Element Interactivity

extension TheStash {

    /// Pure predicates for element interactivity — no mutable state.
    /// Used by WireConverter (to build action lists) and ActionExecutor
    /// (to gate interaction attempts).
    enum InteractivityCheck {
        case interactive(warning: String?)
        case blocked(reason: String)
    }

    /// Caseless namespace enum for MainActor-bound static helpers that read
    /// UIKit responder / window state. No instances are constructed.
    @MainActor enum Interactivity { // swiftlint:disable:this agent_main_actor_value_type

    private static let interactiveHeistTraits: [HeistTrait] = [
        .button, .link, .adjustable, .searchField, .keyboardKey,
        .backButton, .switchButton
    ]

    private static let interactiveTraits: UIAccessibilityTraits =
        UIAccessibilityTraits.fromNames(interactiveHeistTraits.map(\.rawValue))

    private static func hasInteractiveTraits(_ element: AccessibilityElement) -> Bool {
        !element.traits.isDisjoint(with: interactiveTraits)
    }

    /// Check if an element is interactive based on its parsed accessibility data.
    static func isInteractive(element: AccessibilityElement) -> Bool {
        element.respondsToUserInteraction
            || hasInteractiveTraits(element)
            || !element.customActions.isEmpty
    }

    /// Validate whether an element can receive interaction based on its traits.
    /// Pure — any advisory warning travels with `.interactive`; the caller decides
    /// whether to log it.
    static func checkInteractivity(_ element: AccessibilityElement) -> InteractivityCheck {
        if element.traits.contains(.notEnabled) {
            return .blocked(reason: "Element is disabled (has 'notEnabled' trait)")
        }

        let staticTraitsOnly = element.traits.isSubset(of: [.staticText, .image, .header])
        let warning: String? = (staticTraitsOnly && !hasInteractiveTraits(element) && element.customActions.isEmpty)
            ? "Element '\(element.description)' has only static traits, tap may not work"
            : nil

        return .interactive(warning: warning)
    }

    }
}

#endif // DEBUG
#endif // canImport(UIKit)
