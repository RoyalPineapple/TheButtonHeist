#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Scroll Orchestration
//
// TheBagman finds scroll views from the accessibility hierarchy and drives
// TheSafecracker's scroll primitives. TheSafecracker knows nothing about
// elements — it takes a UIScrollView and moves it.

extension TheBagman {

    // MARK: - Scroll Axis Detection

    struct ScrollAxis: OptionSet, Sendable {
        let rawValue: Int
        static let horizontal = ScrollAxis(rawValue: 1 << 0)
        static let vertical   = ScrollAxis(rawValue: 1 << 1)
    }

    func scrollableAxis(of scrollView: UIScrollView) -> ScrollAxis {
        let frame = scrollView.frame.size
        let content = scrollView.contentSize
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
              let scrollView = resolveScrollView(heistId: target.scrollViewHeistId, element: object, includeSelf: true, axis: axis),
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
              let scrollView = resolveScrollView(heistId: target.scrollViewHeistId, element: object, includeSelf: true, axis: axis),
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

        guard let safecracker else {
            return .failure(.scrollToVisible, message: "No gesture engine available")
        }

        // Explicit scroll view target — only search that one.
        if let heistId = target.scrollViewHeistId {
            guard let entry = screenElements[heistId], let obj = entry.object,
                  let sv = obj as? UIScrollView ?? scrollableAncestor(of: obj, includeSelf: true) else {
                return .failure(.scrollToVisible, message: "Scroll view '\(heistId)' not found")
            }
            var scrollCount = 0
            let dir = adaptDirection(searchDirection, for: sv)
            while scrollCount < maxScrolls {
                guard safecracker.scrollByPage(sv, direction: dir, animated: false) else { break }
                await tripwire.yieldFrames(2)
                scrollCount += 1
                refreshAccessibilityData()
                if let found = resolveFirstMatch(searchTarget) {
                    ensureOnScreenSync(found)
                    return foundResult(found, scrollCount: scrollCount)
                }
            }
            return notFoundResult(scrollCount: scrollCount)
        }

        // No explicit target — discover scroll views live from on-screen elements.
        // After each edge-hit we re-discover, so newly-revealed scroll views
        // (from outer scrolling) get picked up automatically.
        var exhausted = Set<ObjectIdentifier>()
        var scrollCount = 0

        while scrollCount < maxScrolls {
            guard let scrollView = findLiveScrollView(
                excluding: exhausted, direction: searchDirection
            ) else { break }

            let dir = adaptDirection(searchDirection, for: scrollView)
            let moved = safecracker.scrollByPage(scrollView, direction: dir, animated: false)

            if !moved {
                exhausted.insert(ObjectIdentifier(scrollView))
                continue
            }

            await tripwire.yieldFrames(2)
            scrollCount += 1
            refreshAccessibilityData()

            if let found = resolveFirstMatch(searchTarget) {
                ensureOnScreenSync(found)
                return foundResult(found, scrollCount: scrollCount)
            }
        }

        return notFoundResult(scrollCount: scrollCount)
    }

    /// Find a live, non-exhausted scroll view from current on-screen elements.
    /// Uses `ScreenElement.scrollView` — the scroll view assigned from the accessibility
    /// hierarchy's `.scrollable` containers, not from UIKit superview walking.
    /// Returns the outermost scroll view first (most children = most content to reveal).
    private func findLiveScrollView(
        excluding exhausted: Set<ObjectIdentifier>,
        direction: ScrollSearchDirection
    ) -> UIScrollView? {
        var childCount: [ObjectIdentifier: (sv: UIScrollView, count: Int)] = [:]
        for (heistId, entry) in screenElements where onScreen.contains(heistId) {
            guard let sv = entry.scrollView, sv.window != nil else { continue }
            let id = ObjectIdentifier(sv)
            guard !exhausted.contains(id) else { continue }
            childCount[id, default: (sv, 0)].count += 1
        }
        // Most children first — the outermost scroll view owns the most on-screen elements.
        return childCount.values.max(by: { $0.count < $1.count })?.sv
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
    /// whose content is scrollable along the requested axis. Falls back to innermost
    /// ancestor if no axis-compatible scroll view is found.
    func resolveScrollView(
        heistId: String?,
        element: NSObject,
        includeSelf: Bool,
        axis: ScrollAxis? = nil
    ) -> UIScrollView? {
        if let heistId, let entry = screenElements[heistId], let obj = entry.object {
            return obj as? UIScrollView ?? scrollableAncestor(of: obj, includeSelf: true)
        }
        guard let axis else {
            return scrollableAncestor(of: element, includeSelf: includeSelf)
        }
        let ancestors = scrollableAncestors(of: element, includeSelf: includeSelf)
        return ancestors.first { scrollableAxis(of: $0).contains(axis) }
            ?? ancestors.first
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
        for scrollView: UIScrollView
    ) -> UIAccessibilityScrollDirection {
        let axis = scrollableAxis(of: scrollView)
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
