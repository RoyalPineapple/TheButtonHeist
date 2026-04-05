#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser

// MARK: - Element Interactivity

extension TheStash {

    /// Pure predicates for element interactivity — no mutable state.
    /// Used by WireConverter (to build action lists) and ActionExecutor
    /// (to gate interaction attempts).
    enum InteractivityCheck {
        case interactive
        case blocked(reason: String)
    }

    @MainActor enum Interactivity {

    /// Check if an element is interactive based on its parsed accessibility data.
    static func isInteractive(element: AccessibilityElement) -> Bool {
        element.respondsToUserInteraction
            || element.traits.contains(.adjustable)
            || !element.customActions.isEmpty
    }

    /// Validate whether an element can receive interaction based on its traits.
    static func checkInteractivity(_ element: AccessibilityElement) -> InteractivityCheck {
        if element.traits.contains(.notEnabled) {
            return .blocked(reason: "Element is disabled (has 'notEnabled' trait)")
        }

        let staticTraitsOnly = element.traits.isSubset(of: [.staticText, .image, .header])
        let hasInteractiveTraits = element.traits.contains(.button) ||
                                   element.traits.contains(.link) ||
                                   element.traits.contains(.adjustable) ||
                                   element.traits.contains(.searchField) ||
                                   element.traits.contains(.keyboardKey)

        if staticTraitsOnly && !hasInteractiveTraits && element.customActions.isEmpty {
            insideJobLogger.warning("Element '\(element.description)' has only static traits, tap may not work")
        }

        return .interactive
    }

    }
} // extension TheStash

#endif // DEBUG
#endif // canImport(UIKit)
