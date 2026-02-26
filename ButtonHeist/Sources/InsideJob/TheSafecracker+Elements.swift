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
        guard let store = elementStore,
              store.elementObjects[index]?.object != nil,
              index >= 0, index < store.cachedElements.count else { return false }
        let el = store.cachedElements[index]
        return el.respondsToUserInteraction
            || el.traits.contains(.adjustable)
            || !el.customActions.isEmpty
    }

    func customActionNames(elementAt index: Int) -> [String] {
        elementStore?.elementObjects[index]?.object?.accessibilityCustomActions?.map { $0.name } ?? []
    }

    // MARK: - Direct Accessibility Actions

    func activate(elementAt index: Int) -> Bool {
        elementStore?.elementObjects[index]?.object?.accessibilityActivate() ?? false
    }

    func increment(elementAt index: Int) {
        elementStore?.elementObjects[index]?.object?.accessibilityIncrement()
    }

    func decrement(elementAt index: Int) {
        elementStore?.elementObjects[index]?.object?.accessibilityDecrement()
    }

    func performCustomAction(named name: String, elementAt index: Int) -> Bool {
        guard let actions = elementStore?.elementObjects[index]?.object?.accessibilityCustomActions else {
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

    // MARK: - Accessibility Scroll

    /// Walk the view/container hierarchy from an element to find the nearest
    /// scrollable UIScrollView ancestor, then scroll it by one page via `setContentOffset`.
    ///
    /// SwiftUI overrides `accessibilityScroll` to return false on its internal
    /// collection/scroll views, so we use direct `setContentOffset` (KIF approach).
    func scroll(elementAt index: Int, direction: UIAccessibilityScrollDirection) -> Bool {
        guard let object = elementStore?.elementObjects[index]?.object else {
            return false
        }

        var current: NSObject? = object
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.isScrollEnabled {
                return scrollByPage(scrollView, direction: direction)
            }
            current = nextAncestor(of: candidate)
        }
        return false
    }

    /// Scroll a UIScrollView by approximately one page in the given direction.
    private func scrollByPage(_ scrollView: UIScrollView, direction: UIAccessibilityScrollDirection) -> Bool {
        let overlap: CGFloat = 44 // keep some context visible
        let size = scrollView.frame.size
        let offset = scrollView.contentOffset
        let contentSize = scrollView.contentSize
        let insets = scrollView.adjustedContentInset

        var newOffset = offset

        switch direction {
        case .up:
            // Reveal content below: move content offset down
            newOffset.y = min(offset.y + size.height - overlap,
                             contentSize.height + insets.bottom - size.height)
        case .down:
            // Reveal content above: move content offset up
            newOffset.y = max(offset.y - (size.height - overlap),
                             -insets.top)
        case .left:
            // Reveal content to the right
            newOffset.x = min(offset.x + size.width - overlap,
                             contentSize.width + insets.right - size.width)
        case .right:
            // Reveal content to the left
            newOffset.x = max(offset.x - (size.width - overlap),
                             -insets.left)
        case .next:
            // Same as .up (reveal next page)
            newOffset.y = min(offset.y + size.height - overlap,
                             contentSize.height + insets.bottom - size.height)
        case .previous:
            // Same as .down (reveal previous page)
            newOffset.y = max(offset.y - (size.height - overlap),
                             -insets.top)
        @unknown default:
            return false
        }

        // If offset didn't change, we're already at the boundary
        if newOffset.x == offset.x && newOffset.y == offset.y {
            return false
        }

        scrollView.setContentOffset(newOffset, animated: true)
        return true
    }

    /// Scroll the nearest UIScrollView ancestor so the element's accessibility frame
    /// is fully visible within the scroll view's viewport.
    func scrollToVisible(elementAt index: Int) -> Bool {
        guard let object = elementStore?.elementObjects[index]?.object else {
            return false
        }

        // Get the element's frame in screen coordinates
        let elementFrame = object.accessibilityFrame
        guard !elementFrame.isNull && !elementFrame.isEmpty else {
            return false
        }

        // Walk up to find the nearest scrollable UIScrollView
        var current: NSObject? = object
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.isScrollEnabled {
                return scrollToMakeVisible(elementFrame, in: scrollView)
            }
            current = nextAncestor(of: candidate)
        }
        return false
    }

    /// Adjust a scroll view's content offset so that `targetFrame` (in screen coordinates)
    /// is fully visible within the scroll view's visible rect.
    private func scrollToMakeVisible(_ targetFrame: CGRect, in scrollView: UIScrollView) -> Bool {
        // Convert the element's screen-space frame into the scroll view's coordinate space
        let targetInScrollView = scrollView.convert(targetFrame, from: nil)

        let visibleRect = CGRect(
            x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
            y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top,
            width: scrollView.frame.width - scrollView.adjustedContentInset.left - scrollView.adjustedContentInset.right,
            height: scrollView.frame.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom
        )

        // Already fully visible
        if visibleRect.contains(targetInScrollView) {
            return true
        }

        var newOffset = scrollView.contentOffset

        // Horizontal adjustment
        if targetInScrollView.minX < visibleRect.minX {
            newOffset.x -= visibleRect.minX - targetInScrollView.minX
        } else if targetInScrollView.maxX > visibleRect.maxX {
            newOffset.x += targetInScrollView.maxX - visibleRect.maxX
        }

        // Vertical adjustment
        if targetInScrollView.minY < visibleRect.minY {
            newOffset.y -= visibleRect.minY - targetInScrollView.minY
        } else if targetInScrollView.maxY > visibleRect.maxY {
            newOffset.y += targetInScrollView.maxY - visibleRect.maxY
        }

        // Clamp to valid content bounds
        let insets = scrollView.adjustedContentInset
        let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
        let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        newOffset.x = max(-insets.left, min(newOffset.x, maxX))
        newOffset.y = max(-insets.top, min(newOffset.y, maxY))

        if newOffset.x == scrollView.contentOffset.x && newOffset.y == scrollView.contentOffset.y {
            return true // Already at best position
        }

        scrollView.setContentOffset(newOffset, animated: true)
        return true
    }

    /// Scroll the nearest UIScrollView ancestor to an edge.
    func scrollToEdge(elementAt index: Int, edge: ScrollEdge) -> Bool {
        guard let object = elementStore?.elementObjects[index]?.object else {
            return false
        }

        var current: NSObject? = object
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.isScrollEnabled {
                let insets = scrollView.adjustedContentInset
                var newOffset = scrollView.contentOffset

                switch edge {
                case .top:
                    newOffset.y = -insets.top
                case .bottom:
                    newOffset.y = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
                case .left:
                    newOffset.x = -insets.left
                case .right:
                    newOffset.x = scrollView.contentSize.width + insets.right - scrollView.frame.width
                }

                if newOffset.x == scrollView.contentOffset.x && newOffset.y == scrollView.contentOffset.y {
                    return true
                }
                scrollView.setContentOffset(newOffset, animated: true)
                return true
            }
            current = nextAncestor(of: candidate)
        }
        return false
    }

    /// Walk up one level in the view/container hierarchy.
    private func nextAncestor(of candidate: NSObject) -> NSObject? {
        if let view = candidate as? UIView {
            return view.superview
        } else if let element = candidate as? UIAccessibilityElement {
            return element.accessibilityContainer as? NSObject
        } else if candidate.responds(to: Selector(("accessibilityContainer"))) {
            // SwiftUI proxy types (e.g. SwiftUI.AccessibilityNode)
            return candidate.value(forKey: "accessibilityContainer") as? NSObject
        }
        return nil
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
