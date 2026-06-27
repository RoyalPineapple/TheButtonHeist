#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Live Capture

/// Visible live view from the latest observed capture.
///
/// **Ownership.** Owned by `TheStash` as viewport-tied live state; carried by
/// `Screen` only as part of an observed capture. Ephemeral index, not source of
/// truth: keyed by `TreePath` / `AccessibilityElement` / `HeistId`, rebuilt
/// wholesale on every parse, and invalidated by the next parse (last-read-wins).
/// It carries weak UIKit refs, live geometry, and per-path lookups but is
/// **never** unioned across exploration pages and must never be treated as
/// stable identity. See `docs/ARCHITECTURE.md#state-has-one-owner`.
struct LiveCapture: Equatable {
    let snapshot: Snapshot
    let dispatchReferences: DispatchReferences
    private let scrollableViewsByContainerName: [ContainerName: ScrollableViewRef]

    var hierarchy: [AccessibilityHierarchy] {
        snapshot.hierarchy
    }

    var containerNames: [AccessibilityContainer: ContainerName] {
        snapshot.containerNames
    }

    var containerNamesByPath: [TreePath: ContainerName] {
        snapshot.containerNamesByPath
    }

    var heistIdByElement: [AccessibilityElement: HeistId] {
        snapshot.heistIdByElement
    }

    var elementRefs: [HeistId: ElementRef] {
        dispatchReferences.elementRefs
    }

    var containerRefsByPath: [TreePath: ContainerRef] {
        dispatchReferences.containerRefsByPath
    }

    var containerContentFramesByPath: [TreePath: CGRect] {
        snapshot.containerContentFramesByPath
    }

    var containerScrollContentLocationsByPath: [TreePath: SemanticScreen.ScrollContentLocation] {
        snapshot.containerScrollContentLocationsByPath
    }

    var firstResponderHeistId: HeistId? {
        dispatchReferences.firstResponderHeistId
    }

    var scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef] {
        dispatchReferences.scrollableContainerViews
    }

    var scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] {
        dispatchReferences.scrollableContainerViewsByPath
    }

    init(
        hierarchy: [AccessibilityHierarchy],
        containerNames: [AccessibilityContainer: ContainerName],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdByElement: [AccessibilityElement: HeistId],
        elementRefs: [HeistId: ElementRef],
        containerRefsByPath: [TreePath: ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: CGRect] = [:],
        containerScrollContentLocationsByPath: [TreePath: SemanticScreen.ScrollContentLocation] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef],
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:],
        scrollableViewsByContainerName: [ContainerName: ScrollableViewRef]? = nil
    ) {
        let snapshot = Snapshot(
            hierarchy: hierarchy,
            containerNames: containerNames,
            containerNamesByPath: containerNamesByPath,
            heistIdByElement: heistIdByElement,
            containerContentFramesByPath: containerContentFramesByPath,
            containerScrollContentLocationsByPath: containerScrollContentLocationsByPath
        )
        let dispatchReferences = DispatchReferences(
            elementRefs: elementRefs,
            containerRefsByPath: containerRefsByPath,
            firstResponderHeistId: firstResponderHeistId,
            scrollableContainerViews: scrollableContainerViews,
            scrollableContainerViewsByPath: scrollableContainerViewsByPath
        )
        self.init(
            snapshot: snapshot,
            dispatchReferences: dispatchReferences,
            scrollableViewsByContainerName: scrollableViewsByContainerName
        )
    }

    init(
        snapshot: Snapshot,
        dispatchReferences: DispatchReferences = .empty,
        scrollableViewsByContainerName: [ContainerName: ScrollableViewRef]? = nil
    ) {
        self.snapshot = snapshot
        self.dispatchReferences = dispatchReferences
        self.scrollableViewsByContainerName = scrollableViewsByContainerName ?? Self.scrollableViewsByContainerName(
            snapshot: snapshot,
            dispatchReferences: dispatchReferences
        )
    }

    static var empty: LiveCapture {
        LiveCapture(snapshot: .empty)
    }

    var heistIds: Set<HeistId> {
        snapshot.heistIds
    }

    func contains(heistId: HeistId) -> Bool {
        snapshot.contains(heistId: heistId)
    }

    func heistId(for element: AccessibilityElement) -> HeistId? {
        snapshot.heistId(for: element)
    }

    func element(for heistId: HeistId) -> AccessibilityElement? {
        snapshot.element(for: heistId)
    }

    func object(for heistId: HeistId) -> NSObject? {
        elementRefs[heistId]?.object
    }

    func scrollView(for heistId: HeistId) -> UIScrollView? {
        elementRefs[heistId]?.scrollView
    }

    func scrollView(forContainer containerName: ContainerName) -> UIScrollView? {
        scrollableViewsByContainerName[containerName]?.view as? UIScrollView
    }

    func scrollView(for container: SemanticScreen.Container) -> UIScrollView? {
        if let containerName = container.containerName,
           let scrollView = scrollView(forContainer: containerName) {
            return scrollView
        }
        return scrollableContainerViewsByPath[container.path]?.view as? UIScrollView
            ?? containerRefsByPath[container.path]?.object as? UIScrollView
    }

    func containerObject(forPath path: TreePath) -> NSObject? {
        containerRefsByPath[path]?.object
    }

    func containerContentFrame(forPath path: TreePath) -> CGRect? {
        snapshot.containerContentFrame(forPath: path)
    }

    func containerScrollContentLocation(forPath path: TreePath) -> SemanticScreen.ScrollContentLocation? {
        snapshot.containerScrollContentLocation(forPath: path)
    }

    func scrollView(for element: SemanticScreen.Element) -> UIScrollView? {
        let visibleScrollView = contains(heistId: element.heistId) ? scrollView(for: element.heistId) : nil
        let namedScrollView = element.scrollContentLocation
            .map { $0.scrollContainer }
            .flatMap(scrollView(forContainer:))
        return visibleScrollView
            ?? namedScrollView
    }

    // MARK: - Snapshot

    /// Value-only capture metadata retained by settled semantic storage.
    ///
    /// This preserves parser hierarchy, ids, container names, and
    /// content-space evidence without carrying weak UIKit refs or live dispatch
    /// lookup tables.
    struct Snapshot: Sendable, Equatable {
        let hierarchy: [AccessibilityHierarchy]
        let containerNames: [AccessibilityContainer: ContainerName]
        let containerNamesByPath: [TreePath: ContainerName]
        let heistIdByElement: [AccessibilityElement: HeistId]
        let containerContentFramesByPath: [TreePath: CGRect]
        let containerScrollContentLocationsByPath: [TreePath: SemanticScreen.ScrollContentLocation]

        init(
            hierarchy: [AccessibilityHierarchy],
            containerNames: [AccessibilityContainer: ContainerName],
            containerNamesByPath: [TreePath: ContainerName] = [:],
            heistIdByElement: [AccessibilityElement: HeistId],
            containerContentFramesByPath: [TreePath: CGRect] = [:],
            containerScrollContentLocationsByPath: [TreePath: SemanticScreen.ScrollContentLocation] = [:]
        ) {
            self.hierarchy = hierarchy
            self.containerNames = containerNames
            self.containerNamesByPath = containerNamesByPath
            self.heistIdByElement = heistIdByElement
            self.containerContentFramesByPath = containerContentFramesByPath
            self.containerScrollContentLocationsByPath = containerScrollContentLocationsByPath
        }

        static let empty = Snapshot(
            hierarchy: [],
            containerNames: [:],
            heistIdByElement: [:]
        )

        var heistIds: Set<HeistId> {
            Set(heistIdByElement.values)
        }

        func contains(heistId: HeistId) -> Bool {
            heistIds.contains(heistId)
        }

        func heistId(for element: AccessibilityElement) -> HeistId? {
            heistIdByElement[element]
        }

        func element(for heistId: HeistId) -> AccessibilityElement? {
            heistIdByElement.first { $0.value == heistId }?.key
        }

        func containerContentFrame(forPath path: TreePath) -> CGRect? {
            containerContentFramesByPath[path]
        }

        func containerScrollContentLocation(forPath path: TreePath) -> SemanticScreen.ScrollContentLocation? {
            containerScrollContentLocationsByPath[path]
        }
    }

    // MARK: - Dispatch References

    /// Live UIKit references used for action dispatch and scroll lookup.
    ///
    /// These are viewport-local weak refs. They are only accessed through the
    /// existing main-actor stash/live-lookup path and are intentionally absent
    /// from settled semantic storage.
    struct DispatchReferences: Equatable {
        let elementRefs: [HeistId: ElementRef]
        let containerRefsByPath: [TreePath: ContainerRef]
        let firstResponderHeistId: HeistId?
        let scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef]
        let scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]

        init(
            elementRefs: [HeistId: ElementRef] = [:],
            containerRefsByPath: [TreePath: ContainerRef] = [:],
            firstResponderHeistId: HeistId? = nil,
            scrollableContainerViews: [AccessibilityContainer: ScrollableViewRef] = [:],
            scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
        ) {
            self.elementRefs = elementRefs
            self.containerRefsByPath = containerRefsByPath
            self.firstResponderHeistId = firstResponderHeistId
            self.scrollableContainerViews = scrollableContainerViews
            self.scrollableContainerViewsByPath = scrollableContainerViewsByPath
        }

        static var empty: DispatchReferences {
            DispatchReferences()
        }
    }

    struct ScrollableViewRef: Equatable {
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

    struct ElementRef: Equatable {
        /// Live UIKit object for action dispatch. Weak — nils on reuse.
        weak var object: NSObject?
        /// Nearest live scroll view for coordinate conversion.
        weak var scrollView: UIScrollView?

        static func == (lhs: ElementRef, rhs: ElementRef) -> Bool {
            lhs.object === rhs.object && lhs.scrollView === rhs.scrollView
        }
    }

    struct ContainerRef: Equatable {
        weak var object: NSObject?

        static func == (lhs: ContainerRef, rhs: ContainerRef) -> Bool {
            lhs.object === rhs.object
        }
    }

    private static func scrollableViewsByContainerName(
        snapshot: Snapshot,
        dispatchReferences: DispatchReferences
    ) -> [ContainerName: ScrollableViewRef] {
        var result: [ContainerName: ScrollableViewRef] = [:]
        var ambiguousNames = Set<ContainerName>()

        for (container, path) in snapshot.hierarchy.containerPaths {
            guard let ref = dispatchReferences.scrollableContainerViewsByPath[path]
                ?? dispatchReferences.scrollableContainerViews[container]
                ?? scrollableContainerRefFromContainerObject(dispatchReferences.containerRefsByPath[path])
            else { continue }
            guard let containerName = snapshot.containerNamesByPath[path] ?? snapshot.containerNames[container] else {
                continue
            }
            guard !ambiguousNames.contains(containerName) else { continue }
            if result[containerName] != nil {
                result[containerName] = nil
                ambiguousNames.insert(containerName)
            } else {
                result[containerName] = ref
            }
        }
        return result
    }

    private static func scrollableContainerRefFromContainerObject(
        _ ref: ContainerRef?
    ) -> ScrollableViewRef? {
        guard let scrollView = ref?.object as? UIScrollView else { return nil }
        return ScrollableViewRef(view: scrollView)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
