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
    /// Three tiers: UIScrollView (direct offset), accessibilityScroll (VoiceOver page),
    /// swipe gesture (universal fallback).
    @MainActor enum ScrollableTarget {
        case uiScrollView(UIScrollView)
        case accessibilityScrollable(view: UIView, contentSize: CGSize)
        case swipeable(frame: CGRect, contentSize: CGSize)

        var frame: CGRect {
            switch self {
            case .uiScrollView(let sv): return sv.frame
            case .accessibilityScrollable(let v, _): return v.frame
            case .swipeable(let frame, _): return frame
            }
        }

        var contentSize: CGSize {
            switch self {
            case .uiScrollView(let sv): return sv.contentSize
            case .accessibilityScrollable(_, let cs): return cs
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
        scrollableAxis(frame: scrollView.frame.size, content: scrollView.contentSize)
    }

    func scrollableAxis(of target: ScrollableTarget) -> ScrollAxis {
        scrollableAxis(frame: target.frame.size, content: target.contentSize)
    }

    private func scrollableAxis(frame: CGSize, content: CGSize) -> ScrollAxis {
        var axis: ScrollAxis = []
        if content.width > frame.width { axis.insert(.horizontal) }
        if content.height > frame.height { axis.insert(.vertical) }
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

    /// Scroll a target by one page. Three tiers:
    /// 1. UIScrollView → setContentOffset (fast, precise)
    /// 2. accessibilityScroll: → VoiceOver page scroll (works on any scrollable view)
    /// 3. Synthetic swipe → universal fallback
    /// accessibilityScroll: falls through to swipe on failure since some views
    /// respond to the selector but return NO (SwiftUI PlatformContainer).
    func scrollOnePage(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) async -> Bool {
        guard let safecracker else { return false }
        switch target {
        case .uiScrollView(let sv):
            return safecracker.scrollByPage(sv, direction: direction, animated: animated)
        case .accessibilityScrollable(let view, _):
            if view.accessibilityScroll(direction) { return true }
            // accessibilityScroll: returned NO — fall back to swipe at the view's frame
            let screenFrame = view.convert(view.bounds, to: nil)
            return await safecracker.scrollBySwipe(frame: screenFrame, direction: direction)
        case .swipeable(let frame, _):
            return await safecracker.scrollBySwipe(frame: frame, direction: direction)
        }
    }

    // MARK: - Scroll Command Execution

    func executeScroll(_ target: ScrollTarget) -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scroll, message: "Element target required for scroll")
        }
        let resolution = resolveTarget(elementTarget)
        guard let resolved = resolution.resolved else {
            return .failure(.elementNotFound, message: resolution.diagnostics)
        }
        let axis = requiredAxis(for: target.direction)
        guard let object = resolved.screenElement.object,
              let scrollView = resolveScrollView(
                  heistId: target.scrollViewHeistId, element: object,
                  screenElement: resolved.screenElement, includeSelf: true, axis: axis
              ),
              let safecracker else {
            return .failure(.scroll, message: "No scrollable ancestor found for element")
        }

        let uiDirection = uiScrollDirection(for: target.direction)
        let success = safecracker.scrollByPage(scrollView, direction: uiDirection)
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
        let axis = requiredAxis(for: target.edge)
        guard let object = resolved.screenElement.object,
              let scrollView = resolveScrollView(
                  heistId: target.scrollViewHeistId, element: object,
                  screenElement: resolved.screenElement, includeSelf: true, axis: axis
              ),
              let safecracker else {
            return .failure(.scrollToEdge, message: "No scrollable ancestor found for element")
        }

        let success = safecracker.scrollToEdge(scrollView, edge: target.edge)

        // Content may grow after the jump (lazy containers materialise on
        // scroll). Yield a couple of frames, then re-jump until contentSize
        // stops changing.
        if success {
            for _ in 0..<20 {
                await tripwire.yieldFrames(2)
                let prev = scrollView.contentSize
                let moved = safecracker.scrollToEdge(scrollView, edge: target.edge)
                if moved { await tripwire.yieldFrames(2) }
                if !moved && scrollView.contentSize == prev { break }
            }
        }

        return TheSafecracker.InteractionResult(
            success: success, method: .scrollToEdge,
            message: success ? nil : "Already at edge",
            value: nil
        )
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
        var exhausted = Set<Int>()
        var scrollCount = 0

        while scrollCount < maxScrolls {
            guard let (target, idx) = findLiveScrollTarget(excluding: exhausted) else { break }

            let dir = adaptDirection(searchDirection, for: target)
            let before = onScreen
            let moved = await scrollOnePage(target, direction: dir, animated: false)

            if !moved { exhausted.insert(idx); continue }

            await tripwire.yieldFrames(3)
            scrollCount += 1
            refreshAccessibilityData()

            if let found = resolveFirstMatch(searchTarget) {
                ensureOnScreenSync(found)
                return foundResult(found, scrollCount: scrollCount)
            }

            // No new elements → this container is exhausted in this direction
            if onScreen == before { exhausted.insert(idx) }
        }

        return notFoundResult(scrollCount: scrollCount)
    }

    /// Walk the cached hierarchy tree (pre-order = outermost first) and return the
    /// first non-exhausted scrollable container as a `ScrollableTarget`.
    private func findLiveScrollTarget(
        excluding exhausted: Set<Int>
    ) -> (target: ScrollableTarget, index: Int)? {
        struct State {
            var index = 0
            var first: (ScrollableTarget, Int)?
        }
        let state = cachedHierarchy.reducedHierarchy(State()) { state, node in
            var state = state
            guard state.first == nil else { return state }
            guard case .container(let container, _) = node,
                  case .scrollable(let contentSize) = container.type else { return state }
            let thisIndex = state.index
            state.index += 1
            guard !exhausted.contains(thisIndex) else { return state }
            if let sv = scrollViewLookup[container], sv.window != nil {
                state.first = (.uiScrollView(sv), thisIndex)
            } else if let view = scrollableViewLookup[container], view.window != nil {
                state.first = (.accessibilityScrollable(view: view, contentSize: contentSize), thisIndex)
            } else {
                state.first = (.swipeable(frame: container.frame, contentSize: contentSize), thisIndex)
            }
            return state
        }
        return state.first
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
        guard let scrollView = resolved.screenElement.scrollView ?? scrollableAncestor(of: object, includeSelf: false),
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
        guard let scrollView = scrollableAncestor(of: responder, includeSelf: false),
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
        guard let scrollView = resolved.screenElement.scrollView ?? scrollableAncestor(of: object, includeSelf: false) else { return }
        _ = safecracker.scrollToMakeVisible(frame, in: scrollView)
    }

    // MARK: - Scroll View Discovery

    /// Return all unique scroll views reachable from on-screen elements, innermost first.
    /// De-duplicates by identity so each UIScrollView appears only once.
    func findAllScrollViews() -> [UIScrollView] {
        var seen = Set<ObjectIdentifier>()
        var result: [UIScrollView] = []
        for (heistId, entry) in screenElements where onScreen.contains(heistId) {
            guard let object = entry.object else { continue }
            for sv in scrollableAncestors(of: object, includeSelf: true) {
                let id = ObjectIdentifier(sv)
                if seen.insert(id).inserted {
                    result.append(sv)
                }
            }
        }
        return result
    }

    /// Return all unique scroll views, outermost first.
    /// Used by scroll_to_visible: the outer scroll view reveals new sections
    /// (and their inner carousels), so exhaust the outer dimension first.
    func findAllScrollViewsOutermostFirst() -> [UIScrollView] {
        findAllScrollViews().reversed()
    }

    func scrollableAncestor(of object: NSObject, includeSelf: Bool) -> UIScrollView? {
        scrollableAncestors(of: object, includeSelf: includeSelf).first
    }

    /// Return ALL scrollable ancestors, innermost first.
    func scrollableAncestors(of object: NSObject, includeSelf: Bool) -> [UIScrollView] {
        var ancestors: [UIScrollView] = []
        var current: NSObject? = includeSelf ? object : nextAncestor(of: object)
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView, scrollView.isScrollEnabled {
                ancestors.append(scrollView)
            }
            current = nextAncestor(of: candidate)
        }
        return ancestors
    }

    /// Resolve an explicit scroll view by heistId, or fall back to axis-aware ancestor discovery.
    /// When `axis` is provided and no `heistId` is specified, returns the first ancestor
    /// whose content is scrollable along the requested axis. Falls back to the accessibility
    /// hierarchy's stored scroll view, then to the innermost ancestor.
    func resolveScrollView(
        heistId: String?,
        element: NSObject,
        screenElement: ScreenElement? = nil,
        includeSelf: Bool,
        axis: ScrollAxis? = nil
    ) -> UIScrollView? {
        if let heistId, let entry = screenElements[heistId], let obj = entry.object {
            return obj as? UIScrollView ?? scrollableAncestor(of: obj, includeSelf: true)
        }
        let ancestors = scrollableAncestors(of: element, includeSelf: includeSelf)
        if let axis {
            if let match = ancestors.first(where: { scrollableAxis(of: $0).contains(axis) }) {
                return match
            }
        }
        // Fall back to the accessibility hierarchy's scroll view, then any ancestor.
        return ancestors.first ?? screenElement?.scrollView
    }

    private func nextAncestor(of candidate: NSObject) -> NSObject? {
        if let view = candidate as? UIView { return view.superview }
        if let element = candidate as? UIAccessibilityElement {
            return element.accessibilityContainer as? NSObject
        }
        if candidate.responds(to: Selector(("accessibilityContainer"))) {
            return candidate.value(forKey: "accessibilityContainer") as? NSObject
        }
        return nil
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
