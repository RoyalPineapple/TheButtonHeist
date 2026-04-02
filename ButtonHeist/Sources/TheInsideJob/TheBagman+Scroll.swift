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
    /// UIScrollView → direct setContentOffset. swipeable → synthetic swipe (no UIScrollView ref).
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

    static func scrollableAxis(of target: ScrollableTarget) -> ScrollAxis {
        var axis: ScrollAxis = []
        if target.contentSize.width > target.frame.width { axis.insert(.horizontal) }
        if target.contentSize.height > target.frame.height { axis.insert(.vertical) }
        return axis
    }

    static func requiredAxis(for direction: ScrollDirection) -> ScrollAxis {
        switch direction {
        case .up, .down, .next, .previous: return .vertical
        case .left, .right: return .horizontal
        }
    }

    static func requiredAxis(for edge: ScrollEdge) -> ScrollAxis {
        switch edge {
        case .top, .bottom: return .vertical
        case .left, .right: return .horizontal
        }
    }

    static func requiredAxis(for direction: ScrollSearchDirection) -> ScrollAxis {
        switch direction {
        case .up, .down: return .vertical
        case .left, .right: return .horizontal
        }
    }

    // MARK: - Unified Scroll Dispatch

    /// Scroll a target by one page, wait for layout to settle, and refresh
    /// the accessibility tree. Both UIScrollView and swipeable paths end in
    /// a consistent settled state — one yield + one refresh.
    /// Returns whether the scroll moved and the onScreen set from before the scroll.
    private func scrollOnePageAndSettle(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = false
    ) async -> (moved: Bool, previousOnScreen: Set<String>) {
        let before = onScreen
        guard let safecracker else { return (false, before) }

        switch target {
        case .uiScrollView(let sv):
            let moved = safecracker.scrollByPage(sv, direction: direction, animated: animated)
            guard moved else { return (false, before) }
            await tripwire.yieldFrames(3)
            refresh()
            return (true, before)
        case .swipeable(let frame, _):
            _ = await safecracker.scrollBySwipe(frame: frame, direction: direction)
            await tripwire.yieldFrames(3)
            refresh()
            return (onScreen != before, before)
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
        let axis = Self.requiredAxis(for: target.direction)
        guard let scrollTarget = resolveScrollTarget(
            screenElement: resolved.screenElement, axis: axis
        ) else {
            return .failure(.scroll, message: "No scrollable ancestor found for element")
        }

        let uiDirection = Self.uiScrollDirection(for: target.direction)
        let (success, _) = await scrollOnePageAndSettle(scrollTarget, direction: uiDirection)
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
        let axis = Self.requiredAxis(for: target.edge)
        guard let scrollTarget = resolveScrollTarget(
            screenElement: resolved.screenElement, axis: axis
        ) else {
            return .failure(.scrollToEdge, message: "No scrollable ancestor found for element")
        }

        let moved: Bool
        switch scrollTarget {
        case .uiScrollView(let sv):
            guard let safecracker else { return .failure(.scrollToEdge, message: "No gesture engine") }
            moved = safecracker.scrollToEdge(sv, edge: target.edge)
        case .swipeable:
            let direction = Self.edgeDirection(for: target.edge)
            var didMove = false
            for _ in 0..<50 {
                let (stepped, before) = await scrollOnePageAndSettle(
                    scrollTarget, direction: direction
                )
                if !stepped { break }
                didMove = true
                if onScreen == before { break }
            }
            moved = didMove
        }

        return TheSafecracker.InteractionResult(
            success: moved, method: .scrollToEdge,
            message: moved ? nil : "Already at edge",
            value: nil
        )
    }

    private static func edgeDirection(for edge: ScrollEdge) -> UIAccessibilityScrollDirection {
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
        let searchDirection = target.resolvedDirection

        // Already visible?
        refresh()
        if let found = resolveFirstMatch(searchTarget) {
            ensureOnScreenSync(found)
            return foundResult(found, scrollCount: 0)
        }

        guard safecracker != nil else {
            return .failure(.scrollToVisible, message: "No gesture engine available")
        }

        // Fast path: if the element was discovered by a prior full scan, use its
        // cached content-space position to jump directly instead of page-by-page search.
        if case .heistId(let heistId) = searchTarget,
           let entry = screenElements[heistId], presentedHeistIds.contains(heistId),
           let origin = entry.contentSpaceOrigin,
           let scrollView = entry.scrollView {
            let savedOffset = scrollView.contentOffset
            let targetOffset = Self.scrollTargetOffset(for: origin, in: scrollView)
            scrollView.setContentOffset(targetOffset, animated: false)
            await tripwire.yieldFrames(3)
            refresh()
            if let found = resolveFirstMatch(searchTarget),
               let result = await fineTuneAndResolve(found, searchTarget: searchTarget, scrollCount: 1) {
                return result
            }
            // Fast path failed — restore original scroll position so the slow
            // page-by-page search starts from where the user left off.
            scrollView.setContentOffset(savedOffset, animated: false)
            await tripwire.yieldFrames(3)
            refresh()
        }

        // Walk the hierarchy tree for scrollable containers (outermost first).
        // Scroll each one in its natural axis until no new elements appear,
        // then move to the next. Re-walks the tree after each scroll so
        // newly-revealed containers get picked up.
        // Exhaustion keyed by AccessibilityContainer (Hashable value type) —
        // uses type + frame for identity. Stable within a single search;
        // no ObjectIdentifier (cell reuse invalidates pointer identity).
        var exhausted = Set<AccessibilityContainer>()
        var scrollCount = 0
        // Hard cap prevents infinite loops on swipeable containers (which always
        // report moved=true) with infinite/paginated content (onScreen always changes).
        let maxScrolls = 200

        while scrollCount < maxScrolls {
            guard let (scrollTarget, container) = findScrollTarget(excluding: exhausted) else { break }

            let direction = Self.adaptDirection(searchDirection, for: scrollTarget)
            let (moved, before) = await scrollOnePageAndSettle(
                scrollTarget, direction: direction
            )

            if !moved { exhausted.insert(container); continue }

            scrollCount += 1

            if let found = resolveFirstMatch(searchTarget) {
                if let result = await fineTuneAndResolve(found, searchTarget: searchTarget, scrollCount: scrollCount) {
                    return result
                }
                return foundResult(found, scrollCount: scrollCount)
            }

            if onScreen == before { exhausted.insert(container) }
        }

        return notFoundResult(scrollCount: scrollCount)
    }

    /// Fine-tune a found element's position and re-resolve to get fresh coordinates.
    private func fineTuneAndResolve(
        _ found: ResolvedTarget,
        searchTarget: ElementTarget,
        scrollCount: Int
    ) async -> TheSafecracker.InteractionResult? {
        ensureOnScreenSync(found, animated: false)
        await tripwire.yieldFrames(3)
        refresh()
        guard let fresh = resolveFirstMatch(searchTarget) else { return nil }
        return foundResult(fresh, scrollCount: scrollCount)
    }

    /// Walk the cached hierarchy tree (pre-order = outermost first) and return the
    /// first scrollable container matching the criteria as a `ScrollableTarget`.
    /// Optionally filters by axis and excludes already-exhausted containers.
    private func findScrollTarget(
        axis: ScrollAxis? = nil,
        excluding exhausted: Set<AccessibilityContainer> = []
    ) -> (target: ScrollableTarget, container: AccessibilityContainer)? {
        currentHierarchy.reducedHierarchy(
            nil as (ScrollableTarget, AccessibilityContainer)?
        ) { found, node in
            guard found == nil else { return found }
            guard case .container(let container, _) = node,
                  case .scrollable(let contentSize) = container.type,
                  !exhausted.contains(container) else { return nil }
            let target: ScrollableTarget
            if let view = scrollableContainerViews[container], view.window != nil {
                if let sv = view as? UIScrollView {
                    target = .uiScrollView(sv)
                } else {
                    let screenFrame = view.convert(view.bounds, to: nil)
                    target = .swipeable(frame: screenFrame, contentSize: contentSize)
                }
            } else {
                target = .swipeable(frame: container.frame, contentSize: contentSize)
            }
            if let axis, !Self.scrollableAxis(of: target).contains(axis) { return nil }
            return (target, container)
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
        let wire = toWire(found.screenElement)
        return TheSafecracker.InteractionResult(
            success: true, method: .scrollToVisible, message: nil, value: nil,
            scrollSearchResult: ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: screenElements.count,
                totalItems: nil, exhaustive: false, foundElement: wire
            )
        )
    }

    // MARK: - Ensure On Screen (Comfort Zone)

    /// Fraction of each dimension to inset from each edge. 1/6 on each side = middle 2/3.
    static let comfortMarginFraction: CGFloat = 1.0 / 6.0

    /// The middle 2/3 of the screen — activation points should land here before interaction.
    private static var interactionComfortZone: CGRect {
        UIScreen.main.bounds.insetBy(
            dx: UIScreen.main.bounds.width * comfortMarginFraction,
            dy: UIScreen.main.bounds.height * comfortMarginFraction
        )
    }

    func ensureOnScreen(for target: ElementTarget) async {
        guard let safecracker else { return }

        // Step 1: Coarse jump — if element is off-screen but has a cached position, jump there.
        if case .heistId(let heistId) = target,
           !onScreen.contains(heistId),
           let entry = screenElements[heistId], presentedHeistIds.contains(heistId),
           let origin = entry.contentSpaceOrigin,
           let scrollView = entry.scrollView {
            let targetOffset = Self.scrollTargetOffset(for: origin, in: scrollView)
            scrollView.setContentOffset(targetOffset, animated: false)
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            refresh()
        }

        // Step 2: Fine-tune — scroll until the activation point is in the comfort zone
        // (middle 2/3 of screen), not just barely on screen.
        guard let resolved = resolveTarget(target).resolved,
              let object = resolved.screenElement.object else { return }
        let frame = object.accessibilityFrame
        let activationPoint = object.accessibilityActivationPoint
        guard !frame.isNull, !frame.isEmpty,
              !Self.interactionComfortZone.contains(activationPoint),
              let scrollView = resolved.screenElement.scrollView else { return }
        if safecracker.scrollToMakeVisible(
            frame, in: scrollView,
            comfortMarginFraction: Self.comfortMarginFraction
        ) {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            refresh()
        }
    }

    func ensureFirstResponderOnScreen() async {
        guard let responder = tripwire.currentFirstResponder() else { return }
        let frame = responder.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return }
        let activationPoint = responder.accessibilityActivationPoint
        guard !Self.interactionComfortZone.contains(activationPoint) else { return }
        guard let scrollView = screenElements.values
            .first(where: { $0.object === responder })?.scrollView,
              let safecracker else { return }
        if safecracker.scrollToMakeVisible(
            frame, in: scrollView,
            comfortMarginFraction: Self.comfortMarginFraction
        ) {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            refresh()
        }
    }

    /// Synchronous scroll-to-visible — setContentOffset is immediate,
    /// no detached Task needed.
    private func ensureOnScreenSync(_ resolved: ResolvedTarget, animated: Bool = true) {
        guard let object = resolved.screenElement.object,
              let safecracker else { return }
        let frame = object.accessibilityFrame
        let activationPoint = object.accessibilityActivationPoint
        guard !frame.isNull, !frame.isEmpty else { return }
        guard !Self.interactionComfortZone.contains(activationPoint) else { return }
        guard let scrollView = resolved.screenElement.scrollView else { return }
        _ = safecracker.scrollToMakeVisible(
            frame, in: scrollView, animated: animated,
            comfortMarginFraction: Self.comfortMarginFraction
        )
    }

    // MARK: - Scroll Target Resolution (Accessibility Hierarchy)

    /// Find the scrollable container for a resolved element from the accessibility hierarchy.
    /// Uses the element's stored `scrollView` ref (set by the hierarchy tree's containerVisitor).
    /// When `axis` is provided and the stored scroll view can't scroll in that axis,
    /// searches the hierarchy tree for a container that can (e.g. an inner carousel
    /// when the stored scroll view is the outer vertical).
    func resolveScrollTarget(
        screenElement: ScreenElement,
        axis: ScrollAxis? = nil
    ) -> ScrollableTarget? {
        if let sv = screenElement.scrollView {
            let target = ScrollableTarget.uiScrollView(sv)
            if let axis, !Self.scrollableAxis(of: target).contains(axis) {
                if let (axisTarget, _) = findScrollTarget(axis: axis) {
                    return axisTarget
                }
            }
            return target
        }
        return nil
    }

    // MARK: - Direction Mapping

    static func uiScrollDirection(for direction: ScrollSearchDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .down: return .down
        case .up: return .up
        case .left: return .left
        case .right: return .right
        }
    }

    static func uiScrollDirection(for direction: ScrollDirection) -> UIAccessibilityScrollDirection {
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
    static func adaptDirection(
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

    // MARK: - Content-Space Scroll Offset

    /// Compute a contentOffset that centers (or best-effort positions) a content-space
    /// point within the scroll view's visible bounds, clamped to valid content range.
    private static func scrollTargetOffset(for contentOrigin: CGPoint, in scrollView: UIScrollView) -> CGPoint {
        let visibleSize = scrollView.bounds.size
        let insets = scrollView.adjustedContentInset
        let contentSize = scrollView.contentSize

        let maxX = max(contentSize.width + insets.right - visibleSize.width, -insets.left)
        let maxY = max(contentSize.height + insets.bottom - visibleSize.height, -insets.top)

        let targetX = min(max(contentOrigin.x - visibleSize.width / 2, -insets.left), maxX)
        let targetY = min(max(contentOrigin.y - visibleSize.height / 2, -insets.top), maxY)

        return CGPoint(x: targetX, y: targetY)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
