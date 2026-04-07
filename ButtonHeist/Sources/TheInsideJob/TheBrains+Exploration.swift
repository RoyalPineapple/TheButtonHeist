#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

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
        let accumulatedFingerprint: Int
        let discoveredHeistIds: Set<String>
    }

    /// Explore and prune: track heistIds across all apply() calls, then remove unseen.
    func exploreAndPrune(target: ElementTarget? = nil) async -> ScreenManifest {
        exploreCycleIds = stash.registry.viewportIds
        let manifest = await exploreScreen(target: target)
        if let seen = exploreCycleIds {
            stash.registry.prune(keeping: seen)
        }
        exploreCycleIds = nil
        return manifest
    }

    /// Scroll all scrollable containers to discover every element on screen.
    func exploreScreen(target: ElementTarget? = nil) async -> ScreenManifest {
        let startTime = CACurrentMediaTime()
        var manifest = ScreenManifest()

        stash.refresh()
        manifest.recordVisibleElements(stash.registry.viewportIds)

        if let target, stash.resolveFirstMatch(target) != nil {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return manifest
        }

        manifest.addPendingContainers(stash.currentHierarchy.scrollableContainers)
        var containerFingerprints = stash.currentHierarchy.containerFingerprints

        while !manifest.pendingContainers.isEmpty {
            let batch = manifest.pendingContainers.sorted { first, second in
                guard case .scrollable(let contentSizeA) = first.type,
                      case .scrollable(let contentSizeB) = second.type else { return false }
                let overflowA = max(0, contentSizeA.width - first.frame.width) + max(0, contentSizeA.height - first.frame.height)
                let overflowB = max(0, contentSizeB.width - second.frame.width) + max(0, contentSizeB.height - second.frame.height)
                return overflowA > overflowB
            }

            for container in batch {
                guard case .scrollable = container.type,
                      let view = stash.scrollableContainerViews[container],
                      let scrollView = view as? UIScrollView,
                      view.window != nil else {
                    manifest.markExplored(container)
                    continue
                }

                if Self.isObscuredByPresentation(view: view) {
                    manifest.markExplored(container)
                    manifest.skippedObscuredContainers += 1
                    continue
                }

                let currentFingerprint = containerFingerprints[container] ?? 0
                if let cached = containerExploreStates[container],
                   cached.visibleSubtreeFingerprint == currentFingerprint,
                   target == nil {
                    exploreCycleIds?.formUnion(cached.discoveredHeistIds)
                    manifest.markExplored(container)
                    manifest.skippedContainers += 1
                    continue
                }

                guard case .scrollable(let contentSize) = container.type else {
                    manifest.markExplored(container)
                    continue
                }
                let hasHOverflow = contentSize.width > container.frame.width + 1
                let hasVOverflow = contentSize.height > container.frame.height + 1
                guard hasHOverflow || hasVOverflow else {
                    manifest.markExplored(container)
                    continue
                }

                let found = await exploreContainer(
                    container: container, scrollView: scrollView,
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
        scrollView: UIScrollView,
        hasHOverflow: Bool,
        hasVOverflow: Bool,
        target: ElementTarget?,
        manifest: inout ScreenManifest,
        containerFingerprints: inout [AccessibilityContainer: Int]
    ) async -> Bool {
        let savedVisualOrigin = CGPoint(
            x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
            y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        )
        let direction: UIAccessibilityScrollDirection = hasHOverflow ? .right : .down

        let leadingEdge: ScrollEdge = hasHOverflow ? .left : .top
        if safecracker.scrollToEdge(scrollView, edge: leadingEdge, animated: false) {
            await tripwire.yieldFrames(2)
            refresh()
            manifest.recordVisibleElements(stash.registry.viewportIds, container: container)
        }

        var originByElement = buildOriginIndex()

        let initialPage = visibleElementsInContainer(container)
        var accumulated = initialPage.elements
        var accumulatedOrigins = initialPage.origins

        for _ in 0..<ScreenManifest.maxScrollsPerContainer {
            let moved = safecracker.scrollByPage(scrollView, direction: direction, animated: false)
            guard moved else { break }
            manifest.scrollCount += 1
            await tripwire.yieldFrames(2)
            refresh()
            originByElement = buildOriginIndex()
            manifest.recordVisibleElements(stash.registry.viewportIds, container: container)

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
                    scrollView: scrollView, savedVisualOrigin: savedVisualOrigin,
                    container: container, accumulated: accumulated, accumulatedOrigins: accumulatedOrigins,
                    manifest: &manifest, containerFingerprints: &containerFingerprints
                )
                return true
            }
        }

        await restoreAndCache(
            scrollView: scrollView, savedVisualOrigin: savedVisualOrigin,
            container: container, accumulated: accumulated, accumulatedOrigins: accumulatedOrigins,
            manifest: &manifest, containerFingerprints: &containerFingerprints
        )

        let newContainers = stash.currentHierarchy.scrollableContainers
            .filter { !manifest.exploredContainers.contains($0) && !manifest.pendingContainers.contains($0) }
        manifest.addPendingContainers(newContainers)
        return false
    }

    // MARK: - Exploration Helpers

    private func restoreAndCache(
        scrollView: UIScrollView,
        savedVisualOrigin: CGPoint,
        container: AccessibilityContainer,
        accumulated: [AccessibilityElement],
        accumulatedOrigins: [CGPoint?],
        manifest: inout ScreenManifest,
        containerFingerprints: inout [AccessibilityContainer: Int]
    ) async {
        Self.restoreVisualOrigin(savedVisualOrigin, in: scrollView)
        await tripwire.yieldFrames(2)
        stash.refresh()
        containerFingerprints = stash.currentHierarchy.containerFingerprints
        manifest.markExplored(container)
        let fingerprint = containerFingerprints[container] ?? 0
        updateContainerExploreCache(container, fingerprint: fingerprint, accumulated: accumulated, accumulatedOrigins: accumulatedOrigins)
    }

    private func visibleElementsInContainer(_ container: AccessibilityContainer) -> ContainerPage {
        let pairs = stash.currentHierarchy.elements.compactMap { element, _ -> (element: AccessibilityElement, origin: CGPoint?)? in
            guard let heistId = stash.registry.reverseIndex[element],
                  stash.registry.viewportIds.contains(heistId),
                  let entry = stash.registry.elements[heistId],
                  isElementInContainer(entry, container: container) else { return nil }
            return (element: entry.element, origin: entry.contentSpaceOrigin)
        }
        return ContainerPage(elements: pairs.map(\.element), origins: pairs.map(\.origin))
    }

    private func isElementInContainer(_ element: TheStash.ScreenElement, container: AccessibilityContainer) -> Bool {
        guard let containerView = stash.scrollableContainerViews[container] as? UIScrollView,
              let elementScrollView = element.scrollView else { return false }
        return containerView === elementScrollView
    }

    private func buildOriginIndex() -> [AccessibilityElement: CGPoint?] {
        Dictionary(
            stash.registry.elements.values.map { ($0.element, $0.contentSpaceOrigin) },
            uniquingKeysWith: { first, _ in first }
        )
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
        accumulated: [AccessibilityElement],
        accumulatedOrigins: [CGPoint?]
    ) {
        let accFingerprint = accumulatedContentFingerprint(
            elements: accumulated, origins: accumulatedOrigins
        )
        let heistIds = Set(stash.registry.elements.filter { isElementInContainer($0.value, container: container) }.keys)
        containerExploreStates[container] = ContainerExploreState(
            visibleSubtreeFingerprint: fingerprint,
            accumulatedFingerprint: accFingerprint,
            discoveredHeistIds: heistIds
        )
    }

    // MARK: - Presentation Obscuring

    /// Returns true if the view is behind a presented view controller.
    ///
    /// Walks the entire VC hierarchy (not just rootVC) to find any presentation.
    /// If a VC anywhere in the tree has a `presentedViewController`, and the view's
    /// owning VC is not a descendant of the topmost presented VC, the view is obscured.
    ///
    /// This handles both root-level presentations (Square Register: root presents
    /// receipt sheet) and nested presentations (nav child presents a modal).
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
