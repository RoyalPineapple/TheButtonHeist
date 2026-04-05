#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser

// MARK: - Element Interactivity

extension TheBagman {

    /// Pure predicates for element interactivity — no mutable state.
    /// Used by WireConverter (to build action lists) and ActionExecutor
    /// (to gate interaction attempts).
    @MainActor enum Interactivity {

    /// Check if an element is interactive given its parsed data and live object.
    static func isInteractive(element: AccessibilityElement, object: NSObject?) -> Bool {
        guard let object else { return false }
        return element.respondsToUserInteraction
            || element.traits.contains(.adjustable)
            || !element.customActions.isEmpty
            || object.accessibilityRespondsToUserInteraction
    }

    /// Check if an element is interactive based on traits.
    /// Returns nil if interactive, or an error string if not.
    static func checkInteractivity(_ element: AccessibilityElement) -> String? {
        if element.traits.contains(.notEnabled) {
            return "Element is disabled (has 'notEnabled' trait)"
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

        return nil
    }

    /// Return custom action names from a live NSObject.
    static func customActionNames(from object: NSObject?) -> [String] {
        object?.accessibilityCustomActions?.map { $0.name } ?? []
    }
    }
} // extension TheBagman

#endif // DEBUG
#endif // canImport(UIKit)
