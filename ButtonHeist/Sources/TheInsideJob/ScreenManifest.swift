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
// Used by:
//   explore command  → full census (target: nil), returns manifest
//   scroll_to_visible → targeted search (target: ElementTarget), stops early

/// Complete element map for a screen, including off-screen content.
struct ScreenManifest {

    /// Every heistId discovered, mapped to the container it was found in.
    /// Elements not inside a scrollable container map to nil.
    var elementContainers: [String: AccessibilityContainer?] = [:]

    /// Containers that have been fully explored.
    var exploredContainers = Set<AccessibilityContainer>()

    /// Total scrollByPage calls during exploration.
    var scrollCount = 0

    /// Wall-clock time spent exploring, in seconds.
    var explorationTime: TimeInterval = 0

    /// Total unique heistIds discovered.
    var elementCount: Int { elementContainers.count }

    /// Whether all known scrollable containers have been explored.
    var isComplete: Bool { pendingContainers.isEmpty }

    /// Containers discovered but not yet explored.
    var pendingContainers = Set<AccessibilityContainer>()

    // MARK: - Queries

    func contains(_ heistId: String) -> Bool {
        elementContainers[heistId] != nil
    }

    func container(for heistId: String) -> AccessibilityContainer?? {
        elementContainers[heistId]
    }

    // MARK: - Building

    mutating func recordVisibleElements(
        _ onScreen: Set<String>,
        container: AccessibilityContainer? = nil
    ) {
        for heistId in onScreen where elementContainers[heistId] == nil {
            elementContainers[heistId] = container
        }
    }

    mutating func markExplored(_ container: AccessibilityContainer) {
        exploredContainers.insert(container)
        pendingContainers.remove(container)
    }

    mutating func addPendingContainers(_ containers: [AccessibilityContainer]) {
        for c in containers where !exploredContainers.contains(c) {
            pendingContainers.insert(c)
        }
    }
}

// MARK: - Exploration

extension TheBagman {

    /// Explore the current screen by scrolling all scrollable containers.
    /// With a target: stops early when the target is found (element-first).
    /// Without a target: complete census of every element on screen.
    /// Scroll positions are saved and restored in both cases.
    func exploreScreen(target: ElementTarget? = nil) async -> ScreenManifest {
        let startTime = CACurrentMediaTime()
        var manifest = ScreenManifest()

        refreshAccessibilityData()
        manifest.recordVisibleElements(onScreen)

        // Early exit if target is already visible
        if let target, resolveFirstMatch(target) != nil {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return manifest
        }

        guard let safecracker else {
            manifest.explorationTime = CACurrentMediaTime() - startTime
            return manifest
        }

        manifest.addPendingContainers(findScrollableContainers())

        while !manifest.pendingContainers.isEmpty {

        // Sort: largest overflow first (outermost containers reveal inner ones)
        let batch = manifest.pendingContainers.sorted { a, b in
            guard case .scrollable(let csA) = a.type,
                  case .scrollable(let csB) = b.type else { return false }
            let overflowA = max(0, csA.width - a.frame.width) + max(0, csA.height - a.frame.height)
            let overflowB = max(0, csB.width - b.frame.width) + max(0, csB.height - b.frame.height)
            return overflowA > overflowB
        }

        for container in batch {
            guard case .scrollable(let contentSize) = container.type,
                  let view = scrollableContainerViews[container],
                  let scrollView = view as? UIScrollView,
                  view.window != nil else {
                manifest.markExplored(container)
                continue
            }

            // Skip containers with no off-screen content
            let hasHOverflow = contentSize.width > scrollView.frame.width + 1
            let hasVOverflow = contentSize.height > scrollView.frame.height + 1
            guard hasHOverflow || hasVOverflow else {
                manifest.markExplored(container)
                continue
            }

            let savedOffset = scrollView.contentOffset
            let direction: UIAccessibilityScrollDirection = hasHOverflow ? .right : .down

            // Scroll forward page by page. Stop when scrollByPage returns false
            // (UIScrollView edge) OR no new elements appear (stagnation — catches
            // UICollectionView edge bouncing where scrollByPage keeps returning true).
            for _ in 0..<200 {
                let beforeCount = manifest.elementCount
                let moved = safecracker.scrollByPage(scrollView, direction: direction, animated: false)
                guard moved else { break }
                manifest.scrollCount += 1
                await tripwire.yieldFrames(2)
                refreshAccessibilityData()
                manifest.recordVisibleElements(onScreen, container: container)

                // No new elements = content exhausted
                if manifest.elementCount == beforeCount { break }

                // Early exit if target found
                if let target, resolveFirstMatch(target) != nil {
                    scrollView.setContentOffset(savedOffset, animated: false)
                    await tripwire.yieldFrames(2)
                    refreshAccessibilityData()
                    manifest.markExplored(container)
                    manifest.explorationTime = CACurrentMediaTime() - startTime
                    return manifest
                }
            }

            // Restore position
            scrollView.setContentOffset(savedOffset, animated: false)
            await tripwire.yieldFrames(2)
            refreshAccessibilityData()
            manifest.markExplored(container)

            // Check for newly-revealed inner containers
            let newContainers = findScrollableContainers()
                .filter { !manifest.exploredContainers.contains($0) && !manifest.pendingContainers.contains($0) }
            manifest.addPendingContainers(newContainers)
        }

        } // while pendingContainers

        manifest.explorationTime = CACurrentMediaTime() - startTime
        return manifest
    }

    // MARK: - Helpers

    private func findScrollableContainers() -> [AccessibilityContainer] {
        var result: [AccessibilityContainer] = []
        cachedHierarchy.reducedHierarchy(()) { _, node in
            if case .container(let container, _) = node,
               case .scrollable = container.type {
                result.append(container)
            }
        }
        return result
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
