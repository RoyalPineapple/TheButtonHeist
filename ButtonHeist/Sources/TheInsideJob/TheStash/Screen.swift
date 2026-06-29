#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Screen Value Type

/// Immutable observed capture used by settle, discovery, trace, and tests.
/// It bundles one parser result's semantic projection with the visible live
/// view needed to interpret that result. The stash stores those halves
/// separately; `Screen` itself is not the long-lived world model.
///
/// `name` and `id` are derived from the live interface on demand — never
/// stored — so they cannot drift from the underlying tree.
struct Screen: Equatable {

    let semantic: SemanticScreen
    let liveCapture: LiveCapture

    typealias ScrollMembership = SemanticScreen.ScrollMembership
    typealias ObservedScrollContentActivationPoint = SemanticScreen.ObservedScrollContentActivationPoint
    typealias ScreenElement = SemanticScreen.Element
    typealias KnownInterface = SemanticScreen
    typealias ScrollableViewRef = LiveCapture.ScrollableViewRef
    typealias ElementRef = LiveCapture.ElementRef
    typealias ContainerRef = LiveCapture.ContainerRef

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
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
    ) {
        let liveCapture = LiveCapture(
            hierarchy: hierarchy,
            elementRefs: elementRefs,
        containerRefsByPath: [:],
        containerContentFramesByPath: [:],
        containerScrollMembershipsByPath: [:],
        containerObservedScrollContentActivationPointsByPath: [:],
        scrollInventoriesByPath: [:],
        firstResponderHeistId: firstResponderHeistId,
        scrollableContainerViewsByPath: scrollableContainerViewsByPath
        )
        self.init(
            semantic: SemanticScreen(
                elements: elements,
                containers: Self.semanticContainers(from: liveCapture)
            ),
            liveCapture: liveCapture
        )
    }

    /// Memberwise init. Explicit so the convenience overload above can call it.
    init(
        elements: [HeistId: ScreenElement],
        hierarchy: [AccessibilityHierarchy],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdsByPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: ElementRef] = [:],
        containerRefsByPath: [TreePath: ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: CGRect] = [:],
        containerScrollMembershipsByPath: [TreePath: ScrollMembership] = [:],
        containerObservedScrollContentActivationPointsByPath: [TreePath: ObservedScrollContentActivationPoint] = [:],
        scrollInventoriesByPath: [TreePath: ScrollInventory] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
    ) {
        let liveCapture = LiveCapture(
            hierarchy: hierarchy,
            containerNamesByPath: containerNamesByPath,
            heistIdsByPath: heistIdsByPath,
            elementRefs: elementRefs,
            containerRefsByPath: containerRefsByPath,
            containerContentFramesByPath: containerContentFramesByPath,
            containerScrollMembershipsByPath: containerScrollMembershipsByPath,
            containerObservedScrollContentActivationPointsByPath: containerObservedScrollContentActivationPointsByPath,
            scrollInventoriesByPath: scrollInventoriesByPath,
            firstResponderHeistId: firstResponderHeistId,
            scrollableContainerViewsByPath: scrollableContainerViewsByPath
        )
        self.init(
            semantic: SemanticScreen(
                elements: elements,
                containers: Self.semanticContainers(from: liveCapture)
            ),
            liveCapture: liveCapture
        )
    }

    init(
        semantic: SemanticScreen,
        liveCapture: LiveCapture
    ) {
        self.semantic = semantic
        self.liveCapture = liveCapture
    }

    init(
        semantic: SemanticScreen,
        captureSnapshot: LiveCapture.Snapshot
    ) {
        self.init(
            semantic: semantic,
            liveCapture: LiveCapture(snapshot: captureSnapshot)
        )
    }

    // MARK: - Derived Properties

    var knownInterface: KnownInterface {
        semantic
    }

    /// Derive the screen name from the topmost header element in latest live
    /// traversal order. Not stored — recomputed on access so it cannot drift
    /// from the parser tree.
    var name: String? {
        liveCapture.hierarchy.sortedElements
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

    /// Count of elements retained in committed semantic memory.
    var knownElementCount: Int {
        semantic.elements.count
    }

    /// The heistId set backed by the latest parsed live hierarchy.
    var visibleIds: Set<HeistId> {
        liveCapture.heistIds
    }

    /// Hash of the settled semantic accessibility state. Deliberately excludes
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

    /// Semantic containers in deterministic traversal order.
    var orderedContainers: [SemanticScreen.Container] {
        semantic.containers.values
            .sorted { $0.path.indices.lexicographicallyPrecedes($1.path.indices) }
    }

    /// A pure projection restricted to ids present in the latest visible live
    /// hierarchy. This keeps the same live capture and drops known-only
    /// semantic entries retained from exploration.
    var visibleOnly: Screen {
        let visibleIds = liveCapture.heistIds
        let visibleContainerPaths = Set(liveCapture.hierarchy.containerPaths.map(\.path))
        return Screen(
            semantic: SemanticScreen(
                elements: semantic.elements.filter { visibleIds.contains($0.key) },
                containers: semantic.containers.filter { visibleContainerPaths.contains($0.key) }
            ),
            liveCapture: liveCapture
        )
    }

    /// Elements in deterministic matcher/diagnostic order: live hierarchy
    /// order first, followed by known-only entries sorted by heistId.
    var orderedElements: [ScreenElement] {
        var seen = Set<HeistId>()
        var ordered: [ScreenElement] = []
        ordered.reserveCapacity(semantic.elements.count)
        for liveEntry in liveCapture.orderedElementEntries() {
            guard let entry = semantic.elements[liveEntry.heistId],
                  seen.insert(liveEntry.heistId).inserted else { continue }
            ordered.append(entry)
        }
        let remaining = semantic.elements
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
    /// replaces the one from `self` — no field-level merging. The most recent
    /// observation is the source of truth.
    ///
    /// `liveCapture` takes `other`'s. It is the latest visible live view, not a
    /// unionable tree — accumulating it across scrolled pages would keep stale
    /// UIKit refs and geometry alive. Code that needs the "all elements ever
    /// seen on this screen" view reads `knownInterface`, not the live interface.
    func merging(_ other: Screen) -> Screen {
        let mergedElements = semantic.elements.merging(other.semantic.elements) { _, new in new }
        let mergedContainers = semantic.containers.merging(other.semantic.containers) { _, new in new }
        return Screen(
            semantic: SemanticScreen(
                elements: mergedElements,
                containers: mergedContainers
            ),
            liveCapture: other.liveCapture
        )
    }

    private static func semanticContainers(from liveCapture: LiveCapture) -> [TreePath: SemanticScreen.Container] {
        Dictionary(
            uniqueKeysWithValues: liveCapture.hierarchy.containerPaths.map { item in
                (
                    item.path,
                    SemanticScreen.Container(
                        container: item.container,
                        path: item.path,
                        containerName: liveCapture.containerNamesByPath[item.path],
                        contentFrame: liveCapture.containerContentFrame(forPath: item.path),
                        scrollMembership: liveCapture.containerScrollMembership(forPath: item.path),
                        observedScrollContentActivationPoint: liveCapture.containerObservedScrollContentActivationPoint(
                            forPath: item.path
                        ),
                        scrollInventory: liveCapture.scrollInventory(forPath: item.path)
                    )
                )
            }
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
