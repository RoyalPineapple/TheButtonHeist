#if canImport(UIKit)
#if DEBUG
import UIKit

import ThePlans
import TheScore

import AccessibilitySnapshotParser

// MARK: - Element Interactivity

package extension AccessibilityElement {
    var projectedActionSet: ElementActionSet {
        let isInteractive = respondsToUserInteraction
            || !traits.isDisjoint(with: AccessibilityPolicy.interactiveTraitsBitmask)
            || !customActions.isEmpty
        var actions: [ElementAction] = isInteractive ? [.activate] : []
        if AccessibilityPolicy.supportsTextEntry(traits.heistTraits) {
            actions.append(.typeText)
        }
        if isInteractive, traits.contains(.adjustable) {
            actions.append(contentsOf: [.increment, .decrement])
        }
        actions.append(contentsOf: customActions
            .compactMap { try? CustomActionName(validating: $0.name) }
            .map(ElementAction.custom))
        return ElementActionSet(actions)
    }
}

extension TheVault {

    /// Interactivity classification and runtime activation diagnostics.
    enum InteractivityCheck {
        case interactive(warning: String?)
        case blocked(reason: String)
    }

    /// Caseless namespace enum for MainActor-bound static helpers that read
    /// UIKit responder / window state. No instances are constructed.
    @MainActor enum Interactivity {

    private static func hasInteractiveTraits(_ element: AccessibilityElement) -> Bool {
        !element.traits.isDisjoint(with: AccessibilityPolicy.interactiveTraitsBitmask)
    }

    /// Runtime implementation introspection for activation diagnostics.
    ///
    /// This is not an accessibility semantic and must never decide whether an
    /// `activate` command is dispatched. VoiceOver asks every target to activate;
    /// Button Heist uses this only to explain a declined activation afterward.
    static func implementsAccessibilityActivation(_ object: NSObject?) -> Bool {
        guard let object else { return false }
        return hasActivationBlock(object) || overridesAccessibilityActivate(object)
    }

    private static func hasActivationBlock(_ object: NSObject) -> Bool {
        // accessibilityActivateBlock is iOS 17+; on earlier deployment targets
        // block-based activation cannot exist, so there is nothing to detect.
        guard #available(iOS 17.0, *) else { return false }
        guard object.responds(to: #selector(NSObject.accessibilityActivateBlock)) else {
            return false
        }
        return object.accessibilityActivateBlock != nil
    }

    private static func overridesAccessibilityActivate(_ object: NSObject) -> Bool {
        AXMethodOverrides.object(object, overrides: #selector(NSObject.accessibilityActivate))
    }

    /// Check if an element is interactive based on its parsed accessibility data.
    static func isInteractive(element: AccessibilityElement) -> Bool {
        element.projectedActionSet.actions.contains(.activate)
    }

    /// Enforce advertised disabled state and derive advisory diagnostics. Runtime
    /// implementation introspection can suppress a weak-target warning, but can
    /// never block dispatch.
    static func checkInteractivity(_ element: AccessibilityElement, object: NSObject? = nil) -> InteractivityCheck {
        if element.traits.contains(.notEnabled) {
            return .blocked(reason: "Element is disabled (has 'notEnabled' trait)")
        }

        let implementsActivation = implementsAccessibilityActivation(object)
        let staticTraitsOnly = element.traits.isSubset(of: AccessibilityPolicy.staticOnlyTraitsBitmask)
        let warning: String? = (
            staticTraitsOnly
                && !implementsActivation
                && !hasInteractiveTraits(element)
                && element.customActions.isEmpty
        )
            ? "Target advertised no interactivity and implements no activation; "
                + "proceeding as VoiceOver would"
            : nil

        return .interactive(warning: warning)
    }

    }
}

#endif // DEBUG
#endif // canImport(UIKit)
