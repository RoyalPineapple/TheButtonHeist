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
        private let elementIndex: LiveElementIndex

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

    var heistIdsByPath: [TreePath: HeistId] {
        snapshot.heistIdsByPath
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

    var scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] {
        dispatchReferences.scrollableContainerViewsByPath
    }

    init(
        hierarchy: [AccessibilityHierarchy],
        containerNames: [AccessibilityContainer: ContainerName],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdByElement: [AccessibilityElement: HeistId],
        heistIdsByPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: ElementRef],
        containerRefsByPath: [TreePath: ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: CGRect] = [:],
        containerScrollContentLocationsByPath: [TreePath: SemanticScreen.ScrollContentLocation] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
    ) {
        let snapshot = Snapshot(
            hierarchy: hierarchy,
            containerNames: containerNames,
            containerNamesByPath: containerNamesByPath,
            heistIdByElement: heistIdByElement,
            heistIdsByPath: heistIdsByPath,
            containerContentFramesByPath: containerContentFramesByPath,
            containerScrollContentLocationsByPath: containerScrollContentLocationsByPath
        )
        let dispatchReferences = DispatchReferences(
            elementRefs: elementRefs,
            containerRefsByPath: containerRefsByPath,
            firstResponderHeistId: firstResponderHeistId,
            scrollableContainerViewsByPath: scrollableContainerViewsByPath
        )
        self.init(
            snapshot: snapshot,
            dispatchReferences: dispatchReferences
        )
    }

    init(
        snapshot: Snapshot,
        dispatchReferences: DispatchReferences = .empty
    ) {
        self.snapshot = snapshot
        self.dispatchReferences = dispatchReferences
        elementIndex = LiveElementIndex(
            snapshot: snapshot,
            dispatchReferences: dispatchReferences
        )
    }

    static var empty: LiveCapture {
        LiveCapture(snapshot: .empty)
    }

    var heistIds: Set<HeistId> {
        elementIndex.heistIds
    }

    func contains(heistId: HeistId) -> Bool {
        elementIndex.contains(heistId: heistId)
    }

    func heistId(for element: AccessibilityElement) -> HeistId? {
        elementIndex.heistId(for: element)
    }

    func heistId(forPath path: TreePath) -> HeistId? {
        elementIndex.heistId(forPath: path)
    }

    func element(for heistId: HeistId) -> AccessibilityElement? {
        elementIndex.element(for: heistId)
    }

    func elementEntry(for heistId: HeistId) -> LiveElementEntry? {
        elementIndex.elementEntry(for: heistId)
    }

    func orderedElementEntries() -> [LiveElementEntry] {
        elementIndex.orderedElementEntries
    }

    func object(for heistId: HeistId) -> NSObject? {
        elementIndex.object(for: heistId)
    }

    func heistId(matching object: NSObject) -> HeistId? {
        elementIndex.heistId(matching: object)
    }

    func scrollView(for heistId: HeistId) -> UIScrollView? {
        elementIndex.scrollView(for: heistId)
    }

    func scrollView(for container: SemanticScreen.Container) -> UIScrollView? {
        scrollView(forContainerPath: container.path)
    }

    func containerObject(forPath path: TreePath) -> NSObject? {
        elementIndex.containerObject(forPath: path)
    }

    func containerContentFrame(forPath path: TreePath) -> CGRect? {
        snapshot.containerContentFrame(forPath: path)
    }

    func containerScrollContentLocation(forPath path: TreePath) -> SemanticScreen.ScrollContentLocation? {
        snapshot.containerScrollContentLocation(forPath: path)
    }

    func scrollView(for element: SemanticScreen.Element) -> UIScrollView? {
        let visibleScrollView = contains(heistId: element.heistId) ? scrollView(for: element.heistId) : nil
        let pathScrollView = element.scrollContentLocation
            .flatMap { scrollView(forContainerPath: $0.scrollContainerPath) }
        return visibleScrollView
            ?? pathScrollView
    }

    func scrollView(forContainerPath path: TreePath) -> UIScrollView? {
        elementIndex.scrollableView(forContainerPath: path) as? UIScrollView
            ?? elementIndex.containerObject(forPath: path) as? UIScrollView
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
        let heistIdsByPath: [TreePath: HeistId]
        let containerContentFramesByPath: [TreePath: CGRect]
        let containerScrollContentLocationsByPath: [TreePath: SemanticScreen.ScrollContentLocation]

        init(
            hierarchy: [AccessibilityHierarchy],
            containerNames: [AccessibilityContainer: ContainerName],
            containerNamesByPath: [TreePath: ContainerName] = [:],
            heistIdByElement: [AccessibilityElement: HeistId],
            heistIdsByPath: [TreePath: HeistId] = [:],
            containerContentFramesByPath: [TreePath: CGRect] = [:],
            containerScrollContentLocationsByPath: [TreePath: SemanticScreen.ScrollContentLocation] = [:]
        ) {
            self.hierarchy = hierarchy
            self.containerNames = containerNames
            self.containerNamesByPath = containerNamesByPath.isEmpty
                ? Self.deriveContainerNamesByPath(hierarchy: hierarchy, containerNames: containerNames)
                : containerNamesByPath
            self.heistIdByElement = heistIdByElement
            self.heistIdsByPath = heistIdsByPath.isEmpty
                ? Self.deriveHeistIdsByPath(hierarchy: hierarchy, heistIdByElement: heistIdByElement)
                : heistIdsByPath
            self.containerContentFramesByPath = containerContentFramesByPath
            self.containerScrollContentLocationsByPath = containerScrollContentLocationsByPath
        }

        static let empty = Snapshot(
            hierarchy: [],
            containerNames: [:],
            heistIdByElement: [:]
        )

        var heistIds: Set<HeistId> {
            Set(heistIdsByPath.values)
        }

        func contains(heistId: HeistId) -> Bool {
            heistIds.contains(heistId)
        }

        func heistId(for element: AccessibilityElement) -> HeistId? {
            heistIdByElement[element]
        }

        func element(for heistId: HeistId) -> AccessibilityElement? {
            guard let path = heistIdsByPath.first(where: { $0.value == heistId })?.key,
                  case .element(let element, _) = hierarchy.node(at: path)
            else { return nil }
            return element
        }

        func containerContentFrame(forPath path: TreePath) -> CGRect? {
            containerContentFramesByPath[path]
        }

        func containerScrollContentLocation(forPath path: TreePath) -> SemanticScreen.ScrollContentLocation? {
            containerScrollContentLocationsByPath[path]
        }

        private static func deriveHeistIdsByPath(
            hierarchy: [AccessibilityHierarchy],
            heistIdByElement: [AccessibilityElement: HeistId]
        ) -> [TreePath: HeistId] {
            Dictionary(
                uniqueKeysWithValues: hierarchy.pathIndexedElements.compactMap { item in
                    heistIdByElement[item.element].map { (item.path, $0) }
                }
            )
        }

        private static func deriveContainerNamesByPath(
            hierarchy: [AccessibilityHierarchy],
            containerNames: [AccessibilityContainer: ContainerName]
        ) -> [TreePath: ContainerName] {
            Dictionary(
                uniqueKeysWithValues: hierarchy.containerPaths.compactMap { item in
                    containerNames[item.container].map { (item.path, $0) }
                }
            )
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
        let scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]

        init(
            elementRefs: [HeistId: ElementRef] = [:],
            containerRefsByPath: [TreePath: ContainerRef] = [:],
            firstResponderHeistId: HeistId? = nil,
            scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
        ) {
            self.elementRefs = elementRefs
            self.containerRefsByPath = containerRefsByPath
            self.firstResponderHeistId = firstResponderHeistId
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

    struct LiveElementEntry: Equatable {
        let path: TreePath
        let heistId: HeistId
        let element: AccessibilityElement
        let ref: ElementRef?
    }

    // MARK: - Live Element Index

    struct LiveElementIndex: Equatable {
        private let entriesByPath: [TreePath: LiveElementEntry]
        private let pathsByHeistId: [HeistId: TreePath]
        private let orderedPaths: [TreePath]
        private let containerRefsByPath: [TreePath: ContainerRef]
        private let scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]

        init(
            snapshot: Snapshot,
            dispatchReferences: DispatchReferences
        ) {
            var entriesByPath: [TreePath: LiveElementEntry] = [:]
            var pathsByHeistId: [HeistId: TreePath] = [:]
            var orderedPaths: [TreePath] = []

            for item in snapshot.hierarchy.pathIndexedElements {
                guard let heistId = snapshot.heistIdsByPath[item.path],
                      pathsByHeistId[heistId] == nil
                else { continue }
                let entry = LiveElementEntry(
                    path: item.path,
                    heistId: heistId,
                    element: item.element,
                    ref: dispatchReferences.elementRefs[heistId]
                )
                entriesByPath[item.path] = entry
                pathsByHeistId[heistId] = item.path
                orderedPaths.append(item.path)
            }

            self.entriesByPath = entriesByPath
            self.pathsByHeistId = pathsByHeistId
            self.orderedPaths = orderedPaths
            containerRefsByPath = dispatchReferences.containerRefsByPath
            scrollableContainerViewsByPath = dispatchReferences.scrollableContainerViewsByPath
        }

        var heistIds: Set<HeistId> {
            Set(pathsByHeistId.keys)
        }

        var orderedElementEntries: [LiveElementEntry] {
            orderedPaths.compactMap { entriesByPath[$0] }
        }

        func contains(heistId: HeistId) -> Bool {
            pathsByHeistId[heistId] != nil
        }

        func heistId(for element: AccessibilityElement) -> HeistId? {
            orderedElementEntries.first { $0.element == element }?.heistId
        }

        func heistId(forPath path: TreePath) -> HeistId? {
            entriesByPath[path]?.heistId
        }

        func element(for heistId: HeistId) -> AccessibilityElement? {
            elementEntry(for: heistId)?.element
        }

        func elementEntry(for heistId: HeistId) -> LiveElementEntry? {
            pathsByHeistId[heistId].flatMap { entriesByPath[$0] }
        }

        func object(for heistId: HeistId) -> NSObject? {
            elementEntry(for: heistId)?.ref?.object
        }

        func heistId(matching object: NSObject) -> HeistId? {
            orderedElementEntries.first { entry in
                entry.ref?.object === object
            }?.heistId
        }

        func scrollView(for heistId: HeistId) -> UIScrollView? {
            elementEntry(for: heistId)?.ref?.scrollView
        }

        func containerObject(forPath path: TreePath) -> NSObject? {
            containerRefsByPath[path]?.object
        }

        func scrollableView(forContainerPath path: TreePath) -> UIView? {
            scrollableContainerViewsByPath[path]?.view
        }
    }

}

private extension Array where Element == AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        guard let rootIndex = path.indices.first,
              indices.contains(rootIndex)
        else { return nil }
        guard path.indices.count > 1 else { return self[rootIndex] }
        return self[rootIndex].node(at: TreePath([Int](path.indices.dropFirst())))
    }
}

private extension AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        guard !path.indices.isEmpty else { return self }
        guard case .container(_, let children) = self,
              let childIndex = path.indices.first,
              children.indices.contains(childIndex)
        else { return nil }
        return children[childIndex].node(at: TreePath([Int](path.indices.dropFirst())))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
