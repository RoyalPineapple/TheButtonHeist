#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Screen Exploration
//
// Scrolls every scrollable container to discover all elements on screen.
// Container fingerprint caching skips unchanged containers on re-explore.

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

    /// Explore and prune: track heistIds across all apply() calls, then remove unseen.
    func exploreAndPrune(target: ElementTarget? = nil) async -> ScreenManifest {
        beginExploreCycle()
        let manifest = await exploreScreen(target: target)
        if let seen = endExploreCycle() {
            stash.registry.prune(keeping: seen)
        }
        return manifest
    }

    /// Scroll all scrollable containers to discover every element on screen.
    func exploreScreen(target: ElementTarget? = nil) async -> ScreenManifest {
        let startTime = CACurrentMediaTime()
        var manifest = ScreenManifest()

        refresh()

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
                    manifest.skippedObscuredContainers += 1
                    continue
                }

                let currentFingerprint = containerFingerprints[container] ?? 0
                if let cached = containerExploreStates[container],
                   cached.visibleSubtreeFingerprint == currentFingerprint,
                   target == nil {
                    recordDuringExplore(cached.discoveredHeistIds)
                    manifest.markExplored(container)
                    manifest.skippedContainers += 1
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
                    containerFingerprints: &containerFingerprints
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
        containerFingerprints: inout [AccessibilityContainer: Int]
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
                refresh()
            }
        case .swipeable:
            let toLeading = Self.edgeDirection(for: leadingEdge)
            for _ in 0..<50 {
                let (moved, before) = await scrollOnePageAndSettle(
                    scrollTarget, direction: toLeading, animated: false
                )
                if !moved || stash.registry.viewportIds == before { break }
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
            originByElement = buildOriginIndex()

            let page = visibleElementsInContainer(container)
            let result = stitchPage(
                accumulated: accumulated,
                accumulatedOrigins: accumulatedOrigins,
                page: page.elements,
                pageOrigins: page.origins
            )
            accumulated = result.elements
            accumulatedOrigins = accumulated.map { originByElement[$0] ?? nil }

            if result.inserted.isEmpty { break }

            if let target, stash.resolveFirstMatch(target) != nil {
                await restoreAndCache(
                    scrollTarget: scrollTarget, savedVisualOrigin: savedVisualOrigin,
                    container: container,
                    discoveredElements: accumulated,
                    manifest: &manifest, containerFingerprints: &containerFingerprints
                )
                return true
            }
        }

        await restoreAndCache(
            scrollTarget: scrollTarget, savedVisualOrigin: savedVisualOrigin,
            container: container,
            discoveredElements: accumulated,
            manifest: &manifest, containerFingerprints: &containerFingerprints
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
        containerFingerprints: inout [AccessibilityContainer: Int]
    ) async {
        if case .uiScrollView(let scrollView) = scrollTarget,
           let savedVisualOrigin {
            Self.restoreVisualOrigin(savedVisualOrigin, in: scrollView)
            await tripwire.yieldFrames(2)
            refresh()
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
                      let heistId = self.stash.registry.reverseIndex[element],
                      self.stash.registry.viewportIds.contains(heistId),
                      let entry = self.stash.registry.findElement(heistId: heistId) else { return nil }
                return (element: entry.element, origin: entry.contentSpaceOrigin)
            }
        )
        return ContainerPage(elements: pairs.map(\.element), origins: pairs.map(\.origin))
    }

    private func buildOriginIndex() -> [AccessibilityElement: CGPoint?] {
        Dictionary(
            stash.registry.flattenElements().map { ($0.element, $0.contentSpaceOrigin) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func resolveHeistIds(for elements: [AccessibilityElement]) -> Set<String> {
        let heistIdByElement = Dictionary(
            stash.registry.flattenElements().map { ($0.element, $0.heistId) },
            uniquingKeysWith: { first, _ in first }
        )
        return Set(elements.compactMap { heistIdByElement[$0] })
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
    ///
    /// This is the AX-tree authority on "is there content beyond the fold". It is
    /// stricter than the `contentSize > frame` check because UIKit/SwiftUI hosting
    /// scroll views can report inflated `contentSize` driven by safe-area, nav-bar,
    /// or scroll-edge geometry — not by actual off-screen content.
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
    ///
    /// Walks the entire VC hierarchy (not just rootVC) to find any presentation.
    /// If a VC anywhere in the tree has a `presentedViewController`, and the view's
    /// owning VC is not a descendant of the topmost presented VC, the view is obscured.
    ///
    /// This handles both root-level presentations (root presents a sheet)
    /// and nested presentations (nav child presents a modal).
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

    /// Walks the full VC tree (children + presentations) to find the topmost
    /// presented view controller. Returns nil if no presentation exists.
    ///
    /// Assumes a single active presentation chain per window (UIKit's default behavior).
    /// If multiple VCs independently present modals, the last one visited wins —
    /// acceptable because UIKit enforces a single presentation chain from the root.
    private static func topmostPresentedViewController(
        from root: UIViewController
    ) -> UIViewController? {
        var topPresented: UIViewController?

        var queue: [UIViewController] = [root]
        while !queue.isEmpty {
            let current = queue.removeFirst()

            if let presented = current.presentedViewController {
                // Walk the presentation chain to the top.
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
        if self === ancestor { return true }

        // Check if we're a child of the ancestor's child hierarchy (nav, tab, children)
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
