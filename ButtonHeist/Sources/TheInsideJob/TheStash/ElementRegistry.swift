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
        // Pass heistIds positionally — `buildNodes` consumes them by DFS
        // order through the hierarchy, matching this array's index. Keying
        // by `AccessibilityElement` would collapse hash-equal duplicates
        // (same label/traits/frame), silently merging heistIds and producing
        // duplicate leaves. Keying by parser-side `traversalIndex` is also
        // not load-bearing — that's parser-internal and not our contract.
        // The matching ordinal is just "position in parsedElements," which
        // we own.
        var resolvedHeistIds: [String] = []
        resolvedHeistIds.reserveCapacity(parsedElements.count)
        var resolvedHeistIdsByElement: [AccessibilityElement: String] = [:]
        for (parsedElement, baseHeistId) in zip(parsedElements, heistIds) {
            let context = contexts[parsedElement]
            let resolved = resolveHeistId(
                baseHeistId,
                element: parsedElement,
                contentSpaceOrigin: context?.contentSpaceOrigin
            )
            resolvedHeistIds.append(resolved)
            resolvedHeistIdsByElement[parsedElement] = resolved
        }

        reverseIndex = resolvedHeistIdsByElement
        viewportIds = Set(resolvedHeistIds)

        merge(
            hierarchy: hierarchy,
            heistIds: resolvedHeistIds,
            contexts: contexts,
            containerContentFrames: containerContentFrames,
            containersNestedInScrollView: containersNestedInScrollView,
            scrollableViews: scrollableViews
        )
    }

    /// Resolve a base heistId, appending a disambiguation suffix when an
    /// existing element with the same base id describes a different scroll
    /// position OR a different accessible identity.
    ///
    /// Two collision shapes are handled here:
    /// 1. Same identity, different scroll position (the canonical scrollable-
    ///    rows case) — append `_at_X_Y` from content-space origin.
    /// 2. Different identity, same base id (e.g. developer reused
    ///    `accessibilityIdentifier = "submit"` on a different element across a
    ///    screen transition; the first orphans before `clearScreen()` fires)
    ///    — append `_sig_<hash>` derived from the new element's stable matcher
    ///    fields so the two leaves remain distinguishable in the registry tree.
    ///
    /// Without case 2 the merge would land two leaves on the same heistId and
    /// `findElement(heistId:)` would resolve to whichever leaf the depth-first
    /// `buildIndex` walked last — silently activating the wrong element.
    private func resolveHeistId(
        _ baseHeistId: String,
        element: AccessibilityElement,
        contentSpaceOrigin: CGPoint?
    ) -> String {
        guard let existing = findElement(heistId: baseHeistId) else {
            return baseHeistId
        }

        if Self.hasSameMinimumMatcher(existing.element, element) {
            if let contentSpaceOrigin,
               let existingOrigin = existing.contentSpaceOrigin,
               !Self.sameOrigin(existingOrigin, contentSpaceOrigin) {
                return Self.contentPositionHeistId(baseHeistId, origin: contentSpaceOrigin)
            }
            return baseHeistId
        }

        // Different identity collision — prefer content-space disambiguation
        // when both elements expose an origin and the origins differ; otherwise
        // fall back to a signature suffix so the two elements stay distinct.
        if let contentSpaceOrigin,
           let existingOrigin = existing.contentSpaceOrigin,
           !Self.sameOrigin(existingOrigin, contentSpaceOrigin) {
            return Self.contentPositionHeistId(baseHeistId, origin: contentSpaceOrigin)
        }
        return Self.signatureHeistId(baseHeistId, element: element)
    }

    private static func contentPositionHeistId(_ baseHeistId: String, origin: CGPoint) -> String {
        "\(baseHeistId)_at_\(Int(origin.x.rounded()))_\(Int(origin.y.rounded()))"
    }

    /// Deterministic short signature derived from the element's stable matcher
    /// fields (identifier, label, value, stable trait names). Used to break
    /// heistId collisions when two elements share a base id but have different
    /// accessible identities and origin disambiguation is unavailable.
    private static func signatureHeistId(_ baseHeistId: String, element: AccessibilityElement) -> String {
        let stableTraits = stableTraitNames(element.traits).sorted().joined(separator: ",")
        let signature = "\(element.identifier ?? "")|\(element.label ?? "")|\(element.value ?? "")|\(stableTraits)"
        // Truncate to a short hex suffix. Hash stability across runs is not
        // required — only within a single registry's lifetime.
        let hashHex = String(UInt(bitPattern: signature.hashValue) & 0xFFFFFF, radix: 16)
        return "\(baseHeistId)_sig_\(hashHex)"
    }

    private static func hasSameMinimumMatcher(_ lhs: AccessibilityElement, _ rhs: AccessibilityElement) -> Bool {
        guard lhs.identifier == rhs.identifier,
              lhs.label == rhs.label,
              stableTraitNames(lhs.traits) == stableTraitNames(rhs.traits) else {
            return false
        }

        // Value is a fallback matcher field for otherwise generic elements,
        // but state changes should not force a new identity when label/id/role
        // already identify the same accessible thing.
        if lhs.identifier?.isEmpty == false || lhs.label?.isEmpty == false {
            return true
        }
        return lhs.value == rhs.value
    }

    private static func stableTraitNames(_ traits: UIAccessibilityTraits) -> Set<String> {
        Set(traits.traitNames).subtracting(Self.transientTraitNames)
    }

    private static let transientTraitNames: Set<String> = [
        HeistTrait.selected.rawValue,
        HeistTrait.notEnabled.rawValue,
        HeistTrait.isEditing.rawValue,
        HeistTrait.inactive.rawValue,
        HeistTrait.visited.rawValue,
        HeistTrait.updatesFrequently.rawValue,
    ]

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
            heistIds: [element.heistId],
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
}

#endif // DEBUG
#endif // canImport(UIKit)
