#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

extension TheStash {

    // MARK: - Tree Node

    /// A node in the persistent registry tree. Lifted out of `ElementRegistry`
    /// to satisfy SwiftLint's `nesting` rule (max one level deep).
    enum RegistryNode {
        /// A leaf element with its UIKit context.
        case element(ScreenElement)
        /// A container with its children.
        case container(RegistryContainerEntry, children: [RegistryNode])
    }

    /// A container in the registry tree, identified by a stable id that
    /// persists across parses even if the underlying frame drifts.
    struct RegistryContainerEntry {
        /// Stable identity for this container across parses. Computed from
        /// the container's type and topology — see `stableId(for:...)`.
        let stableId: String
        /// Most recently observed parser container value. Frame and content
        /// size may shift across parses, but stableId stays put.
        var container: AccessibilityContainer
    }

    /// Path to a node in the registry tree — each element is the child index
    /// at that depth. An empty path is invalid (no root has the empty path).
    typealias RegistryPath = [Int]

    /// The element registry — a persistent tree of elements and containers
    /// that survives across parses.
    ///
    /// `roots` is the canonical source of truth. Every element ever observed
    /// for the current screen lives somewhere in the tree, even if the live
    /// parse no longer mentions it (scrolled out, filtered by overlay
    /// presentation, etc.). Containers are display-only: agents target
    /// leaf elements, never containers directly.
    ///
    /// Invariants enforced by API:
    /// - Every leaf in `roots` has an entry in `elementByHeistId` pointing to its RegistryPath.
    /// - `viewportIds` is a subset of the heistIds reachable from `roots`.
    /// - `reverseIndex` is rebuilt in sync with the live parse, not the persistent tree.
    /// - A container is present iff it has at least one element descendant.
    struct ElementRegistry {

    // MARK: - Storage

    /// The persistent tree. Source of truth for every element known to this
    /// screen, including off-screen / non-live elements.
    var roots: [RegistryNode] = []

    /// O(1) heistId → tree path lookup. Rebuilt on every mutation.
    var elementByHeistId: [String: RegistryPath] = [:]

    /// HeistIds currently visible in the device viewport — rebuilt each refresh cycle.
    var viewportIds: Set<String> = []

    /// HeistId of the element whose live object is currently first responder, if any.
    /// Rebuilt each refresh cycle — no view hierarchy walk needed.
    var firstResponderHeistId: String?

    /// Reverse index: AccessibilityElement → heistId for the current visible set.
    /// Scoped to the live parse, not the persistent tree — used by matchers
    /// to fast-path hierarchy hits to their resolved heistId.
    var reverseIndex: [AccessibilityElement: String] = [:]

    // MARK: - Mutation

    /// Apply a parse result: resolve heistIds with content-space disambiguation,
    /// merge into the persistent tree, refresh viewport/reverseIndex.
    ///
    /// Live state (viewport, reverseIndex) is rebuilt from the incoming parse;
    /// persistent state (the tree) is merged.
    mutating func register(
        parsedElements: [AccessibilityElement],
        heistIds: [String],
        contexts: [AccessibilityElement: ElementContext],
        hierarchy: [AccessibilityHierarchy],
        containerContentFrames: [AccessibilityContainer: CGRect],
        containersNestedInScrollView: Set<AccessibilityContainer> = [],
        scrollableViews: [AccessibilityContainer: UIView] = [:]
    ) {
        var resolvedHeistIds: [AccessibilityElement: String] = [:]
        for (parsedElement, baseHeistId) in zip(parsedElements, heistIds) {
            let context = contexts[parsedElement]
            let resolved = resolveHeistId(baseHeistId, contentSpaceOrigin: context?.contentSpaceOrigin)
            resolvedHeistIds[parsedElement] = resolved
        }

        reverseIndex = resolvedHeistIds
        viewportIds = Set(resolvedHeistIds.values)

        merge(
            hierarchy: hierarchy,
            heistIds: resolvedHeistIds,
            contexts: contexts,
            containerContentFrames: containerContentFrames,
            containersNestedInScrollView: containersNestedInScrollView,
            scrollableViews: scrollableViews
        )
    }

    /// Resolve a base heistId, appending a content-space suffix when an
    /// existing element with the same base id occupies a different position.
    /// Disambiguates cell-reuse cases where the same `accessibilityIdentifier`
    /// shows up at multiple scroll offsets.
    private func resolveHeistId(_ baseHeistId: String, contentSpaceOrigin: CGPoint?) -> String {
        guard let contentSpaceOrigin,
              let existing = findElement(heistId: baseHeistId),
              let existingOrigin = existing.contentSpaceOrigin,
              !Self.sameOrigin(existingOrigin, contentSpaceOrigin) else {
            return baseHeistId
        }
        return "\(baseHeistId)_at_\(Int(contentSpaceOrigin.x.rounded()))_\(Int(contentSpaceOrigin.y.rounded()))"
    }

    private static func sameOrigin(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
    }

    /// Clear everything — suspend or full reset.
    mutating func clear() {
        roots.removeAll()
        elementByHeistId.removeAll()
        viewportIds.removeAll()
        reverseIndex.removeAll()
        firstResponderHeistId = nil
    }

    /// Clear screen-level state on screen change.
    mutating func clearScreen() {
        roots.removeAll()
        elementByHeistId.removeAll()
        reverseIndex.removeAll()
    }

    /// Prune elements not in the given set (post-explore cleanup).
    mutating func prune(keeping seen: Set<String>) {
        pruneTree(keeping: seen)
    }

    /// Test-only: insert a single element at root level by synthesizing a
    /// minimal hierarchy and merging it. Used by unit tests that need to
    /// pre-populate the registry without going through TheBurglar's parse
    /// pipeline.
    mutating func insertForTesting(_ element: ScreenElement) {
        let context = ElementContext(
            contentSpaceOrigin: element.contentSpaceOrigin,
            scrollView: element.scrollView,
            object: element.object
        )
        merge(
            hierarchy: [.element(element.element, traversalIndex: roots.count)],
            heistIds: [element.element: element.heistId],
            contexts: [element.element: context],
            containerContentFrames: [:]
        )
    }
    }

    /// Per-element context gathered during the hierarchy walk.
    struct ElementContext {
        let contentSpaceOrigin: CGPoint?
        weak var scrollView: UIScrollView?
        weak var object: NSObject?
    }
} // extension TheStash

#endif // DEBUG
#endif // canImport(UIKit)
