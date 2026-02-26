#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

extension TheSafecracker {

    // MARK: - Element Resolution

    func findElement(for target: ActionTarget) -> AccessibilityElement? {
        guard let store = elementStore else { return nil }
        if let identifier = target.identifier {
            return store.cachedElements.first { $0.identifier == identifier }
        }
        if let index = target.order, index >= 0, index < store.cachedElements.count {
            return store.cachedElements[index]
        }
        return nil
    }

    /// Check if an element is interactive based on traits.
    /// Returns nil if interactive, or an error string if not.
    func checkElementInteractivity(_ element: AccessibilityElement) -> String? {
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

    func resolveTraversalIndex(for target: ActionTarget) -> Int? {
        guard let store = elementStore else { return nil }
        if let index = target.order {
            return index
        }
        if let identifier = target.identifier {
            return store.cachedElements.firstIndex { $0.identifier == identifier }
        }
        return nil
    }

    // MARK: - Interactive Object Access

    func hasInteractiveObject(at index: Int) -> Bool {
        elementStore?.interactiveObjects[index]?.object != nil
    }

    func customActionNames(elementAt index: Int) -> [String] {
        elementStore?.interactiveObjects[index]?.object?.accessibilityCustomActions?.map { $0.name } ?? []
    }

    // MARK: - Direct Accessibility Actions

    func activate(elementAt index: Int) -> Bool {
        elementStore?.interactiveObjects[index]?.object?.accessibilityActivate() ?? false
    }

    func increment(elementAt index: Int) {
        elementStore?.interactiveObjects[index]?.object?.accessibilityIncrement()
    }

    func decrement(elementAt index: Int) {
        elementStore?.interactiveObjects[index]?.object?.accessibilityDecrement()
    }

    func performCustomAction(named name: String, elementAt index: Int) -> Bool {
        guard let actions = elementStore?.interactiveObjects[index]?.object?.accessibilityCustomActions else {
            return false
        }
        for action in actions where action.name == name {
            if let handler = action.actionHandler {
                return handler(action)
            }
            if let target = action.target {
                _ = (target as AnyObject).perform(action.selector, with: action)
                return true
            }
        }
        return false
    }

    // MARK: - Point Resolution

    /// Resolve a screen point from an element target or explicit coordinates.
    func resolvePoint(
        from elementTarget: ActionTarget?,
        pointX: Double?,
        pointY: Double?
    ) -> Result<CGPoint, InteractionResult> {
        if let elementTarget {
            guard let element = findElement(for: elementTarget) else {
                return .failure(.failure(.elementNotFound, message: "Element not found"))
            }
            return .success(element.activationPoint)
        } else if let x = pointX, let y = pointY {
            return .success(CGPoint(x: x, y: y))
        } else {
            return .failure(.failure(.elementNotFound, message: "No target specified"))
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
