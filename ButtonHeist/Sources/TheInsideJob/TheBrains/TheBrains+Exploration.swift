#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Screen Exploration
//
// Scrolls every scrollable container to discover all elements on screen.
// Container fingerprint caching skips unchanged containers on re-explore.
//
// Post-0.2.25: TheStash has no exploration mode. The accumulator is a local
// `var union: Screen` in exploreAndPrune; the final union is committed by
// writing it back into `stash.currentScreen`. Mid-exploration writes to
// `currentScreen` keep in-cycle scroll-termination checks (viewport change
// detection) working — they read `stash.viewportIds`, which mirrors the
// latest page-only parse, not the in-flight union.

extension TheBrains {

    fileprivate struct ContainerPage {
        let elements: [AccessibilityElement]
        let origins: [CGPoint?]
    }

    /// Cached state from the last explore of each scrollable container.
    struct ContainerExploreState {
        let visibleSubtreeFingerprint: Int
        let discoveredHeistIds: Set<String>
    }

    /// Explore and accumulate the unioned screen. The local `union: Screen`
    /// holds every element seen during this exploration; the final union is
    /// committed to `stash.currentScreen` so subsequent operations can act on
    /// off-screen content (with the documented strict-by-default activation
    /// rule for later refreshes).
    func exploreAndPrune(target: ElementTarget? = nil) async -> ScreenManifest {
        var union = stash.currentScreen
        let manifest = await exploreScreen(target: target, union: &union)
        stash.currentScreen = union
        return manifest
    }

    /// Scroll all scrollable containers to discover every element on screen.
    /// Accumulates discovered elements into `union`. Mid-exploration writes
    /// to `stash.currentScreen` happen as scrolls land — those are the live
    /// viewport, used by termination heuristics.
    func exploreScreen(target: ElementTarget? = nil, union: inout Screen) async -> ScreenManifest {
        let startTime = CACurrentMediaTime()
        var manifest = ScreenManifest()

        if let parsed = stash.refresh() {
            union = union.merging(parsed)
        }

        if let target, stash.resolveFirstMatch(target) != nil {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return manifest
        }

        manifest.addPendingContainers(stash.currentHierarchy.scrollableContainers)
        var containerFingerprints = stash.currentHierarchy.containerFingerprints

        while !manifest.pendingContainers.isEmpty {
            let batch = manifest.pendingContainers
                .map { (container: $0, overflow: Self.totalOverflow(of: $0)) }
                .sorted { $0.overflow > $1.overflow }
                .map(\.container)

            for container in batch {
                guard case .scrollable(let contentSize) = container.type else {
                    manifest.markExplored(container)
                    continue
                }

                if let view = stash.scrollableContainerViews[container],
                   view.window != nil,
                   Self.isObscuredByPresentation(view: view) {
                    manifest.markExplored(container)
                    continue
                }

                let currentFingerprint = containerFingerprints[container] ?? 0
                if let cached = containerExploreStates[container],
                   cached.visibleSubtreeFingerprint == currentFingerprint,
                   target == nil {
                    manifest.markExplored(container)
                    continue
                }

                let hasHOverflow = contentSize.width > container.frame.width + 1
                let hasVOverflow = contentSize.height > container.frame.height + 1
                guard hasHOverflow || hasVOverflow else {
                    manifest.markExplored(container)
                    continue
                }

                // A scroll-shaped container with inflated `contentSize` (e.g. a SwiftUI
                // `NavigationStack` host wrapping a non-scrolling canvas) reports overflow
                // even when no descendant element actually lives off-screen. Require at
                // least one descendant whose AX frame extends past the container frame
                // before paying for swipes.
                guard Self.hasContentBeyondFrame(of: container, in: stash.currentHierarchy) else {
                    manifest.markExplored(container)
                    continue
                }

                guard let scrollTarget = scrollableTarget(for: container, contentSize: contentSize) else {
                    manifest.markExplored(container)
                    continue
                }
                let found = await exploreContainer(
                    container: container, scrollTarget: scrollTarget,
                    hasHOverflow: hasHOverflow, hasVOverflow: hasVOverflow,
                    target: target, manifest: &manifest,
                    containerFingerprints: &containerFingerprints,
                    union: &union
                )
                if found {
                    manifest.explorationTime = CACurrentMediaTime() - startTime
                    return manifest
                }
            }
        }

        manifest.explorationTime = CACurrentMediaTime() - startTime
        return manifest
    }

    /// Scroll a single container to discover all elements. Returns true if the
    /// target was found during exploration (caller should return early).
    private func exploreContainer(
        container: AccessibilityContainer,
        scrollTarget: ScrollableTarget,
        hasHOverflow: Bool,
        hasVOverflow: Bool,
        target: ElementTarget?,
        manifest: inout ScreenManifest,
        containerFingerprints: inout [AccessibilityContainer: Int],
        union: inout Screen
    ) async -> Bool {
        let savedVisualOrigin: CGPoint? = {
            guard case .uiScrollView(let scrollView) = scrollTarget else { return nil }
            return CGPoint(
                x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
                y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            )
        }()
        let direction: UIAccessibilityScrollDirection = hasHOverflow ? .right : .down

        let leadingEdge: ScrollEdge = hasHOverflow ? .left : .top
        switch scrollTarget {
        case .uiScrollView(let scrollView):
            if safecracker.scrollToEdge(scrollView, edge: leadingEdge, animated: false) {
                await tripwire.yieldFrames(2)
                if let parsed = stash.refresh() {
                    union = union.merging(parsed)
                }
            }
        case .swipeable:
            let toLeading = Self.edgeDirection(for: leadingEdge)
            for _ in 0..<50 {
                let (moved, before) = await scrollOnePageAndSettle(
                    scrollTarget, direction: toLeading, animated: false
                )
                if moved, let parsed = stash.parse() {
                    stash.currentScreen = parsed
                    union = union.merging(parsed)
                }
                if !moved || stash.viewportIds == before { break }
            }
        }

        var originByElement = buildOriginIndex()

        let initialPage = visibleElementsInContainer(container)
        var accumulated = initialPage.elements
        var accumulatedOrigins = initialPage.origins

        for _ in 0..<ScreenManifest.maxScrollsPerContainer {
            let (moved, _) = await scrollOnePageAndSettle(
                scrollTarget, direction: direction, animated: false
            )
            guard moved else { break }
            manifest.scrollCount += 1
            if let parsed = stash.parse() {
                stash.currentScreen = parsed
                union = union.merging(parsed)
            }
            originByElement = buildOriginIndex()

            let page = visibleElementsInContainer(container)
            let result = stitchPage(
                accumulated: accumulated,
                accumulatedOrigins: accumulatedOrigins,
                page: page.elements,
                pageOrigins: page.origins,
                orderingAxis: hasHOverflow ? .horizontal : .vertical
            )
            accumulated = result.elements
            accumulatedOrigins = accumulated.map { originByElement[$0] ?? nil }

            if result.inserted.isEmpty { break }

            if let target, stash.resolveFirstMatch(target) != nil {
                await restoreAndCache(
                    scrollTarget: scrollTarget, savedVisualOrigin: savedVisualOrigin,
                    container: container,
                    discoveredElements: accumulated,
                    manifest: &manifest, containerFingerprints: &containerFingerprints,
                    union: &union
                )
                return true
            }
        }

        await restoreAndCache(
            scrollTarget: scrollTarget, savedVisualOrigin: savedVisualOrigin,
            container: container,
            discoveredElements: accumulated,
            manifest: &manifest, containerFingerprints: &containerFingerprints,
            union: &union
        )

        let newContainers = stash.currentHierarchy.scrollableContainers
            .filter { !manifest.exploredContainers.contains($0) && !manifest.pendingContainers.contains($0) }
        manifest.addPendingContainers(newContainers)
        return false
    }

    // MARK: - Exploration Helpers

    private func restoreAndCache(
        scrollTarget: ScrollableTarget,
        savedVisualOrigin: CGPoint?,
        container: AccessibilityContainer,
        discoveredElements: [AccessibilityElement],
        manifest: inout ScreenManifest,
        containerFingerprints: inout [AccessibilityContainer: Int],
        union: inout Screen
    ) async {
        if case .uiScrollView(let scrollView) = scrollTarget,
           let savedVisualOrigin {
            Self.restoreVisualOrigin(savedVisualOrigin, in: scrollView)
            await tripwire.yieldFrames(2)
            if let parsed = stash.refresh() {
                union = union.merging(parsed)
            }
        }
        containerFingerprints = stash.currentHierarchy.containerFingerprints
        manifest.markExplored(container)
        let fingerprint = containerFingerprints[container] ?? 0
        updateContainerExploreCache(
            container,
            fingerprint: fingerprint,
            discoveredHeistIds: resolveHeistIds(for: discoveredElements)
        )
    }

    private func visibleElementsInContainer(_ container: AccessibilityContainer) -> ContainerPage {
        let pairs = stash.currentHierarchy.compactMap(
            context: false,
            container: { isInside, current in isInside || current == container },
            element: { element, _, isInside -> (element: AccessibilityElement, origin: CGPoint?)? in
                guard isInside,
                      let heistId = self.stash.currentScreen.heistIdByElement[element],
                      self.stash.viewportIds.contains(heistId),
                      let entry = self.stash.currentScreen.findElement(heistId: heistId) else { return nil }
                return (element: entry.element, origin: entry.contentSpaceOrigin)
            }
        )
        return ContainerPage(elements: pairs.map(\.element), origins: pairs.map(\.origin))
    }

    private func buildOriginIndex() -> [AccessibilityElement: CGPoint?] {
        Dictionary(
            stash.currentScreen.elements.values.map { ($0.element, $0.contentSpaceOrigin) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func resolveHeistIds(for elements: [AccessibilityElement]) -> Set<String> {
        Set(elements.compactMap { stash.currentScreen.heistIdByElement[$0] })
    }

    private static func restoreVisualOrigin(_ visualOrigin: CGPoint, in scrollView: UIScrollView) {
        let insets = scrollView.adjustedContentInset
        let restoredOffset = CGPoint(
            x: visualOrigin.x - insets.left,
            y: visualOrigin.y - insets.top
        )
        let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
        let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        let clampedOffset = CGPoint(
            x: max(-insets.left, min(restoredOffset.x, maxX)),
            y: max(-insets.top, min(restoredOffset.y, maxY))
        )
        scrollView.setContentOffset(clampedOffset, animated: false)
    }

    private func updateContainerExploreCache(
        _ container: AccessibilityContainer,
        fingerprint: Int,
        discoveredHeistIds: Set<String>
    ) {
        containerExploreStates[container] = ContainerExploreState(
            visibleSubtreeFingerprint: fingerprint,
            discoveredHeistIds: discoveredHeistIds
        )
    }

    // MARK: - Container Overflow

    /// Sum of horizontal and vertical content overflow for a container.
    /// Zero for containers that don't overflow their frame (or aren't `.scrollable`).
    static func totalOverflow(of container: AccessibilityContainer) -> CGFloat {
        guard case .scrollable(let contentSize) = container.type else { return 0 }
        return max(0, contentSize.width - container.frame.width)
            + max(0, contentSize.height - container.frame.height)
    }

    /// Returns true if any accessibility-element descendant of `container` has a
    /// frame extending past `container.frame` by more than `tolerance` points.
    static func hasContentBeyondFrame(
        of container: AccessibilityContainer,
        in hierarchy: [AccessibilityHierarchy],
        tolerance: CGFloat = 1
    ) -> Bool {
        let containerFrame = container.frame
        let hits: [Bool] = hierarchy.compactMap(
            first: 1,
            context: false,
            container: { isInside, current in isInside || current == container },
            element: { element, _, isInside -> Bool? in
                guard isInside else { return nil }
                let elementFrame = element.shape.frame
                let extendsBeyond =
                    elementFrame.minX < containerFrame.minX - tolerance
                    || elementFrame.minY < containerFrame.minY - tolerance
                    || elementFrame.maxX > containerFrame.maxX + tolerance
                    || elementFrame.maxY > containerFrame.maxY + tolerance
                return extendsBeyond ? true : nil
            }
        )
        return !hits.isEmpty
    }

    // MARK: - Presentation Obscuring

    /// Returns true if the view is behind a presented view controller.
    static func isObscuredByPresentation(view: UIView) -> Bool {
        guard let window = view.window,
              let rootVC = window.rootViewController else {
            return false
        }

        guard let topPresented = Self.topmostPresentedViewController(from: rootVC) else {
            return false
        }

        guard let viewVC = view.nearestViewController else {
            return false
        }
        return !viewVC.isDescendant(of: topPresented)
    }

    private static func topmostPresentedViewController(
        from root: UIViewController
    ) -> UIViewController? {
        var topPresented: UIViewController?

        var queue: [UIViewController] = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()

            if let presented = current.presentedViewController {
                var top = presented
                while let next = top.presentedViewController {
                    top = next
                }
                topPresented = top
            }

            queue.append(contentsOf: current.children)
        }

        return topPresented
    }
}

// MARK: - UIView Responder Chain

extension UIView {

    /// Walks the responder chain to find the nearest UIViewController that owns this view.
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController { return viewController }
            responder = next
        }
        return nil
    }
}

// MARK: - UIViewController Hierarchy

extension UIViewController {

    /// Returns true if this view controller is a descendant of the given ancestor —
    /// checking parent, presenting, navigation, and tab controller chains, as well
    /// as child view controllers of container types.
    func isDescendant(of ancestor: UIViewController) -> Bool {
        var queue: [UIViewController] = [ancestor]
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if current === self { return true }
            queue.append(contentsOf: current.children)
        }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
