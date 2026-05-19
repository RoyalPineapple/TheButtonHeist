#if canImport(UIKit)
#if DEBUG
import CryptoKit
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
/// a single immutable value. The one-state invariant is: a `Screen` has two
/// named parts: `knownInterface` is targetable semantic state, and
/// `liveInterface` is the latest parse used for geometry, live object
/// dispatch, scrolling, and wire-tree projection.
///
/// Exploration accumulates a local `var union: Screen` in the caller; the
/// final union is committed by writing it back into `stash.currentScreen`.
/// TheStash never knows whether an exploration is in progress.
///
/// `name` and `id` are derived from the live interface on demand — never
/// stored — so they cannot drift from the underlying tree.
struct Screen: Equatable {

    /// HeistId → element entry. This is targetable semantic state, including
    /// exploration results that are not currently on-screen.
    let elements: [HeistId: ScreenElement]

    /// Latest parse used for geometry, live object dispatch, scrolling, and
    /// wire-tree projection. Viewport-shaped details stay behind this name;
    /// trace history is gated by `semanticHash`, not by snapshot geometry.
    let liveInterface: LiveInterface

    static var empty: Screen {
        Screen(
            elements: [:],
            liveInterface: .empty
        )
    }

    // MARK: - Init

    /// Convenience init for tests and call sites that don't have container /
    /// element index data — defaults the live indices to empty maps.
    init(
        elements: [HeistId: ScreenElement],
        hierarchy: [AccessibilityHierarchy],
        elementRefs: [HeistId: LiveInterface.ElementRef] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]
    ) {
        self.init(
            elements: elements,
            liveInterface: LiveInterface(
                hierarchy: hierarchy,
                containerStableIds: [:],
                heistIdByElement: [:],
                elementRefs: elementRefs,
                firstResponderHeistId: firstResponderHeistId,
                scrollableContainerViews: scrollableContainerViews
            )
        )
    }

    /// Memberwise init. Explicit so the convenience overload above can call it.
    init(
        elements: [HeistId: ScreenElement],
        hierarchy: [AccessibilityHierarchy],
        containerStableIds: [AccessibilityContainer: HeistContainer],
        heistIdByElement: [AccessibilityElement: HeistId],
        elementRefs: [HeistId: LiveInterface.ElementRef] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]
    ) {
        self.init(
            elements: elements,
            liveInterface: LiveInterface(
                hierarchy: hierarchy,
                containerStableIds: containerStableIds,
                heistIdByElement: heistIdByElement,
                elementRefs: elementRefs,
                firstResponderHeistId: firstResponderHeistId,
                scrollableContainerViews: scrollableContainerViews,
                scrollableViewsByStableId: Self.scrollableViewsByStableId(
                    containerStableIds: containerStableIds,
                    scrollableContainerViews: scrollableContainerViews
                )
            )
        )
    }

    init(
        elements: [HeistId: ScreenElement],
        liveInterface: LiveInterface
    ) {
        self.elements = elements
        self.liveInterface = liveInterface
    }

    private static func scrollableViewsByStableId(
        containerStableIds: [AccessibilityContainer: HeistContainer],
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]
    ) -> [HeistContainer: ScrollableViewRef] {
        Dictionary(
            uniqueKeysWithValues: scrollableContainerViews.compactMap { container, ref in
                guard let stableId = containerStableIds[container] else { return nil }
                return (stableId, ref)
            }
        )
    }

    // MARK: - Element Entry

    // An element entry for the current screen. Holds the parsed
    // `AccessibilityElement`, the assigned heistId, and the content-space
    // origin for scroll-target maths.
    //
    // `@unchecked Sendable` rationale: contains `AccessibilityElement`, whose
    // parser model is used only behind the main-actor stash at runtime.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    struct ScreenElement: @unchecked Sendable, Equatable {
        let heistId: HeistId
        /// Content-space position within nearest scrollable container.
        /// nil if not inside a scrollable.
        let contentSpaceOrigin: CGPoint?
        /// Parsed accessibility element (refreshed on every parse).
        let element: AccessibilityElement

        init(
            heistId: HeistId,
            contentSpaceOrigin: CGPoint?,
            element: AccessibilityElement
        ) {
            self.heistId = heistId
            self.contentSpaceOrigin = contentSpaceOrigin
            self.element = element
        }

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
        let elements: [HeistId: ScreenElement]

        var heistIds: Set<HeistId> {
            Set(elements.keys)
        }

        func findElement(heistId: HeistId) -> ScreenElement? {
            elements[heistId]
        }
    }

    /// Latest inflated parse used for geometry, live object dispatch,
    /// scrolling, and wire-tree construction. This is viewport-shaped: known
    /// off-screen elements are retained in `KnownInterface`, but their live
    /// UIKit refs are intentionally absent until a new parse inflates them.
    struct LiveInterface: Equatable {
        // `@unchecked Sendable` rationale: weak UIKit refs are only observed
        // behind TheStash on the main actor.
        // swiftlint:disable:next agent_unchecked_sendable_no_comment
        struct ElementRef: @unchecked Sendable, Equatable {
            /// Live UIKit object for action dispatch. Weak — nils on reuse.
            weak var object: NSObject?
            /// Nearest live scroll view for coordinate conversion.
            weak var scrollView: UIScrollView?

            static func == (lhs: ElementRef, rhs: ElementRef) -> Bool {
                lhs.object === rhs.object && lhs.scrollView === rhs.scrollView
            }
        }

        let hierarchy: [AccessibilityHierarchy]
        let containerStableIds: [AccessibilityContainer: HeistContainer]
        let heistIdByElement: [AccessibilityElement: HeistId]
        let elementRefs: [HeistId: ElementRef]
        let firstResponderHeistId: HeistId?
        let scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]
        private let scrollableViewsByStableId: [HeistContainer: ScrollableViewRef]

        init(
            hierarchy: [AccessibilityHierarchy],
            containerStableIds: [AccessibilityContainer: HeistContainer],
            heistIdByElement: [AccessibilityElement: HeistId],
            elementRefs: [HeistId: ElementRef],
            firstResponderHeistId: HeistId?,
            scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef],
            scrollableViewsByStableId: [HeistContainer: ScrollableViewRef] = [:]
        ) {
            self.hierarchy = hierarchy
            self.containerStableIds = containerStableIds
            self.heistIdByElement = heistIdByElement
            self.elementRefs = elementRefs
            self.firstResponderHeistId = firstResponderHeistId
            self.scrollableContainerViews = scrollableContainerViews
            self.scrollableViewsByStableId = scrollableViewsByStableId
        }

        static let empty = LiveInterface(
            hierarchy: [],
            containerStableIds: [:],
            heistIdByElement: [:],
            elementRefs: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )

        var heistIds: Set<HeistId> {
            Set(heistIdByElement.values)
        }

        func contains(heistId: HeistId) -> Bool {
            heistIdByElement.values.contains(heistId)
        }

        func heistId(for element: AccessibilityElement) -> HeistId? {
            heistIdByElement[element]
        }

        func object(for heistId: HeistId) -> NSObject? {
            elementRefs[heistId]?.object
        }

        func scrollView(for heistId: HeistId) -> UIScrollView? {
            elementRefs[heistId]?.scrollView
        }

        func scrollView(forContainer stableId: HeistContainer) -> UIScrollView? {
            scrollableViewsByStableId[stableId]?.view as? UIScrollView
        }

        func scrollView(for element: ScreenElement) -> UIScrollView? {
            scrollView(for: element.heistId)
        }
    }

    private struct SemanticElementFingerprint: Codable, Hashable {
        let heistId: HeistId
        let description: String
        let label: String?
        let value: String?
        let identifier: String?
        let hint: String?
        let traits: [String]
        let respondsToUserInteraction: Bool
        let customContent: [SemanticCustomContentFingerprint]
        let rotors: [String]
    }

    private struct SemanticCustomContentFingerprint: Codable, Hashable {
        let label: String
        let value: String
        let isImportant: Bool
    }

    // MARK: - Derived Properties

    var knownInterface: KnownInterface {
        KnownInterface(elements: elements)
    }

    /// Derive the screen name from the first header element in latest live
    /// traversal order. Not stored — recomputed on access so it cannot drift
    /// from the parser tree.
    var name: String? {
        liveInterface.hierarchy.sortedElements.first {
            $0.traits.contains(.header) && $0.label != nil
        }?.label
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var id: String? {
        TheScore.slugify(name)
    }

    /// The heistId set of every element in the committed semantic screen.
    var knownIds: Set<HeistId> {
        knownInterface.heistIds
    }

    /// The heistId set backed by the latest parsed live hierarchy.
    var visibleIds: Set<HeistId> {
        liveInterface.heistIds
    }

    /// Hash of the known semantic accessibility state. Deliberately excludes
    /// viewport-only facts like frame, activation point, visible ids, and
    /// scroll offset so a user can scroll a stable screen without producing
    /// history events.
    var semanticHash: String {
        let fingerprints = elements.values
            .map(Self.semanticElementFingerprint)
            .sorted { $0.heistId < $1.heistId }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(fingerprints)) ?? Data()
        return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Lookup

    /// O(1) heistId lookup.
    func findElement(heistId: HeistId) -> ScreenElement? {
        knownInterface.findElement(heistId: heistId)
    }

    /// A pure view of this screen restricted to ids present in the latest live
    /// hierarchy. This keeps the same live interface and drops known-only
    /// semantic entries retained from exploration.
    var visibleOnly: Screen {
        let visibleIds = liveInterface.heistIds
        return Screen(
            elements: elements.filter { visibleIds.contains($0.key) },
            liveInterface: liveInterface
        )
    }

    /// Elements in deterministic matcher/diagnostic order: live hierarchy
    /// order first, followed by known-only entries sorted by heistId.
    var orderedElements: [ScreenElement] {
        var seen = Set<String>()
        var ordered: [ScreenElement] = []
        ordered.reserveCapacity(elements.count)
        for (element, _) in liveInterface.hierarchy.elements {
            guard let heistId = liveInterface.heistIdByElement[element],
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

    private static func semanticElementFingerprint(_ entry: ScreenElement) -> SemanticElementFingerprint {
        let element = entry.element
        let customContent = element.customContent
            .filter { !$0.label.isEmpty || !$0.value.isEmpty }
            .map {
                SemanticCustomContentFingerprint(
                    label: $0.label,
                    value: $0.value,
                    isImportant: $0.isImportant
                )
            }
        return SemanticElementFingerprint(
            heistId: entry.heistId,
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: element.traits.namesIncludingUnknownBits,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: customContent,
            rotors: element.customRotors.map(\.name).filter { !$0.isEmpty }
        )
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
    /// `liveInterface` takes `other`'s. It is the latest inflated parse, not
    /// a unionable tree — accumulating it across scrolled pages would keep
    /// stale UIKit refs and geometry alive. Code that needs the "all elements
    /// ever seen on this screen" view reads `knownInterface`, not the live
    /// interface.
    func merging(_ other: Screen) -> Screen {
        let mergedElements = elements.merging(other.elements) { _, new in new }
        return Screen(
            elements: mergedElements,
            liveInterface: other.liveInterface
        )
    }

    /// Apply a fresh visible parse. If the visible ids are already known, keep
    /// explored offscreen memory and replace only the live interface.
    /// Previously visible non-scroll elements that disappear are dropped; empty
    /// or unknown refreshes replace the screen.
    func refreshingVisibleState(with visibleRefresh: Screen) -> Screen {
        guard !visibleRefresh.visibleIds.isEmpty,
              visibleRefresh.visibleIds.isSubset(of: knownIds) else {
            return visibleRefresh
        }
        let disappearedVisibleIds = visibleIds.subtracting(visibleRefresh.visibleIds)
        let staleVisibleIds = disappearedVisibleIds.filter {
            elements[$0]?.contentSpaceOrigin == nil
        }
        guard !staleVisibleIds.isEmpty else {
            return merging(visibleRefresh)
        }
        let refreshed = merging(visibleRefresh)
        return Screen(
            elements: refreshed.elements.filter { !staleVisibleIds.contains($0.key) },
            liveInterface: refreshed.liveInterface
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
