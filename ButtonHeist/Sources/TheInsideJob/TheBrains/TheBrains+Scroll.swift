#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Scroll Orchestration
//
// Finds scrollable containers from the accessibility hierarchy and
// drives TheSafecracker's scroll primitives. Two paths:
//
//   UIScrollView → setContentOffset (fast, precise)
//   Any scrollable → synthetic swipe gesture (universal fallback)

extension TheBrains {

    /// Keep swipe gesture timing stable; scrolling cadence is frame-driven.
    private static let swipeGestureDuration: TimeInterval = 0.12
    /// End swipe settle after this many consecutive frames with no newly
    /// discovered elements.
    private static let swipeSettleIdleFrames = 2
    /// Require viewport stability for a few consecutive frames.
    private static let swipeSettleStableViewportFrames = 3
    /// Minimum post-swipe cooldown frames before allowing another gesture.
    /// Direction reversals need additional frames for spring/inertia to settle.
    private static let swipeDirectionChangeMinSettleFrames = 6
    /// Continuing in the same direction can be dispatched aggressively.
    private static let swipeSameDirectionMinSettleFrames = 1
    /// Hard cap on settle polling to avoid long stalls on spring animations.
    private static let swipeSettleMaxFrames = 24
    /// Quick settle defaults when continuing in the same direction.
    private static let swipeQuickSettleIdleFrames = 1
    private static let swipeQuickSettleStableViewportFrames = 1
    private static let swipeQuickSettleMaxFrames = 3

    /// A scrollable container discovered from the accessibility hierarchy.
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

    struct ScrollAxis: OptionSet, Sendable {
        let rawValue: Int
        static let horizontal = ScrollAxis(rawValue: 1 << 0)
        static let vertical   = ScrollAxis(rawValue: 1 << 1)
    }

    // MARK: - Scroll Axis Detection

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

    func scrollOnePageAndSettle(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) async -> (moved: Bool, previousOnScreen: Set<String>) {
        let before = stash.registry.viewportIds
        let beforeAnchor = viewportAnchorSignature()

        switch target {
        case .uiScrollView(let sv):
            let moved = safecracker.scrollByPage(sv, direction: direction, animated: animated)
            guard moved else { return (false, before) }
            if animated {
                let screenFrame = sv.convert(sv.bounds, to: nil)
                await safecracker.animateScrollFingerprint(
                    frame: screenFrame, direction: direction
                )
            } else {
                await tripwire.yieldFrames(3)
            }
            refresh()
            return (true, before)
        case .swipeable(let frame, let contentSize):
            let targetKey = swipeTargetKey(frame: frame, contentSize: contentSize)
            let isDirectionChange = lastSwipeDirectionByTarget[targetKey].map { $0 != direction } ?? false
            let dispatched = await safecracker.scrollBySwipe(
                frame: frame,
                direction: direction,
                duration: Self.swipeGestureDuration
            )
            guard dispatched else { return (false, before) }
            let moved = await settleSwipeMotion(
                previousOnScreen: before,
                previousAnchor: beforeAnchor,
                requireDirectionChangeSettle: isDirectionChange
            )
            lastSwipeDirectionByTarget[targetKey] = direction
            return (moved, before)
        }
    }

    /// Parse through post-gesture spring/inertia and consider the swipe settled
    /// when no new elements are discovered for a short consecutive frame window.
    private func settleSwipeMotion(
        previousOnScreen: Set<String>,
        previousAnchor: Int?,
        requireDirectionChangeSettle: Bool
    ) async -> Bool {
        let requiredIdleFrames = requireDirectionChangeSettle
            ? Self.swipeSettleIdleFrames
            : Self.swipeQuickSettleIdleFrames
        let requiredStableViewportFrames = requireDirectionChangeSettle
            ? Self.swipeSettleStableViewportFrames
            : Self.swipeQuickSettleStableViewportFrames
        let minFrames = requireDirectionChangeSettle
            ? Self.swipeDirectionChangeMinSettleFrames
            : Self.swipeSameDirectionMinSettleFrames
        let maxFrames = requireDirectionChangeSettle
            ? Self.swipeSettleMaxFrames
            : Self.swipeQuickSettleMaxFrames

        var moved = false
        var knownHeistIds = Set(stash.registry.elements.keys)
        var idleFramesWithoutNew = 0
        var stableViewportFrames = 0
        var lastViewport = stash.registry.viewportIds

        for frame in 0..<maxFrames {
            refresh()
            let currentViewport = stash.registry.viewportIds
            let currentAnchor = viewportAnchorSignature()
            if let previousAnchor, let currentAnchor {
                if currentAnchor != previousAnchor {
                    moved = true
                }
            } else if currentViewport != previousOnScreen {
                moved = true
            }
            if currentViewport == lastViewport {
                stableViewportFrames += 1
            } else {
                lastViewport = currentViewport
                stableViewportFrames = 0
            }

            let currentHeistIds = Set(stash.registry.elements.keys)
            let newHeistIds = currentHeistIds.subtracting(knownHeistIds)
            if newHeistIds.isEmpty {
                idleFramesWithoutNew += 1
            } else {
                knownHeistIds.formUnion(newHeistIds)
                idleFramesWithoutNew = 0
            }

            if frame + 1 >= minFrames,
               idleFramesWithoutNew >= requiredIdleFrames,
               stableViewportFrames >= requiredStableViewportFrames {
                break
            }
            if frame + 1 < maxFrames {
                await tripwire.yieldFrames(1)
            }
        }
        return moved
    }

    /// Stable signature for the top of the viewport based on content-space
    /// origins. This avoids treating edge bounces/re-parses as true movement.
    private func viewportAnchorSignature() -> Int? {
        let anchors = stash.registry.viewportIds.compactMap { heistId -> String? in
            guard let entry = stash.registry.elements[heistId],
                  let origin = entry.contentSpaceOrigin else { return nil }
            return "\(heistId):\(Int(origin.x.rounded())):\(Int(origin.y.rounded()))"
        }.sorted()
        guard !anchors.isEmpty else { return nil }
        return anchors.prefix(12).joined(separator: "|").hashValue
    }

    private func swipeTargetKey(frame: CGRect, contentSize: CGSize) -> String {
        let values = [
            Int(frame.minX.rounded()),
            Int(frame.minY.rounded()),
            Int(frame.width.rounded()),
            Int(frame.height.rounded()),
            Int(contentSize.width.rounded()),
            Int(contentSize.height.rounded())
        ]
        return values.map(String.init).joined(separator: ":")
    }

    private static func safeSwipeFrame(from frame: CGRect) -> CGRect {
        let safeTopInset = windowSafeAreaInsets.top + 56
        let safeBottomInset = windowSafeAreaInsets.bottom + 20
        let safeBounds = UIScreen.main.bounds.inset(by: UIEdgeInsets(
            top: safeTopInset,
            left: 16,
            bottom: safeBottomInset,
            right: 16
        ))
        let intersected = frame.intersection(safeBounds)
        if !intersected.isNull, !intersected.isEmpty,
           intersected.width >= 44, intersected.height >= 44 {
            return intersected
        }

        let fallback = frame.insetBy(
            dx: min(20, frame.width * 0.1),
            dy: min(60, frame.height * 0.2)
        )
        if !fallback.isEmpty { return fallback }
        return frame
    }

    private static var windowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    // MARK: - Scroll Command Execution

    func executeScroll(_ target: ScrollTarget) async -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scroll, message: "Element target required for scroll")
        }
        let resolution = stash.resolveTarget(elementTarget)
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
        let resolution = stash.resolveTarget(elementTarget)
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
                if stash.registry.viewportIds == before { break }
            }
            moved = didMove
        }

        return TheSafecracker.InteractionResult(
            success: moved, method: .scrollToEdge,
            message: moved ? nil : "Already at edge",
            value: nil
        )
    }

    static func edgeDirection(for edge: ScrollEdge) -> UIAccessibilityScrollDirection {
        switch edge {
        case .top: return .up
        case .bottom: return .down
        case .left: return .left
        case .right: return .right
        }
    }

    // MARK: - Scroll To Visible (One-Shot)

    /// One-shot scroll: jump directly to a known element's position.
    /// If already visible, no-op. If the element has a recorded content-space
    /// position, computes the target offset and scrolls there in one shot.
    /// Fails if the element is not in the registry or has no scroll position.
    func executeScrollToVisible(_ target: ScrollToVisibleTarget) async -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scrollToVisible, message: "Element target required for scroll_to_visible")
        }

        stash.refresh()

        // Already visible — ensure it's in the comfort zone and return
        if let found = stash.resolveFirstMatch(elementTarget) {
            ensureOnScreenSync(found)
            return TheSafecracker.InteractionResult(success: true, method: .scrollToVisible, message: "Already visible", value: nil)
        }

        // Known element with recorded position — one-shot jump
        if case .heistId(let heistId) = elementTarget,
           let entry = stash.registry.elements[heistId],
           stash.jumpToRecordedPosition(entry) != nil {
            await tripwire.yieldRealFrames(20)
            refresh()
            if let found = stash.resolveFirstMatch(elementTarget) {
                ensureOnScreenSync(found)
                await tripwire.yieldRealFrames(20)
                refresh()
                if stash.resolveFirstMatch(elementTarget) != nil {
                    return TheSafecracker.InteractionResult(success: true, method: .scrollToVisible, message: nil, value: nil)
                }
            }
            return .failure(.scrollToVisible, message: "Element not visible after scrolling to recorded position")
        }

        return .failure(.scrollToVisible, message: "Element not in registry or has no recorded scroll position. Use element_search to find unseen elements.")
    }

    // MARK: - Element Search (Iterative)

    /// Iterative search: page through scroll content looking for an element.
    /// Used when the element has never been seen (not in the registry).
    func executeElementSearch(_ target: ElementSearchTarget) async -> TheSafecracker.InteractionResult {
        guard let searchTarget = target.elementTarget else {
            return .failure(.elementSearch, message: "Element target required for element_search")
        }
        let searchDirection = target.resolvedDirection

        stash.refresh()

        // Check if already visible before searching
        if let found = stash.resolveFirstMatch(searchTarget) {
            ensureOnScreenSync(found)
            return searchFoundResult(found, scrollCount: 0)
        }

        // If we have a recorded position, try the one-shot path first
        if case .heistId(let heistId) = searchTarget,
           let entry = stash.registry.elements[heistId],
           let savedOffset = stash.jumpToRecordedPosition(entry) {
            await tripwire.yieldRealFrames(20)
            refresh()
            if let found = stash.resolveFirstMatch(searchTarget),
               let result = await searchFineTuneAndResolve(found, searchTarget: searchTarget, scrollCount: 1) {
                return result
            }
            stash.restoreScrollPosition(entry, to: savedOffset)
            await tripwire.yieldRealFrames(20)
            refresh()
        }

        // Iterative page-by-page search
        var exhausted = Set<AccessibilityContainer>()
        var scrollCount = 0
        let maxScrolls = 200

        while scrollCount < maxScrolls {
            guard let (scrollTarget, container) = findScrollTarget(excluding: exhausted) else { break }

            let direction = Self.adaptDirection(searchDirection, for: scrollTarget)
            let (moved, before) = await scrollOnePageAndSettle(
                scrollTarget, direction: direction
            )

            if !moved { exhausted.insert(container); continue }

            scrollCount += 1

            if let found = stash.resolveFirstMatch(searchTarget) {
                if let result = await searchFineTuneAndResolve(found, searchTarget: searchTarget, scrollCount: scrollCount) {
                    return result
                }
                return searchFoundResult(found, scrollCount: scrollCount)
            }

            if stash.registry.viewportIds == before { exhausted.insert(container) }
        }

        return searchNotFoundResult(scrollCount: scrollCount)
    }

    private func searchFineTuneAndResolve(
        _ found: TheStash.ResolvedTarget,
        searchTarget: ElementTarget,
        scrollCount: Int
    ) async -> TheSafecracker.InteractionResult? {
        ensureOnScreenSync(found)
        await tripwire.yieldRealFrames(20)
        stash.refresh()
        guard let fresh = stash.resolveFirstMatch(searchTarget) else { return nil }
        return searchFoundResult(fresh, scrollCount: scrollCount)
    }

    func findScrollTarget(
        axis: ScrollAxis? = nil,
        excluding exhausted: Set<AccessibilityContainer> = []
    ) -> (target: ScrollableTarget, container: AccessibilityContainer)? {
        stash.currentHierarchy.scrollableContainers
            .lazy
            .compactMap { container -> (target: ScrollableTarget, container: AccessibilityContainer)? in
                guard !exhausted.contains(container),
                      case .scrollable(let contentSize) = container.type else { return nil }
                let target = self.scrollableTarget(for: container, contentSize: contentSize)
                if let axis, !Self.scrollableAxis(of: target).contains(axis) { return nil }
                return (target, container)
            }
            .first
    }

    /// Build a ScrollableTarget for a container, preferring the live UIView when attached
    /// to a window so that frames reflect the current screen position.
    func scrollableTarget(
        for container: AccessibilityContainer,
        contentSize: CGSize
    ) -> ScrollableTarget {
        if let view = stash.scrollableContainerViews[container], view.window != nil {
            if let scrollView = view as? UIScrollView, !forceSwipeScrolling {
                return .uiScrollView(scrollView)
            }
            let screenFrame = Self.safeSwipeFrame(from: view.convert(view.bounds, to: nil))
            return .swipeable(frame: screenFrame, contentSize: contentSize)
        }
        return .swipeable(frame: Self.safeSwipeFrame(from: container.frame), contentSize: contentSize)
    }

    private func searchNotFoundResult(scrollCount: Int) -> TheSafecracker.InteractionResult {
        TheSafecracker.InteractionResult(
            success: false, method: .elementSearch,
            message: "Element not found after \(scrollCount) scrolls", value: nil,
            scrollSearchResult: ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: stash.registry.elements.count,
                totalItems: nil, exhaustive: true
            )
        )
    }

    private func searchFoundResult(_ found: TheStash.ResolvedTarget, scrollCount: Int) -> TheSafecracker.InteractionResult {
        let wire = stash.toWire(found.screenElement)
        return TheSafecracker.InteractionResult(
            success: true, method: .elementSearch, message: nil, value: nil,
            scrollSearchResult: ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: stash.registry.elements.count,
                totalItems: nil, exhaustive: false, foundElement: wire
            )
        )
    }

    // MARK: - Ensure On Screen (Comfort Zone)

    private static let comfortMarginFraction: CGFloat = 1.0 / 6.0

    private static var interactionComfortZone: CGRect {
        UIScreen.main.bounds.insetBy(
            dx: UIScreen.main.bounds.width * comfortMarginFraction,
            dy: UIScreen.main.bounds.height * comfortMarginFraction
        )
    }

    func ensureOnScreen(for target: ElementTarget) async {
        if let entry = offViewportRegistryEntry(for: target),
           stash.jumpToRecordedPosition(entry) != nil {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            refresh()
        }

        guard let resolved = stash.resolveTarget(target).resolved,
              let geometry = stash.liveGeometry(for: resolved.screenElement),
              !Self.interactionComfortZone.contains(geometry.activationPoint) else { return }
        if safecracker.scrollToMakeVisible(
            geometry.frame, in: geometry.scrollView,
            comfortMarginFraction: Self.comfortMarginFraction
        ) {
            await tripwire.yieldFrames(3)
            refresh()
        }
    }

    func ensureFirstResponderOnScreen() async {
        guard let heistId = stash.registry.firstResponderHeistId,
              let entry = stash.registry.elements[heistId],
              let geometry = stash.liveGeometry(for: entry),
              !UIScreen.main.bounds.contains(geometry.frame),
              !Self.interactionComfortZone.contains(geometry.activationPoint) else { return }
        if safecracker.scrollToMakeVisible(
            geometry.frame, in: geometry.scrollView,
            comfortMarginFraction: Self.comfortMarginFraction
        ) {
            await tripwire.yieldFrames(3)
            refresh()
        }
    }

    private func ensureOnScreenSync(_ resolved: TheStash.ResolvedTarget, animated: Bool = true) {
        guard let geometry = stash.liveGeometry(for: resolved.screenElement),
              !UIScreen.main.bounds.contains(geometry.frame),
              !Self.interactionComfortZone.contains(geometry.activationPoint) else { return }
        _ = safecracker.scrollToMakeVisible(
            geometry.frame, in: geometry.scrollView, animated: animated,
            comfortMarginFraction: Self.comfortMarginFraction
        )
    }

    // MARK: - Off-Viewport Registry Lookup

    /// Find a registry element that matches `target` but is NOT in the current viewport.
    /// For `.heistId`, looks up the registry directly. For `.matcher`, searches all
    /// registry entries for the first off-viewport match. Returns nil if the element
    /// is already visible or not in the registry.
    func offViewportRegistryEntry(for target: ElementTarget) -> TheStash.ScreenElement? {
        switch target {
        case .heistId(let heistId):
            guard !stash.registry.viewportIds.contains(heistId) else { return nil }
            return stash.registry.elements[heistId]
        case .matcher(let matcher, _):
            for (heistId, entry) in stash.registry.elements
            where !stash.registry.viewportIds.contains(heistId) && entry.element.matches(matcher) {
                return entry
            }
            return nil
        }
    }

    // MARK: - Scroll Target Resolution

    func resolveScrollTarget(
        screenElement: TheStash.ScreenElement,
        axis: ScrollAxis? = nil
    ) -> ScrollableTarget? {
        if let sv = screenElement.scrollView {
            let target: ScrollableTarget
            if forceSwipeScrolling {
                let screenFrame = Self.safeSwipeFrame(from: sv.convert(sv.bounds, to: nil))
                target = .swipeable(frame: screenFrame, contentSize: sv.contentSize)
            } else {
                target = .uiScrollView(sv)
            }
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

}

#endif // DEBUG
#endif // canImport(UIKit)
