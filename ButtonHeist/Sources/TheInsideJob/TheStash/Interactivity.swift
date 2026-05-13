#if canImport(UIKit)
#if DEBUG
import UIKit
import ObjectiveC.runtime

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

    private static func hasInteractiveTraits(_ element: AccessibilityElement) -> Bool {
        !element.traits.isDisjoint(with: AccessibilityPolicy.interactiveTraitsBitmask)
    }

    private static func supportsDefaultActivation(_ object: NSObject?) -> Bool {
        guard let object else { return false }
        return hasActivationBlock(object) || overridesAccessibilityActivate(object)
    }

    private static func hasActivationBlock(_ object: NSObject) -> Bool {
        if #available(iOS 17.0, tvOS 17.0, *) {
            guard object.responds(to: NSSelectorFromString("accessibilityActivateBlock")) else {
                return false
            }
            return object.accessibilityActivateBlock != nil
        }
        return false
    }

    private static func overridesAccessibilityActivate(_ object: NSObject) -> Bool {
        guard var currentClass = object_getClass(object) else { return false }
        let selector = #selector(NSObject.accessibilityActivate)

        while !isDefaultActivationBoundary(currentClass),
              let superclass = class_getSuperclass(currentClass) {
            if let currentMethod = class_getInstanceMethod(currentClass, selector),
               let superclassMethod = class_getInstanceMethod(superclass, selector),
               method_getImplementation(currentMethod) != method_getImplementation(superclassMethod) {
                return true
            }
            currentClass = superclass
        }
        return false
    }

    private static func isDefaultActivationBoundary(_ type: AnyClass) -> Bool {
        type == NSObject.self
            || type == UIResponder.self
            || type == UIView.self
            || type == UIControl.self
            || type == UIAccessibilityElement.self
    }

    /// Check if an element is interactive based on its parsed accessibility data.
    static func isInteractive(element: AccessibilityElement, object: NSObject? = nil) -> Bool {
        element.respondsToUserInteraction
            || supportsDefaultActivation(object)
            || hasInteractiveTraits(element)
            || !element.customActions.isEmpty
    }

    /// Validate whether an element can receive interaction based on its traits.
    /// Pure — any advisory warning travels with `.interactive`; the caller decides
    /// whether to log it.
    static func checkInteractivity(_ element: AccessibilityElement, object: NSObject? = nil) -> InteractivityCheck {
        if element.traits.contains(.notEnabled) {
            return .blocked(reason: "Element is disabled (has 'notEnabled' trait)")
        }

        let supportsActivation = supportsDefaultActivation(object)
        let staticTraitsOnly = element.traits.isSubset(of: AccessibilityPolicy.staticOnlyTraitsBitmask)
        let warning: String? = (
            staticTraitsOnly
                && !supportsActivation
                && !hasInteractiveTraits(element)
                && element.customActions.isEmpty
        )
            ? "Element '\(element.description)' has only static traits, tap may not work"
            : nil

        return .interactive(warning: warning)
    }

    }
}

#endif // DEBUG
#endif // canImport(UIKit)
