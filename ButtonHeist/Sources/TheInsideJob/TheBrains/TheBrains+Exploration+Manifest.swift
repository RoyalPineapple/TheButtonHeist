#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser

extension TheBrains {

    // MARK: - Screen Manifest

    /// Bookkeeping for a single exploration pass.
    ///
    /// Only fields that are actually consumed downstream (by `ExploreResult` or
    /// explore-loop control flow) live here. Anything that was "tracked for future
    /// use" was removed — add fields back when they have a real consumer.
    struct ScreenManifest {

        /// Containers that have been fully explored.
        var exploredContainers = Set<AccessibilityContainer>()

        /// Containers discovered but not yet explored.
        var pendingContainers = Set<AccessibilityContainer>()

        /// Total scrollByPage calls during exploration. Surfaced as `ExploreResult.scrollCount`.
        var scrollCount = 0

        /// Containers skipped because their accessibility fingerprint matched the cached value.
        /// Not surfaced on the wire today; kept for logging and diagnostics inside the server.
        var skippedContainers = 0

        /// Containers skipped because they are behind a presented view controller.
        /// Surfaced as `ExploreResult.containersSkippedObscured`.
        var skippedObscuredContainers = 0

        /// Wall-clock time spent exploring, in seconds. Surfaced as `ExploreResult.explorationTime`.
        var explorationTime: TimeInterval = 0

        /// Safety cap on per-container scroll iterations.
        static let maxScrollsPerContainer = 200

        // MARK: - Building

        mutating func markExplored(_ container: AccessibilityContainer) {
            exploredContainers.insert(container)
            pendingContainers.remove(container)
        }

        mutating func addPendingContainers(_ containers: [AccessibilityContainer]) {
            pendingContainers.formUnion(containers.filter { !exploredContainers.contains($0) })
        }
    }
} // extension TheBrains

#endif // DEBUG
#endif // canImport(UIKit)
