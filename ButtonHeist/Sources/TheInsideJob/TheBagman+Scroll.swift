#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Scroll Orchestration
//
// TheBagman finds scrollable containers from the accessibility hierarchy and
// drives TheSafecracker's scroll primitives. Two paths:
//
//   UIScrollView → setContentOffset (fast, precise)
//   Any scrollable → synthetic swipe gesture (universal fallback)
//
// The accessibility hierarchy marks containers as .scrollable with their
// contentSize. When the backing view is a UIScrollView, we manipulate it
// directly. When it's not (e.g. SwiftUI's PlatformContainer), we swipe.

extension TheBagman {

    /// A scrollable container discovered from the accessibility hierarchy.
    /// UIScrollView → direct setContentOffset. Everything else → synthetic swipe.
    @MainActor enum ScrollableTarget {
        case uiScrollView(UIScrollView)
        case swipeable(frame: CGRect, contentSize: CGSize)

        var frame: CGRect {
            switch self {
            case .uiScrollView(let sv): return sv.frame
            case .swipeable(let frame, _): return frame
            }
        }

        var contentSize: CGSize {
            switch self {
            case .uiScrollView(let sv): return sv.contentSize
            case .swipeable(_, let cs): return cs
            }
        }
    }

    // MARK: - Scroll Axis Detection

    struct ScrollAxis: OptionSet, Sendable {
        let rawValue: Int
        static let horizontal = ScrollAxis(rawValue: 1 << 0)
        static let vertical   = ScrollAxis(rawValue: 1 << 1)
    }

    func scrollableAxis(of scrollView: UIScrollView) -> ScrollAxis {
        scrollableAxis(of: .uiScrollView(scrollView))
    }

    func scrollableAxis(of target: ScrollableTarget) -> ScrollAxis {
        var axis: ScrollAxis = []
        if target.contentSize.width > target.frame.width { axis.insert(.horizontal) }
        if target.contentSize.height > target.frame.height { axis.insert(.vertical) }
        return axis
    }

    func requiredAxis(for direction: ScrollDirection) -> ScrollAxis {
        switch direction {
        case .up, .down, .next, .previous: return .vertical
        case .left, .right: return .horizontal
        }
    }

    func requiredAxis(for edge: ScrollEdge) -> ScrollAxis {
        switch edge {
        case .top, .bottom: return .vertical
        case .left, .right: return .horizontal
        }
    }

    func requiredAxis(for direction: ScrollSearchDirection) -> ScrollAxis {
        switch direction {
        case .up, .down: return .vertical
        case .left, .right: return .horizontal
        }
    }

    // MARK: - Unified Scroll Dispatch

    /// Scroll a target by one page.
    /// UIScrollView → setContentOffset (fast, precise, returns false at edge).
    /// Everything else → synthetic swipe (universal, always returns true).
    func scrollOnePage(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) async -> Bool {
        guard let safecracker else { return false }
        switch target {
        case .uiScrollView(let sv):
            return safecracker.scrollByPage(sv, direction: direction, animated: animated)
        case .swipeable(let frame, _):
            return await safecracker.scrollBySwipe(frame: frame, direction: direction)
        }
    }

    // MARK: - Scroll Command Execution

    func executeScroll(_ target: ScrollTarget) async -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scroll, message: "Element target required for scroll")
        }
        let resolution = resolveTarget(elementTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }
        guard let scrollTarget = resolveScrollTarget(
            screenElement: resolved.screenElement
        ) else {
            return .failure(.scroll, message: "No scrollable ancestor found for element")
        }

        let uiDirection = uiScrollDirection(for: target.direction)
        let success = await scrollOnePage(scrollTarget, direction: uiDirection)
        return TheSafecracker.InteractionResult(
            success: success, method: .scroll,
            message: success ? nil : "Already at edge",
            value: nil
        )
    }

    func executeScrollToEdge(_ target: ScrollToEdgeTarget) async -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scrollToEdge, message: "Element target required for scroll_to_edge")
        }
        let resolution = resolveTarget(elementTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }
        guard let scrollTarget = resolveScrollTarget(
            screenElement: resolved.screenElement
        ) else {
            return .failure(.scrollToEdge, message: "No scrollable ancestor found for element")
        }

        // Scroll repeatedly in the edge direction until no more movement.
        // scrollByPage returns false at edge for UIScrollViews.
        // For swipe-based targets (always return true), stagnation (no new
        // elements) is the fallback termination signal.
        let direction = edgeDirection(for: target.edge)
        var moved = false
        for _ in 0..<50 {
            let before = onScreen
            let stepped = await scrollOnePage(scrollTarget, direction: direction, animated: false)
            if !stepped { break }
            moved = true
            await tripwire.yieldFrames(2)
            refreshAccessibilityData()
            if onScreen == before { break }
        }

        return TheSafecracker.InteractionResult(
            success: moved, method: .scrollToEdge,
            message: moved ? nil : "Already at edge",
            value: nil
        )
    }

    private func edgeDirection(for edge: ScrollEdge) -> UIAccessibilityScrollDirection {
        switch edge {
        case .top: return .up
        case .bottom: return .down
        case .left: return .left
        case .right: return .right
        }
    }

    func executeScrollToVisible(_ target: ScrollToVisibleTarget) async -> TheSafecracker.InteractionResult {
        guard let searchTarget = target.elementTarget else {
            return .failure(.scrollToVisible, message: "Element target required for scroll_to_visible")
        }
        let maxScrolls = target.resolvedMaxScrolls
        let searchDirection = target.resolvedDirection

        // Already visible?
        refreshAccessibilityData()
        if let found = resolveFirstMatch(searchTarget) {
            ensureOnScreenSync(found)
            return foundResult(found, scrollCount: 0)
        }

        guard safecracker != nil else {
            return .failure(.scrollToVisible, message: "No gesture engine available")
        }

        // Walk the hierarchy tree for scrollable containers (outermost first).
        // Scroll each one in its natural axis until no new elements appear, then
        // move to the next. After each scroll, re-walk the tree so newly-revealed
        // containers get picked up. maxScrolls is a safety valve, not a budget.
        // Exhaustion is keyed by AccessibilityContainer (Hashable, value-type) so
        // it survives hierarchy rebuilds — no positional index drift.
        var exhausted = Set<AccessibilityContainer>()
        var scrollCount = 0

        while scrollCount < maxScrolls {
            guard let (scrollTarget, container) = findLiveScrollTarget(excluding: exhausted) else { break }

            let dir = adaptDirection(searchDirection, for: scrollTarget)
            let before = onScreen
            let moved = await scrollOnePage(scrollTarget, direction: dir, animated: false)

            if !moved { exhausted.insert(container); continue }

            await tripwire.yieldFrames(3)
            refreshAccessibilityData()

            if let found = resolveFirstMatch(searchTarget) {
                ensureOnScreenSync(found)
                scrollCount += 1
                return foundResult(found, scrollCount: scrollCount)
            }

            // No new elements → this container is exhausted in this direction
            if onScreen == before {
                exhausted.insert(container)
            } else {
                scrollCount += 1
            }
        }

        return notFoundResult(scrollCount: scrollCount)
    }

    /// Walk the cached hierarchy tree (pre-order = outermost first) and return the
    /// first non-exhausted scrollable container as a `ScrollableTarget`.
    private func findLiveScrollTarget(
        excluding exhausted: Set<AccessibilityContainer>
    ) -> (target: ScrollableTarget, container: AccessibilityContainer)? {
        cachedHierarchy.reducedHierarchy(nil as (ScrollableTarget, AccessibilityContainer)?) { found, node in
            guard found == nil else { return found }
            guard case .container(let container, _) = node,
                  case .scrollable(let contentSize) = container.type,
                  !exhausted.contains(container) else { return nil }
            if let sv = scrollableContainerViews[container] as? UIScrollView, sv.window != nil {
                return (.uiScrollView(sv), container)
            }
            return (.swipeable(frame: container.frame, contentSize: contentSize), container)
        }
    }

    private func notFoundResult(scrollCount: Int) -> TheSafecracker.InteractionResult {
        TheSafecracker.InteractionResult(
            success: false, method: .scrollToVisible,
            message: "Element not found after \(scrollCount) scrolls", value: nil,
            scrollSearchResult: ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: screenElements.count,
                totalItems: nil, exhaustive: true
            )
        )
    }

    private func foundResult(_ found: ResolvedTarget, scrollCount: Int) -> TheSafecracker.InteractionResult {
        let wireElement = convertAndAssignId(found.element, index: found.traversalIndex)
        return TheSafecracker.InteractionResult(
            success: true, method: .scrollToVisible, message: nil, value: nil,
            scrollSearchResult: ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: screenElements.count,
                totalItems: nil, exhaustive: false, foundElement: wireElement
            )
        )
    }

    // MARK: - Ensure On Screen

    func ensureOnScreen(for target: ElementTarget) async {
        guard let resolved = resolveTarget(target).resolved,
              let object = resolved.screenElement.object else { return }
        let frame = object.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return }
        guard !UIScreen.main.bounds.contains(frame) else { return }
        guard let scrollView = resolved.screenElement.scrollView,
              let safecracker else { return }
        if safecracker.scrollToMakeVisible(frame, in: scrollView) {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            refreshAccessibilityData()
        }
    }

    func ensureFirstResponderOnScreen() async {
        guard let responder = tripwire.currentFirstResponder() else { return }
        let frame = responder.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return }
        guard !UIScreen.main.bounds.contains(frame) else { return }
        // Find the responder in screenElements to get its hierarchy scroll view
        guard let scrollView = screenElements.values
            .first(where: { $0.object === responder })?.scrollView,
              let safecracker else { return }
        if safecracker.scrollToMakeVisible(frame, in: scrollView) {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            refreshAccessibilityData()
        }
    }

    private func ensureOnScreenSync(_ resolved: ResolvedTarget) {
        guard let object = resolved.screenElement.object,
              let safecracker else { return }
        let frame = object.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return }
        guard !UIScreen.main.bounds.contains(frame) else { return }
        guard let scrollView = resolved.screenElement.scrollView else { return }
        _ = safecracker.scrollToMakeVisible(frame, in: scrollView)
    }

    // MARK: - Scroll Target Resolution (Accessibility Hierarchy)

    /// Find the scrollable container for a resolved element from the accessibility hierarchy.
    /// Uses the element's stored `scrollView` ref (set by the hierarchy tree's containerVisitor).
    func resolveScrollTarget(
        screenElement: ScreenElement
    ) -> ScrollableTarget? {
        guard let sv = screenElement.scrollView else { return nil }
        return .uiScrollView(sv)
    }

    // MARK: - Direction Mapping

    func uiScrollDirection(for direction: ScrollSearchDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .down: return .down
        case .up: return .up
        case .left: return .left
        case .right: return .right
        }
    }

    func uiScrollDirection(for direction: ScrollDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .next: return .next
        case .previous: return .previous
        }
    }

    /// Map a search direction to the appropriate scroll direction for a specific scroll view.
    /// "Down" means "forward" — forward in a vertical scroll view = down, forward in a
    /// horizontal scroll view = right. This lets scroll_to_visible search every scroll view
    /// in its natural axis regardless of the caller's direction hint.
    func adaptDirection(
        _ direction: ScrollSearchDirection,
        for target: ScrollableTarget
    ) -> UIAccessibilityScrollDirection {
        let axis = scrollableAxis(of: target)
        let requested = requiredAxis(for: direction)
        if axis.contains(requested) { return uiScrollDirection(for: direction) }

        let isForward = direction == .down || direction == .right
        if axis.contains(.horizontal) { return isForward ? .right : .left }
        if axis.contains(.vertical) { return isForward ? .down : .up }

        return uiScrollDirection(for: direction)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
