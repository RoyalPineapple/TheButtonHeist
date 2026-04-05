#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Scroll Orchestration
//
// Finds scrollable containers from the accessibility hierarchy and
// drives TheSafecracker's scroll primitives. Two paths:
//
//   UIScrollView → setContentOffset (fast, precise)
//   Any scrollable → synthetic swipe gesture (universal fallback)

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

    struct ScrollAxis: OptionSet, Sendable {
        let rawValue: Int
        static let horizontal = ScrollAxis(rawValue: 1 << 0)
        static let vertical   = ScrollAxis(rawValue: 1 << 1)
    }

    @MainActor
    final class ScrollExecution {

    unowned let bagman: TheBagman

    init(bagman: TheBagman) {
        self.bagman = bagman
    }

    private var safecracker: TheSafecracker? { bagman.safecracker }

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

    /// Scroll a target by one page, wait for layout to settle, and refresh.
    func scrollOnePageAndSettle(
        _ target: ScrollableTarget,
        direction: UIAccessibilityScrollDirection,
        animated: Bool = true
    ) async -> (moved: Bool, previousOnScreen: Set<String>) {
        let before = bagman.viewportHeistIds
        guard let safecracker else { return (false, before) }

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
                await bagman.tripwire.yieldFrames(3)
            }
            bagman.refresh()
            return (true, before)
        case .swipeable(let frame, _):
            _ = await safecracker.scrollBySwipe(frame: frame, direction: direction)
            await bagman.tripwire.yieldFrames(3)
            bagman.refresh()
            return (bagman.viewportHeistIds != before, before)
        }
    }

    // MARK: - Scroll Command Execution

    func executeScroll(_ target: ScrollTarget) async -> TheSafecracker.InteractionResult {
        guard let elementTarget = target.elementTarget else {
            return .failure(.scroll, message: "Element target required for scroll")
        }
        let resolution = bagman.resolveTarget(elementTarget)
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
        let resolution = bagman.resolveTarget(elementTarget)
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
                if bagman.viewportHeistIds == before { break }
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
        bagman.refresh()
        if let found = bagman.resolveFirstMatch(searchTarget) {
            ensureOnScreenSync(found)
            return foundResult(found, scrollCount: 0)
        }

        guard safecracker != nil else {
            return .failure(.scrollToVisible, message: "No gesture engine available")
        }

        // Fast path: cached content-space position jump
        if case .heistId(let heistId) = searchTarget,
           let entry = bagman.screenElements[heistId], bagman.presentedHeistIds.contains(heistId),
           let origin = entry.contentSpaceOrigin,
           let scrollView = entry.scrollView {
            let savedOffset = scrollView.contentOffset
            let targetOffset = Self.scrollTargetOffset(for: origin, in: scrollView)
            scrollView.setContentOffset(targetOffset, animated: true)
            await bagman.tripwire.yieldRealFrames(20)
            bagman.refresh()
            if let found = bagman.resolveFirstMatch(searchTarget),
               let result = await fineTuneAndResolve(found, searchTarget: searchTarget, scrollCount: 1) {
                return result
            }
            scrollView.setContentOffset(savedOffset, animated: true)
            await bagman.tripwire.yieldRealFrames(20)
            bagman.refresh()
        }

        // Page-by-page search
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

            if let found = bagman.resolveFirstMatch(searchTarget) {
                if let result = await fineTuneAndResolve(found, searchTarget: searchTarget, scrollCount: scrollCount) {
                    return result
                }
                return foundResult(found, scrollCount: scrollCount)
            }

            if bagman.viewportHeistIds == before { exhausted.insert(container) }
        }

        return notFoundResult(scrollCount: scrollCount)
    }

    private func fineTuneAndResolve(
        _ found: ResolvedTarget,
        searchTarget: ElementTarget,
        scrollCount: Int
    ) async -> TheSafecracker.InteractionResult? {
        ensureOnScreenSync(found)
        await bagman.tripwire.yieldRealFrames(20)
        bagman.refresh()
        guard let fresh = bagman.resolveFirstMatch(searchTarget) else { return nil }
        return foundResult(fresh, scrollCount: scrollCount)
    }

    func findScrollTarget(
        axis: ScrollAxis? = nil,
        excluding exhausted: Set<AccessibilityContainer> = []
    ) -> (target: ScrollableTarget, container: AccessibilityContainer)? {
        let candidates = bagman.currentHierarchy.scrollableContainers
            .filter { !exhausted.contains($0) }

        for container in candidates {
            guard case .scrollable(let contentSize) = container.type else { continue }
            let target: ScrollableTarget
            if let view = bagman.scrollableContainerViews[container], view.window != nil {
                if let scrollView = view as? UIScrollView {
                    target = .uiScrollView(scrollView)
                } else {
                    let screenFrame = view.convert(view.bounds, to: nil)
                    target = .swipeable(frame: screenFrame, contentSize: contentSize)
                }
            } else {
                target = .swipeable(frame: container.frame, contentSize: contentSize)
            }
            if let axis, !Self.scrollableAxis(of: target).contains(axis) { continue }
            return (target, container)
        }
        return nil
    }

    private func notFoundResult(scrollCount: Int) -> TheSafecracker.InteractionResult {
        TheSafecracker.InteractionResult(
            success: false, method: .scrollToVisible,
            message: "Element not found after \(scrollCount) scrolls", value: nil,
            scrollSearchResult: ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: bagman.screenElements.count,
                totalItems: nil, exhaustive: true
            )
        )
    }

    private func foundResult(_ found: ResolvedTarget, scrollCount: Int) -> TheSafecracker.InteractionResult {
        bagman.markPresented([found.screenElement])
        let wire = bagman.toWire(found.screenElement)
        return TheSafecracker.InteractionResult(
            success: true, method: .scrollToVisible, message: nil, value: nil,
            scrollSearchResult: ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: bagman.screenElements.count,
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
        guard let safecracker else { return }

        if case .heistId(let heistId) = target,
           !bagman.viewportHeistIds.contains(heistId),
           let entry = bagman.screenElements[heistId], bagman.presentedHeistIds.contains(heistId),
           let origin = entry.contentSpaceOrigin,
           let scrollView = entry.scrollView {
            let targetOffset = Self.scrollTargetOffset(for: origin, in: scrollView)
            scrollView.setContentOffset(targetOffset, animated: true)
            await bagman.tripwire.yieldFrames(20)
            bagman.refresh()
        }

        guard let resolved = bagman.resolveTarget(target).resolved,
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
            await bagman.tripwire.yieldFrames(3)
            bagman.refresh()
        }
    }

    func ensureFirstResponderOnScreen() async {
        guard let responder = bagman.tripwire.currentFirstResponder() else { return }
        let frame = responder.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return }
        guard !UIScreen.main.bounds.contains(frame) else { return }
        let activationPoint = responder.accessibilityActivationPoint
        guard !Self.interactionComfortZone.contains(activationPoint) else { return }
        guard let scrollView = bagman.screenElements.values
            .first(where: { $0.object === responder })?.scrollView,
              let safecracker else { return }
        if safecracker.scrollToMakeVisible(
            frame, in: scrollView,
            comfortMarginFraction: Self.comfortMarginFraction
        ) {
            await bagman.tripwire.yieldFrames(3)
            bagman.refresh()
        }
    }

    func ensureOnScreenSync(_ resolved: ResolvedTarget, animated: Bool = true) {
        guard let object = resolved.screenElement.object,
              let safecracker else { return }
        let frame = object.accessibilityFrame
        let activationPoint = object.accessibilityActivationPoint
        guard !frame.isNull, !frame.isEmpty else { return }
        guard !UIScreen.main.bounds.contains(frame) else { return }
        guard !Self.interactionComfortZone.contains(activationPoint) else { return }
        guard let scrollView = resolved.screenElement.scrollView else { return }
        _ = safecracker.scrollToMakeVisible(
            frame, in: scrollView, animated: animated,
            comfortMarginFraction: Self.comfortMarginFraction
        )
    }

    // MARK: - Scroll Target Resolution

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

    static func scrollTargetOffset(for contentOrigin: CGPoint, in scrollView: UIScrollView) -> CGPoint {
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
} // extension TheBagman

#endif // DEBUG
#endif // canImport(UIKit)
