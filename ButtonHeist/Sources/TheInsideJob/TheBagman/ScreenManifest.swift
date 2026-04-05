#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser

extension TheBagman {

    /// Complete element map for a screen, including off-screen content.
    struct ScreenManifest {

    /// Every heistId discovered, mapped to the container it was found in.
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

    /// Safety cap on per-container scroll iterations.
    static let maxScrollsPerContainer = 200

    // MARK: - Queries

    func contains(_ heistId: String) -> Bool {
        elementContainers.keys.contains(heistId)
    }

    // MARK: - Building

    mutating func recordVisibleElements(
        _ viewportHeistIds: Set<String>,
        container: AccessibilityContainer? = nil
    ) {
        for heistId in viewportHeistIds where !elementContainers.keys.contains(heistId) {
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
} // extension TheBagman

#endif // DEBUG
#endif // canImport(UIKit)
