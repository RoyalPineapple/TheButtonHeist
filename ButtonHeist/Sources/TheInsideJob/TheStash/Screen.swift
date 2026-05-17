#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Screen Value Type

/// Immutable interface state with pure value semantics.
///
/// `Screen` is the currency type for the resolution layer post-0.2.25. It
/// replaces the dozen mutable fields previously held on TheStash
/// (`heistIdIndex`, `currentHierarchy`, `reverseIndex`, `knownIds`,
/// `currentContainers`, `firstResponderHeistId`, `lastScreenName`, ...) with
/// a single immutable value. The one-state invariant is: a `Screen` carries
/// both targetable known elements and the latest visible capture.
/// KnownInterface is targetable semantic state; InteractionSnapshot is the
/// latest parse used for interaction.
///
/// Exploration accumulates a local `var union: Screen` in the caller; the
/// final union is committed by writing it back into `stash.currentScreen`.
/// TheStash never knows whether an exploration is in progress.
///
/// `name` and `id` are derived from the hierarchy on demand — never stored
/// — so they cannot drift from the underlying tree.
struct Screen: Equatable {

    /// HeistId → element entry. This is targetable semantic state, including
    /// exploration results that are not currently on-screen.
    let elements: [String: ScreenElement]

    /// The latest parsed accessibility hierarchy. Used for scroll-target
    /// discovery, wire tree construction, and interaction state.
    let hierarchy: [AccessibilityHierarchy]

    /// Stable id for every container reachable from `hierarchy`. Computed
    /// once during parse so wire-tree construction and tree-edit detection
    /// can ask for a container's identity without recomputing.
    let containerStableIds: [AccessibilityContainer: String]

    /// HeistId assigned to each `AccessibilityElement` in this parse. Allows
    /// wire-tree construction to walk `hierarchy` and resolve each leaf to
    /// its heistId without rebuilding the assignment.
    let heistIdByElement: [AccessibilityElement: String]

    /// HeistId of the element whose live object is currently first responder.
    let firstResponderHeistId: String?

    /// Maps scrollable containers from the hierarchy to their backing UIView.
    /// Stored as `ScrollableViewRef` so `Screen` can be `Equatable` — UIView
    /// itself isn't — while keeping the live reference available for scroll
    /// dispatch.
    let scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]

    static var empty: Screen {
        Screen(
            elements: [:],
            hierarchy: [],
            containerStableIds: [:],
            heistIdByElement: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )
    }

    // MARK: - Init

    /// Convenience init for tests and call sites that don't have container /
    /// element index data — defaults the new indices to empty maps.
    init(
        elements: [String: ScreenElement],
        hierarchy: [AccessibilityHierarchy],
        firstResponderHeistId: String?,
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]
    ) {
        self.init(
            elements: elements,
            hierarchy: hierarchy,
            containerStableIds: [:],
            heistIdByElement: [:],
            firstResponderHeistId: firstResponderHeistId,
            scrollableContainerViews: scrollableContainerViews
        )
    }

    /// Memberwise init. Explicit so the convenience overload above can call it.
    init(
        elements: [String: ScreenElement],
        hierarchy: [AccessibilityHierarchy],
        containerStableIds: [AccessibilityContainer: String],
        heistIdByElement: [AccessibilityElement: String],
        firstResponderHeistId: String?,
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]
    ) {
        self.elements = elements
        self.hierarchy = hierarchy
        self.containerStableIds = containerStableIds
        self.heistIdByElement = heistIdByElement
        self.firstResponderHeistId = firstResponderHeistId
        self.scrollableContainerViews = scrollableContainerViews
    }

    // MARK: - Element Entry

    // An element entry for the current screen. Holds the parsed
    // `AccessibilityElement`, the assigned heistId, the content-space origin
    // for scroll-target maths, and weak references to the live UIKit objects.
    //
    // `@unchecked Sendable` rationale: holds `weak NSObject` / `weak UIScrollView`
    // refs. The type lives behind `@MainActor` (TheStash) at every runtime
    // touchpoint, so weak refs are only observed on the main actor. Equatable
    // compares heistId + parsed element + origin only; weak object identity is
    // intentionally excluded.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    struct ScreenElement: @unchecked Sendable, Equatable {
        let heistId: String
        /// Content-space position within nearest scrollable container.
        /// nil if not inside a scrollable.
        let contentSpaceOrigin: CGPoint?
        /// Parsed accessibility element (refreshed on every parse).
        let element: AccessibilityElement
        /// Live UIKit object for action dispatch. Weak — nils on cell reuse.
        weak var object: NSObject?
        /// Parent scroll view for coordinate conversion. Weak — outlives children.
        weak var scrollView: UIScrollView?

        static func == (lhs: ScreenElement, rhs: ScreenElement) -> Bool {
            lhs.heistId == rhs.heistId
                && lhs.contentSpaceOrigin == rhs.contentSpaceOrigin
                && lhs.element == rhs.element
        }
    }

    // Wrapper around a weak `UIView` so we can store the map in an `Equatable`
    // value type. Equality compares the live view's object identity; equal if
    // both are nil.
    // `@unchecked Sendable` rationale: UIView is non-Sendable but the wrapper
    // is only touched on `@MainActor`.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    struct ScrollableViewRef: @unchecked Sendable, Equatable {
        weak var view: UIView?

        static func == (lhs: ScrollableViewRef, rhs: ScrollableViewRef) -> Bool {
            switch (lhs.view, rhs.view) {
            case (nil, nil):
                return true
            case let (left?, right?):
                return left === right
            default:
                return false
            }
        }
    }

    /// Targetable semantic state retained across exploration.
    struct KnownInterface: Equatable {
        let elements: [String: ScreenElement]

        var heistIds: Set<String> {
            Set(elements.keys)
        }

        func findElement(heistId: String) -> ScreenElement? {
            elements[heistId]
        }
    }

    /// Latest parse used for geometry, live object dispatch, scrolling, and
    /// wire-tree construction.
    struct InteractionSnapshot: Equatable {
        let hierarchy: [AccessibilityHierarchy]
        let containerStableIds: [AccessibilityContainer: String]
        let heistIdByElement: [AccessibilityElement: String]
        let firstResponderHeistId: String?
        let scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]

        var heistIds: Set<String> {
            Set(heistIdByElement.values)
        }

        func contains(heistId: String) -> Bool {
            heistIdByElement.values.contains(heistId)
        }

        func heistId(for element: AccessibilityElement) -> String? {
            heistIdByElement[element]
        }
    }

    // MARK: - Derived Properties

    var knownInterface: KnownInterface {
        KnownInterface(elements: elements)
    }

    var interactionSnapshot: InteractionSnapshot {
        InteractionSnapshot(
            hierarchy: hierarchy,
            containerStableIds: containerStableIds,
            heistIdByElement: heistIdByElement,
            firstResponderHeistId: firstResponderHeistId,
            scrollableContainerViews: scrollableContainerViews
        )
    }

    /// Derive the screen name from the first header element in traversal
    /// order. Not stored — recomputed on access so it cannot drift from
    /// `hierarchy`.
    var name: String? {
        hierarchy.sortedElements.first {
            $0.traits.contains(.header) && $0.label != nil
        }?.label
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var id: String? {
        TheScore.slugify(name)
    }

    /// The heistId set of every element in the committed semantic screen.
    var knownIds: Set<String> {
        knownInterface.heistIds
    }

    /// The heistId set backed by the latest parsed live hierarchy.
    var visibleIds: Set<String> {
        interactionSnapshot.heistIds
    }

    // MARK: - Lookup

    /// O(1) heistId lookup.
    func findElement(heistId: String) -> ScreenElement? {
        knownInterface.findElement(heistId: heistId)
    }

    /// A pure view of this screen restricted to ids present in the latest live
    /// hierarchy. This keeps the same InteractionSnapshot and drops known-only
    /// semantic entries retained from exploration.
    var visibleOnly: Screen {
        let visibleIds = interactionSnapshot.heistIds
        return Screen(
            elements: elements.filter { visibleIds.contains($0.key) },
            hierarchy: hierarchy,
            containerStableIds: containerStableIds,
            heistIdByElement: heistIdByElement,
            firstResponderHeistId: firstResponderHeistId,
            scrollableContainerViews: scrollableContainerViews
        )
    }

    /// Elements in deterministic matcher/diagnostic order: live hierarchy
    /// order first, followed by known-only entries sorted by heistId.
    var orderedElements: [ScreenElement] {
        var seen = Set<String>()
        var ordered: [ScreenElement] = []
        ordered.reserveCapacity(elements.count)
        for (element, _) in hierarchy.elements {
            guard let heistId = heistIdByElement[element],
                  let entry = elements[heistId],
                  seen.insert(heistId).inserted else { continue }
            ordered.append(entry)
        }
        let remaining = elements
            .filter { !seen.contains($0.key) }
            .map(\.value)
            .sorted { $0.heistId < $1.heistId }
        ordered.append(contentsOf: remaining)
        return ordered
    }

    // MARK: - Merge

    /// Union two screens. Used by exploration to accumulate the full tree
    /// across many parses.
    ///
    /// Conflict rule: **last read always wins.** When the same heistId appears
    /// in both `self` and `other`, the entire `ScreenElement` from `other`
    /// replaces the one from `self` — no field-level merging, no special case
    /// to preserve a previously-recorded `contentSpaceOrigin`. The most recent
    /// observation is the source of truth.
    ///
    /// `hierarchy`, `firstResponderHeistId`, container indices, and live-view
    /// refs all take `other`'s. `hierarchy` is the live snapshot, not a
    /// unionable tree — accumulating it across scrolled pages would mix stale
    /// geometry with live geometry. Code that needs the "all elements ever
    /// seen on this screen" view reads `elements`, not `hierarchy`.
    func merging(_ other: Screen) -> Screen {
        let mergedElements = elements.merging(other.elements) { _, new in new }
        return Screen(
            elements: mergedElements,
            hierarchy: other.hierarchy,
            containerStableIds: other.containerStableIds,
            heistIdByElement: other.heistIdByElement,
            firstResponderHeistId: other.firstResponderHeistId,
            scrollableContainerViews: other.scrollableContainerViews
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
