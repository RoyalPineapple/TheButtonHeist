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

                let savedVisualOrigin = CGPoint(
                    x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
                    y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
                )
                let direction: UIAccessibilityScrollDirection = hasHOverflow ? .right : .down

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
                        manifest.explorationTime = CACurrentMediaTime() - startTime
                        return manifest
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
            }
        }

        manifest.explorationTime = CACurrentMediaTime() - startTime
        return manifest
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
}

#endif // DEBUG
#endif // canImport(UIKit)
