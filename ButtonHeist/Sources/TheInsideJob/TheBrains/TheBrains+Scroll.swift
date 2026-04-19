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

    /// Settle-loop pacing parameters. Two canned profiles: `.directionChange`
    /// is the conservative budget for reversals (spring/inertia takes longer);
    /// `.sameDirection` is the aggressive budget for continuing scrolls.
    struct SettleSwipeProfile: Sendable, Equatable {
        /// Earliest frame at which exit conditions can be evaluated.
        var minFrames: Int
        /// Hard cap on settle polling to avoid long stalls on spring animations.
        var maxFrames: Int
        /// Consecutive frames with no newly-discovered elements needed to exit.
        var requiredIdleFrames: Int
        /// Consecutive frames with an unchanged viewport set needed to exit.
        var requiredStableViewportFrames: Int

        static let directionChange = SettleSwipeProfile(
            minFrames: 6, maxFrames: 24,
            requiredIdleFrames: 2, requiredStableViewportFrames: 3
        )
        static let sameDirection = SettleSwipeProfile(
            minFrames: 1, maxFrames: 3,
            requiredIdleFrames: 1, requiredStableViewportFrames: 1
        )
    }

    /// Return value from `SettleSwipeLoopState.advance(...)` — whether the
    /// caller should feed another frame or treat the swipe as settled.
    enum SettleSwipeStep: Equatable { case `continue`, done }

    /// Pure stepwise driver for the swipe-settle loop. Tracks motion-detected
    /// state, idle/stable counters, and exit conditions given a sequence of
    /// per-frame observations. `moved` only latches from false to true.
    struct SettleSwipeLoopState: Equatable {
        let profile: SettleSwipeProfile
        let previousViewport: Set<String>
        let previousAnchor: Int?

        private(set) var moved = false
        private(set) var frame = 0
        private var lastViewport: Set<String>
        private var idleFramesWithoutNew = 0
        private var stableViewportFrames = 0

        init(
            profile: SettleSwipeProfile,
            previousViewport: Set<String>,
            previousAnchor: Int?
        ) {
            self.profile = profile
            self.previousViewport = previousViewport
            self.previousAnchor = previousAnchor
            self.lastViewport = previousViewport
        }

        /// Advance one frame. Pass the current viewport id set, the current
        /// anchor signature (nil if content-space origins unavailable), and
        /// the heistIds newly discovered this frame.
        mutating func advance(
            viewportIds: Set<String>,
            anchorSignature: Int?,
            newHeistIds: Set<String>
        ) -> SettleSwipeStep {
            if let previousAnchor, let anchorSignature {
                if anchorSignature != previousAnchor { moved = true }
            } else if viewportIds != previousViewport {
                moved = true
            }

            if viewportIds == lastViewport {
                stableViewportFrames += 1
            } else {
                lastViewport = viewportIds
                stableViewportFrames = 0
            }

            if newHeistIds.isEmpty {
                idleFramesWithoutNew += 1
            } else {
                idleFramesWithoutNew = 0
            }

            frame += 1

            if frame >= profile.minFrames,
               idleFramesWithoutNew >= profile.requiredIdleFrames,
               stableViewportFrames >= profile.requiredStableViewportFrames {
                return .done
            }
            if frame >= profile.maxFrames {
                return .done
            }
            return .continue
        }
    }

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
        let profile: SettleSwipeProfile = requireDirectionChangeSettle
            ? .directionChange
            : .sameDirection
        var state = SettleSwipeLoopState(
            profile: profile,
            previousViewport: previousOnScreen,
            previousAnchor: previousAnchor
        )
        var knownHeistIds = Set(stash.registry.elements.keys)

        while true {
            refresh()
            let currentHeistIds = Set(stash.registry.elements.keys)
            let newHeistIds = currentHeistIds.subtracting(knownHeistIds)
            knownHeistIds.formUnion(newHeistIds)

            let step = state.advance(
                viewportIds: stash.registry.viewportIds,
                anchorSignature: viewportAnchorSignature(),
                newHeistIds: newHeistIds
            )
            if case .done = step { break }
            await tripwire.yieldFrames(1)
        }
        return state.moved
    }

    /// Stable signature for the viewport based on content-space origins.
    /// Avoids treating edge bounces/re-parses as true movement.
    ///
    /// The returned hash is **in-process only** — Swift's hash seed is
    /// randomized per launch, so never persist, log, or compare these values
    /// across processes.
    private func viewportAnchorSignature() -> Int? {
        let anchors = stash.registry.viewportIds.compactMap { heistId -> String? in
            guard let entry = stash.registry.elements[heistId],
                  let origin = entry.contentSpaceOrigin else { return nil }
            return "\(heistId):\(Int(origin.x.rounded())):\(Int(origin.y.rounded()))"
        }.sorted()
        guard !anchors.isEmpty else { return nil }
        return anchors.joined(separator: "|").hashValue
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

    /// Clamp a swipe rectangle to the screen region that isn't occupied by
    /// visible navigation bars, tab bars, or the window's layout margins.
    /// Returns the intersection when it's non-empty; otherwise returns the
    /// frame clipped to the screen so swipes at least stay on-screen.
    static func safeSwipeFrame(from frame: CGRect) -> CGRect {
        let safeIntersection = frame.intersection(currentSwipeSafeBounds())
        if !safeIntersection.isNull, !safeIntersection.isEmpty {
            return safeIntersection
        }
        let screenIntersection = frame.intersection(ScreenMetrics.current.bounds)
        if !screenIntersection.isNull, !screenIntersection.isEmpty {
            return screenIntersection
        }
        return frame
    }

    /// Region of the screen safe for synthetic swipes: below any visible
    /// `UINavigationBar`, above any visible `UITabBar`/`UIToolbar`, inset
    /// horizontally by the key window's layout margins. With no window or
    /// chrome, degrades to the screen bounds inset by `safeAreaInsets`.
    private static func currentSwipeSafeBounds() -> CGRect {
        let screen = ScreenMetrics.current.bounds
        guard let window = keyWindow else { return screen }
        let chrome = visibleChromeEdges(in: window)
        let insets = window.safeAreaInsets
        let horizontalInset = window.directionalLayoutMargins.leading
        let top = chrome.navBarBottom ?? insets.top
        let bottom = chrome.tabBarTop ?? (screen.height - insets.bottom)
        return CGRect(
            x: screen.minX + horizontalInset,
            y: top,
            width: max(0, screen.width - horizontalInset * 2),
            height: max(0, bottom - top)
        )
    }

    /// Bottom of the lowest visible navigation bar and top of the highest
    /// visible tab bar / toolbar, both in window coordinates. `nil` entries
    /// signal absence of that chrome in the key window's hierarchy.
    private static func visibleChromeEdges(
        in window: UIWindow?
    ) -> (navBarBottom: CGFloat?, tabBarTop: CGFloat?) {
        guard let window else { return (nil, nil) }
        var navBarBottom: CGFloat?
        var tabBarTop: CGFloat?
        var stack: [UIView] = [window]
        while let view = stack.popLast() {
            guard !view.isHidden, view.alpha > 0 else { continue }
            if let nav = view as? UINavigationBar {
                let frame = nav.convert(nav.bounds, to: nil)
                navBarBottom = max(navBarBottom ?? -.greatestFiniteMagnitude, frame.maxY)
            } else if view is UITabBar || view is UIToolbar {
                let frame = view.convert(view.bounds, to: nil)
                tabBarTop = min(tabBarTop ?? .greatestFiniteMagnitude, frame.minY)
            }
            stack.append(contentsOf: view.subviews)
        }
        return (navBarBottom, tabBarTop == .greatestFiniteMagnitude ? nil : tabBarTop)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
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
        let bounds = ScreenMetrics.current.bounds
        return bounds.insetBy(
            dx: bounds.width * comfortMarginFraction,
            dy: bounds.height * comfortMarginFraction
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
              !ScreenMetrics.current.bounds.contains(geometry.frame),
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
              !ScreenMetrics.current.bounds.contains(geometry.frame),
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
