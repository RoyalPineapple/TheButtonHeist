#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - Screen Manifest
//
// Maps every element on the current screen — including off-screen content inside
// scrollable containers. Built by scrolling each container to its limits and back.
// Scroll positions are saved and restored; the user sees no visual change.
//
// Uses the reconciliation algorithms (stitchPage, findOverlap, contentFingerprint)
// for element deduplication and stagnation detection. Container subtree fingerprints
// from the accessibility hierarchy drive the skip-on-re-explore fast path — all
// signals come from the accessibility domain, not UIKit plumbing.
//
// Used by:
//   get_interface --full → full census (target: nil), returns manifest
//   scroll_to_visible → targeted search (target: ElementTarget), stops early
//   post-action → automatic re-explore, skips unchanged containers

/// Complete element map for a screen, including off-screen content.
struct ScreenManifest {

    /// Every heistId discovered, mapped to the container it was found in.
    /// Elements not inside a scrollable container map to nil.
    var elementContainers: [String: AccessibilityContainer?] = [:]

    /// Containers that have been fully explored.
    var exploredContainers = Set<AccessibilityContainer>()

    /// Total scrollByPage calls during exploration.
    var scrollCount = 0

    /// Containers skipped because their accessibility fingerprint matched the cached value.
    var skippedContainers = 0

    /// Wall-clock time spent exploring, in seconds.
    var explorationTime: TimeInterval = 0

    /// Total unique heistIds discovered.
    var elementCount: Int { elementContainers.count }

    /// Whether all known scrollable containers have been explored.
    var isComplete: Bool { pendingContainers.isEmpty }

    /// Containers discovered but not yet explored.
    var pendingContainers = Set<AccessibilityContainer>()

    /// Safety cap on per-container scroll iterations. Prevents runaway scrolling
    /// in pathological layouts (e.g. infinite-scroll feeds). If a container exceeds
    /// this, the census for that container is silently truncated.
    static let maxScrollsPerContainer = 200

    // MARK: - Queries

    func contains(_ heistId: String) -> Bool {
        elementContainers[heistId] != nil
    }

    // MARK: - Building

    mutating func recordVisibleElements(
        _ viewportHeistIds: Set<String>,
        container: AccessibilityContainer? = nil
    ) {
        for heistId in viewportHeistIds where elementContainers[heistId] == nil {
            elementContainers.updateValue(container, forKey: heistId)
        }
    }

    mutating func markExplored(_ container: AccessibilityContainer) {
        exploredContainers.insert(container)
        pendingContainers.remove(container)
    }

    mutating func addPendingContainers(_ containers: [AccessibilityContainer]) {
        pendingContainers.formUnion(containers.filter { !exploredContainers.contains($0) })
    }
}

// MARK: - Exploration

extension TheBagman {

    /// Scroll all scrollable containers to discover every element on screen.
    /// With a target: stops early when the target is found. Without: full census.
    /// Scroll positions are saved and restored. Unchanged containers are skipped
    /// via cached accessibility fingerprints.
    func exploreScreen(target: ElementTarget? = nil) async -> ScreenManifest {
        let startTime = CACurrentMediaTime()
        var manifest = ScreenManifest()

        refresh()
        manifest.recordVisibleElements(viewportHeistIds)

        // Early exit if target is already visible
        if let target, resolveFirstMatch(target) != nil {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return manifest
        }

        guard let safecracker else {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return manifest
        }

        manifest.addPendingContainers(currentHierarchy.scrollableContainers)
        var containerFingerprints = currentHierarchy.containerFingerprints

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
                      let view = scrollableContainerViews[container],
                      let scrollView = view as? UIScrollView,
                      view.window != nil else {
                    manifest.markExplored(container)
                    continue
                }

                // Skip unchanged containers via fingerprint cache.
                // Targeted searches always scroll — the target may be off-screen.
                let currentFingerprint = containerFingerprints[container] ?? 0
                if let cached = containerExploreStates[container],
                   cached.visibleSubtreeFingerprint == currentFingerprint,
                   target == nil {
                    exploreCycleIds?.formUnion(cached.discoveredHeistIds)
                    manifest.markExplored(container)
                    manifest.skippedContainers += 1
                    continue
                }

                // Check for off-screen content using the container's accessibility
                // metadata. The .scrollable type carries contentSize from the parser.
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

                // Save the visual scroll position — the content point at the top-left of
                // the visible area. Raw contentOffset drifts when adjustedContentInset
                // changes during explore (nav bar collapse, search bar hide).
                let savedVisualOrigin = CGPoint(
                    x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
                    y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top
                )
                let direction: UIAccessibilityScrollDirection = hasHOverflow ? .right : .down

                // O(1) origin lookup — rebuilt after each refresh() to reflect new elements.
                var originByElement = buildOriginIndex()

                let initialPage = visibleElementsInContainer(container)
                var accumulated = initialPage.elements
                var accumulatedOrigins = initialPage.origins

                // Scroll forward page by page. Stop when stitchPage reports no
                // new elements (the page is entirely overlap with accumulated).
                for _ in 0..<ScreenManifest.maxScrollsPerContainer {
                    let moved = safecracker.scrollByPage(scrollView, direction: direction, animated: false)
                    guard moved else { break }
                    manifest.scrollCount += 1
                    await tripwire.yieldFrames(2)
                    refresh()
                    originByElement = buildOriginIndex()
                    manifest.recordVisibleElements(viewportHeistIds, container: container)

                    let page = visibleElementsInContainer(container)
                    let result = stitchPage(
                        accumulated: accumulated,
                        accumulatedOrigins: accumulatedOrigins,
                        page: page.elements,
                        pageOrigins: page.origins
                    )
                    accumulated = result.elements
                    // originByElement values are CGPoint? — subscript returns CGPoint??,
                    // so ?? nil flattens to CGPoint? (missing element → nil origin).
                    accumulatedOrigins = accumulated.map { originByElement[$0] ?? nil }

                    if result.inserted.isEmpty { break }

                    // Early exit if target found
                    if let target, resolveFirstMatch(target) != nil {
                        Self.restoreVisualOrigin(savedVisualOrigin, in: scrollView)
                        await tripwire.yieldFrames(2)
                        refresh()
                        containerFingerprints = currentHierarchy.containerFingerprints
                        manifest.markExplored(container)
                        let fingerprint = containerFingerprints[container] ?? 0
                        updateContainerExploreCache(container, fingerprint: fingerprint, accumulated: accumulated, accumulatedOrigins: accumulatedOrigins)
                        manifest.explorationTime = CACurrentMediaTime() - startTime
                        return manifest
                    }
                }

                // Restore the visual scroll position, accounting for any inset changes
                Self.restoreVisualOrigin(savedVisualOrigin, in: scrollView)
                await tripwire.yieldFrames(2)
                refresh()
                containerFingerprints = currentHierarchy.containerFingerprints
                manifest.markExplored(container)

                let fingerprint = containerFingerprints[container] ?? 0
                updateContainerExploreCache(container, fingerprint: fingerprint, accumulated: accumulated, accumulatedOrigins: accumulatedOrigins)

                let newContainers = currentHierarchy.scrollableContainers
                    .filter { !manifest.exploredContainers.contains($0) && !manifest.pendingContainers.contains($0) }
                manifest.addPendingContainers(newContainers)
            }
        }

        manifest.explorationTime = CACurrentMediaTime() - startTime
        return manifest
    }

    // MARK: - Helpers

    /// Elements and their content-space origins for a given container.
    private struct ContainerPage {
        let elements: [AccessibilityElement]
        let origins: [CGPoint?]
    }

    /// Visible elements in a scrollable container, in traversal order.
    private func visibleElementsInContainer(_ container: AccessibilityContainer) -> ContainerPage {
        let pairs = currentHierarchy.elements.compactMap { element, _ -> (element: AccessibilityElement, origin: CGPoint?)? in
            guard let heistId = elementToHeistId[element],
                  viewportHeistIds.contains(heistId),
                  let entry = screenElements[heistId],
                  isElementInContainer(entry, container: container) else { return nil }
            return (element: entry.element, origin: entry.contentSpaceOrigin)
        }
        return ContainerPage(elements: pairs.map(\.element), origins: pairs.map(\.origin))
    }

    /// Check whether a screen element belongs to a given scrollable container
    /// by verifying its scroll view matches the container's backing view.
    private func isElementInContainer(_ element: ScreenElement, container: AccessibilityContainer) -> Bool {
        guard let containerView = scrollableContainerViews[container] as? UIScrollView,
              let elementScrollView = element.scrollView else { return false }
        return containerView === elementScrollView
    }

    /// Build an O(1) lookup from AccessibilityElement to its content-space origin.
    /// Rebuilt after each refresh() to reflect newly-discovered elements.
    private func buildOriginIndex() -> [AccessibilityElement: CGPoint?] {
        Dictionary(
            screenElements.values.map { ($0.element, $0.contentSpaceOrigin) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Scroll Position Restore

    /// Restore a scroll view to the same visual position, compensating for any
    /// `adjustedContentInset` changes that occurred during explore (nav bar
    /// collapse, search bar hide, safe area shifts).
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

    /// Cache a container's explore state using a pre-computed fingerprint.
    private func updateContainerExploreCache(
        _ container: AccessibilityContainer,
        fingerprint: Int,
        accumulated: [AccessibilityElement],
        accumulatedOrigins: [CGPoint?]
    ) {
        let accFingerprint = accumulatedContentFingerprint(
            elements: accumulated, origins: accumulatedOrigins
        )
        let heistIds = Set(screenElements.filter { isElementInContainer($0.value, container: container) }.keys)
        containerExploreStates[container] = ContainerExploreState(
            visibleSubtreeFingerprint: fingerprint,
            accumulatedFingerprint: accFingerprint,
            discoveredHeistIds: heistIds
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
