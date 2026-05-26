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
/// two named values: `semantic` is durable targetable state, and `liveCapture`
/// is the latest parse used for geometry, live object dispatch, scrolling,
/// and wire-tree projection.
///
/// Exploration accumulates a local `var union: Screen` in the caller; the
/// final union is committed by writing it back into `stash.currentScreen`.
/// TheStash never knows whether an exploration is in progress.
///
/// `name` and `id` are derived from the live interface on demand — never
/// stored — so they cannot drift from the underlying tree.
struct Screen: Equatable {

    let semantic: SemanticScreen
    let liveCapture: LiveCapture

    typealias ScrollContentLocation = SemanticScreen.ScrollContentLocation
    typealias ScreenElement = SemanticScreen.Element
    typealias KnownInterface = SemanticScreen
    typealias LiveInterface = LiveCapture
    typealias ScrollableViewRef = LiveCapture.ScrollableViewRef
    typealias ElementRef = LiveCapture.ElementRef
    typealias ContainerRef = LiveCapture.ContainerRef

    /// Compatibility view for callers that still read `Screen.elements`.
    var elements: [HeistId: ScreenElement] {
        semantic.elements
    }

    /// Compatibility view for callers that still read `Screen.liveInterface`.
    var liveInterface: LiveInterface {
        liveCapture
    }

    static var empty: Screen {
        Screen(
            semantic: .empty,
            liveCapture: .empty
        )
    }

    // MARK: - Init

    /// Convenience init for tests and call sites that don't have container /
    /// element index data — defaults the live indices to empty maps.
    init(
        elements: [HeistId: ScreenElement],
        hierarchy: [AccessibilityHierarchy],
        elementRefs: [HeistId: ElementRef] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef],
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
    ) {
        self.init(
            elements: elements,
            liveInterface: LiveCapture(
                hierarchy: hierarchy,
                containerStableIds: [:],
                heistIdByElement: [:],
                heistIdByElementPath: [:],
                elementRefs: elementRefs,
                containerRefsByPath: [:],
                containerContentFramesByPath: [:],
                firstResponderHeistId: firstResponderHeistId,
                scrollableContainerViews: scrollableContainerViews,
                scrollableContainerViewsByPath: scrollableContainerViewsByPath
            )
        )
    }

    /// Memberwise init. Explicit so the convenience overload above can call it.
    init(
        elements: [HeistId: ScreenElement],
        hierarchy: [AccessibilityHierarchy],
        containerStableIds: [AccessibilityContainer: HeistContainer],
        containerStableIdsByPath: [TreePath: HeistContainer] = [:],
        heistIdByElement: [AccessibilityElement: HeistId],
        heistIdByElementPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: ElementRef] = [:],
        containerRefsByPath: [TreePath: ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: CGRect] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef],
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
    ) {
        self.init(
            elements: elements,
            liveInterface: LiveCapture(
                hierarchy: hierarchy,
                containerStableIds: containerStableIds,
                containerStableIdsByPath: containerStableIdsByPath,
                heistIdByElement: heistIdByElement,
                heistIdByElementPath: heistIdByElementPath,
                elementRefs: elementRefs,
                containerRefsByPath: containerRefsByPath,
                containerContentFramesByPath: containerContentFramesByPath,
                firstResponderHeistId: firstResponderHeistId,
                scrollableContainerViews: scrollableContainerViews,
                scrollableContainerViewsByPath: scrollableContainerViewsByPath
            )
        )
    }

    init(
        elements: [HeistId: ScreenElement],
        liveInterface: LiveInterface
    ) {
        self.init(
            semantic: SemanticScreen(elements: elements),
            liveCapture: liveInterface
        )
    }

    init(
        semantic: SemanticScreen,
        liveCapture: LiveCapture
    ) {
        self.semantic = semantic
        self.liveCapture = liveCapture
    }

    // MARK: - Derived Properties

    var knownInterface: KnownInterface {
        semantic
    }

    /// Derive the screen name from the topmost header element in latest live
    /// traversal order. Not stored — recomputed on access so it cannot drift
    /// from the parser tree.
    var name: String? {
        liveInterface.hierarchy.sortedElements
            .enumerated()
            .compactMap { index, element -> (index: Int, element: AccessibilityElement)? in
                guard element.traits.contains(.header), element.label != nil else { return nil }
                return (index, element)
            }
            .min { left, right in
                let leftFrame = left.element.shape.frame
                let rightFrame = right.element.shape.frame
                if leftFrame.minY != rightFrame.minY { return leftFrame.minY < rightFrame.minY }
                if leftFrame.minX != rightFrame.minX { return leftFrame.minX < rightFrame.minX }
                return left.index < right.index
            }?
            .element
            .label
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
        semantic.semanticHash
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
    /// `liveInterface` takes `other`'s. It is the latest live parse, not
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
    /// previously explored offscreen memory and replace only the live interface.
    /// Elements that were visible in the prior parse and disappear in the fresh
    /// parse are dropped; scroll position alone is not semantic retention.
    func refreshingVisibleState(with visibleRefresh: Screen) -> Screen {
        guard !visibleRefresh.visibleIds.isEmpty,
              visibleRefresh.visibleIds.isSubset(of: knownIds) else {
            return visibleRefresh
        }
        let disappearedVisibleIds = visibleIds.subtracting(visibleRefresh.visibleIds)
        guard !disappearedVisibleIds.isEmpty else {
            return merging(visibleRefresh)
        }
        let refreshed = merging(visibleRefresh)
        return Screen(
            elements: refreshed.elements.filter { !disappearedVisibleIds.contains($0.key) },
            liveInterface: refreshed.liveInterface
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
