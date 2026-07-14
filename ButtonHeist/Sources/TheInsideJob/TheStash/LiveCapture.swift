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
/// `InterfaceObservation` only as part of an observed capture. `Snapshot` owns
/// value identity and geometry; `DispatchReferences` owns viewport-local weak
/// UIKit references. Neither is unioned across exploration pages or treated as
/// stable identity. See `docs/ARCHITECTURE.md#state-has-one-owner`.
struct LiveCapture {
    let snapshot: Snapshot
    let dispatchReferences: DispatchReferences

    var hierarchy: [AccessibilityHierarchy] {
        snapshot.hierarchy
    }

    var containerNamesByPath: [TreePath: ContainerName] {
        snapshot.containerNamesByPath
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

    var containerContentFramesByPath: [TreePath: ContentRect] {
        snapshot.containerContentFramesByPath
    }

    var containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership] {
        snapshot.containerScrollMembershipsByPath
    }

    var containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint] {
        snapshot.containerObservedScrollContentActivationPointsByPath
    }

    var scrollInventoriesByPath: [TreePath: ScrollInventory] {
        snapshot.scrollInventoriesByPath
    }

    var firstResponderHeistId: HeistId? {
        snapshot.firstResponderHeistId
    }

    var scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] {
        dispatchReferences.scrollableContainerViewsByPath
    }

    private init(snapshot: Snapshot, dispatchReferences: DispatchReferences) {
        self.snapshot = snapshot
        self.dispatchReferences = dispatchReferences
    }

    static func build(
        validating tree: InterfaceTree,
        dispatchReferences: DispatchReferences = .empty
    ) throws -> LiveCapture {
        try validate(
            validating: tree,
            dispatchReferences: dispatchReferences
        )
        return LiveCapture(
            snapshot: tree.viewportCapture,
            dispatchReferences: dispatchReferences
        )
    }

    var heistIds: Set<HeistId> {
        snapshot.heistIds
    }

    func contains(heistId: HeistId) -> Bool {
        snapshot.contains(heistId: heistId)
    }

    func heistId(forPath path: TreePath) -> HeistId? {
        snapshot.heistIdsByPath[path]
    }

    func element(for heistId: HeistId) -> AccessibilityElement? {
        snapshot.element(for: heistId)
    }

    func elementEntry(for heistId: HeistId) -> LiveElementEntry? {
        guard let path = snapshot.path(for: heistId),
              case .element(let element, _) = snapshot.hierarchy.node(at: path)
        else { return nil }
        return LiveElementEntry(path: path, heistId: heistId, element: element)
    }

    func object(for heistId: HeistId) -> NSObject? {
        dispatchReferences.elementRefs[heistId]?.object
    }

    func heistId(matching object: NSObject) -> HeistId? {
        snapshot.orderedHeistIds.first { heistId in
            dispatchReferences.elementRefs[heistId]?.object === object
        }
    }

    func scrollView(for heistId: HeistId) -> UIScrollView? {
        dispatchReferences.elementRefs[heistId]?.scrollView
    }

    func scrollView(for container: InterfaceTree.Container) -> UIScrollView? {
        scrollView(forContainerPath: container.path)
    }

    func containerObject(forPath path: TreePath) -> NSObject? {
        dispatchReferences.containerRefsByPath[path]?.object
    }

    func containerContentFrame(forPath path: TreePath) -> ContentRect? {
        snapshot.containerContentFrame(forPath: path)
    }

    func containerScrollMembership(forPath path: TreePath) -> InterfaceTree.ScrollMembership? {
        snapshot.containerScrollMembership(forPath: path)
    }

    func containerObservedScrollContentActivationPoint(
        forPath path: TreePath
    ) -> InterfaceTree.ObservedScrollContentActivationPoint? {
        snapshot.containerObservedScrollContentActivationPoint(forPath: path)
    }

    func scrollInventory(forPath path: TreePath) -> ScrollInventory? {
        snapshot.scrollInventory(forPath: path)
    }

    func scrollView(for element: InterfaceTree.Element) -> UIScrollView? {
        let visibleScrollView = contains(heistId: element.heistId) ? scrollView(for: element.heistId) : nil
        let pathScrollView = element.scrollContainerPath
            .flatMap { scrollView(forContainerPath: $0) }
        return visibleScrollView
            ?? pathScrollView
    }

    func scrollView(forContainerPath path: TreePath) -> UIScrollView? {
        dispatchReferences.scrollableContainerViewsByPath[path]?.view
    }

    // MARK: - Snapshot

    /// Value-only capture metadata retained by settled semantic storage.
    ///
    /// This preserves parser hierarchy, ids, first-responder identity, container
    /// names, and scroll membership evidence without carrying weak UIKit refs or
    /// live dispatch lookup tables.
    struct Snapshot: Sendable, Equatable {
        let hierarchy: [AccessibilityHierarchy]
        let containerNamesByPath: [TreePath: ContainerName]
        let heistIdsByPath: [TreePath: HeistId]
        let containerContentFramesByPath: [TreePath: ContentRect]
        let containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership]
        let containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint]
        let scrollInventoriesByPath: [TreePath: ScrollInventory]
        /// Value-only first-responder evidence from this capture.
        /// Live UIKit identity remains in weak dispatch references.
        let firstResponderHeistId: HeistId?

        init(
            hierarchy: [AccessibilityHierarchy],
            containerNamesByPath: [TreePath: ContainerName] = [:],
            heistIdsByPath: [TreePath: HeistId] = [:],
            containerContentFramesByPath: [TreePath: ContentRect] = [:],
            containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership] = [:],
            containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint] = [:],
            scrollInventoriesByPath: [TreePath: ScrollInventory] = [:],
            firstResponderHeistId: HeistId? = nil
        ) {
            self.hierarchy = hierarchy
            self.containerNamesByPath = containerNamesByPath
            self.heistIdsByPath = heistIdsByPath
            self.containerContentFramesByPath = containerContentFramesByPath
            self.containerScrollMembershipsByPath = containerScrollMembershipsByPath
            self.containerObservedScrollContentActivationPointsByPath = containerObservedScrollContentActivationPointsByPath
            self.scrollInventoriesByPath = scrollInventoriesByPath
            self.firstResponderHeistId = firstResponderHeistId
        }

        static let empty = Snapshot(
            hierarchy: []
        )

        var heistIds: Set<HeistId> {
            Set(hierarchy.pathIndexedElements.compactMap { entry in
                guard entry.element.visibility == .onscreen else { return nil }
                return heistIdsByPath[entry.path]
            })
        }

        func contains(heistId: HeistId) -> Bool {
            heistIds.contains(heistId)
        }

        func element(for heistId: HeistId) -> AccessibilityElement? {
            guard let path = path(for: heistId),
                  case .element(let element, _) = hierarchy.node(at: path)
            else { return nil }
            return element
        }

        fileprivate func path(for heistId: HeistId) -> TreePath? {
            heistIdsByPath.first { $0.value == heistId }?.key
        }

        fileprivate var orderedHeistIds: [HeistId] {
            hierarchy.pathIndexedElements.compactMap { heistIdsByPath[$0.path] }
        }

        func containerContentFrame(forPath path: TreePath) -> ContentRect? {
            containerContentFramesByPath[path]
        }

        func containerScrollMembership(forPath path: TreePath) -> InterfaceTree.ScrollMembership? {
            containerScrollMembershipsByPath[path]
        }

        func containerObservedScrollContentActivationPoint(
            forPath path: TreePath
        ) -> InterfaceTree.ObservedScrollContentActivationPoint? {
            containerObservedScrollContentActivationPointsByPath[path]
        }

        func scrollInventory(forPath path: TreePath) -> ScrollInventory? {
            scrollInventoriesByPath[path]
        }
    }

    // MARK: - Dispatch References

    /// Live UIKit references used for action dispatch and scroll lookup.
    ///
    /// These are viewport-local weak refs. They are only accessed through the
    /// existing main-actor stash/live-lookup path and are intentionally absent
    /// from settled semantic storage.
    struct DispatchReferences {
        let elementRefs: [HeistId: ElementRef]
        let containerRefsByPath: [TreePath: ContainerRef]
        let scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]

        init(
            elementRefs: [HeistId: ElementRef] = [:],
            containerRefsByPath: [TreePath: ContainerRef] = [:],
            scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
        ) {
            self.elementRefs = elementRefs
            self.containerRefsByPath = containerRefsByPath
            self.scrollableContainerViewsByPath = scrollableContainerViewsByPath
        }

        static var empty: DispatchReferences {
            DispatchReferences()
        }
    }

    struct ScrollableViewRef {
        weak var view: UIScrollView?
    }

    struct ElementRef {
        /// Live UIKit object for action dispatch. Weak — nils on reuse.
        weak var object: NSObject?
        /// Nearest live scroll view for coordinate conversion.
        weak var scrollView: UIScrollView?
    }

    struct ContainerRef {
        weak var object: NSObject?
    }

    struct LiveElementEntry {
        let path: TreePath
        let heistId: HeistId
        let element: AccessibilityElement
    }

    private static func validate(
        validating tree: InterfaceTree,
        dispatchReferences: DispatchReferences
    ) throws {
        let snapshot = tree.viewportCapture
        let indexedElements = snapshot.hierarchy.pathIndexedElements
        let elementPaths = Set(indexedElements.map(\.path))

        for (heistId, element) in tree.elements.sorted(by: { $0.key < $1.key })
        where element.heistId != heistId {
            throw ValidationError.treeElementKeyMismatch(
                dictionaryHeistId: heistId,
                elementHeistId: element.heistId
            )
        }
        for (path, container) in tree.containers.sorted(by: { $0.key < $1.key })
        where container.path != path {
            throw ValidationError.treeContainerPathMismatch(
                dictionaryPath: path,
                containerPath: container.path
            )
        }

        for (path, heistId) in snapshot.heistIdsByPath.sorted(by: { $0.key < $1.key }) {
            guard snapshot.hierarchy.node(at: path) != nil else {
                throw ValidationError.heistIdForMissingPath(heistId: heistId, path: path)
            }
            guard elementPaths.contains(path) else {
                throw ValidationError.heistIdForNonElementPath(heistId: heistId, path: path)
            }
        }

        var pathsByHeistId: [HeistId: TreePath] = [:]
        for item in indexedElements {
            guard let heistId = snapshot.heistIdsByPath[item.path] else {
                throw ValidationError.missingHeistId(path: item.path)
            }
            if let firstPath = pathsByHeistId[heistId] {
                throw ValidationError.duplicateHeistId(
                    heistId: heistId,
                    firstPath: firstPath,
                    duplicatePath: item.path
                )
            }
            pathsByHeistId[heistId] = item.path
        }

        for item in indexedElements {
            guard let heistId = snapshot.heistIdsByPath[item.path] else {
                throw ValidationError.missingHeistId(path: item.path)
            }
            guard let treeElement = tree.elements[heistId] else {
                throw ValidationError.missingTreeElement(heistId: heistId, path: item.path)
            }
            guard treeElement.path == item.path else {
                throw ValidationError.treeElementPathMismatch(
                    heistId: heistId,
                    snapshotPath: item.path,
                    treePath: treeElement.path
                )
            }
            guard capturedElementsMatch(treeElement.element, item.element) else {
                throw ValidationError.treeElementMismatch(heistId: heistId, path: item.path)
            }
            try validateScrollEvidence(
                at: item.path,
                membership: treeElement.scrollMembership,
                observedPoint: treeElement.observedScrollContentActivationPoint,
                hierarchy: snapshot.hierarchy
            )
        }

        try validateContainers(in: tree)
        try validate(
            dispatchReferences: dispatchReferences,
            snapshot: snapshot,
            liveHeistIds: Set(pathsByHeistId.keys)
        )
    }

    private static func capturedElementsMatch(
        _ lhs: AccessibilityElement,
        _ rhs: AccessibilityElement
    ) -> Bool {
        lhs.matchesCapturedFacts(of: rhs)
    }

    private static func validateContainers(in tree: InterfaceTree) throws {
        let snapshot = tree.viewportCapture
        let metadataPaths = Set(snapshot.containerNamesByPath.keys)
            .union(snapshot.containerContentFramesByPath.keys)
            .union(snapshot.containerScrollMembershipsByPath.keys)
            .union(snapshot.containerObservedScrollContentActivationPointsByPath.keys)
            .union(snapshot.scrollInventoriesByPath.keys)

        for path in metadataPaths.sorted() {
            switch snapshot.hierarchy.node(at: path) {
            case nil:
                throw ValidationError.containerMetadataForMissingPath(path: path)
            case .element:
                throw ValidationError.containerMetadataForElementPath(path: path)
            case .container:
                break
            }
        }

        for item in snapshot.hierarchy.pathIndexedContainers {
            guard let treeContainer = tree.containers[item.path] else {
                throw ValidationError.missingTreeContainer(path: item.path)
            }
            let expected = InterfaceTree.Container(
                container: item.container,
                path: item.path,
                containerName: snapshot.containerNamesByPath[item.path],
                contentRect: snapshot.containerContentFramesByPath[item.path],
                scrollMembership: snapshot.containerScrollMembershipsByPath[item.path],
                observedScrollContentActivationPoint: snapshot
                    .containerObservedScrollContentActivationPointsByPath[item.path],
                scrollInventory: snapshot.scrollInventoriesByPath[item.path]
            )
            guard treeContainer == expected else {
                throw ValidationError.treeContainerMismatch(path: item.path)
            }
            try validateScrollEvidence(
                at: item.path,
                membership: treeContainer.scrollMembership,
                observedPoint: treeContainer.observedScrollContentActivationPoint,
                hierarchy: snapshot.hierarchy
            )
            if treeContainer.scrollInventory != nil, !item.container.isScrollable {
                throw ValidationError.scrollInventoryForNonScrollablePath(path: item.path)
            }
        }
    }

    private static func validateScrollEvidence(
        at path: TreePath,
        membership: InterfaceTree.ScrollMembership?,
        observedPoint: InterfaceTree.ObservedScrollContentActivationPoint?,
        hierarchy: [AccessibilityHierarchy]
    ) throws {
        if observedPoint != nil, membership == nil {
            throw ValidationError.observedScrollPointWithoutMembership(path: path)
        }
        guard let membership else { return }
        guard membership.containerPath != path,
              path.hasPrefix(membership.containerPath),
              case .container(let container, _) = hierarchy.node(at: membership.containerPath),
              container.isScrollable
        else {
            throw ValidationError.invalidScrollMembership(
                path: path,
                containerPath: membership.containerPath
            )
        }
    }

    private static func validate(
        dispatchReferences: DispatchReferences,
        snapshot: Snapshot,
        liveHeistIds: Set<HeistId>
    ) throws {
        for heistId in dispatchReferences.elementRefs.keys.sorted() where !liveHeistIds.contains(heistId) {
            throw ValidationError.strayElementRef(heistId: heistId)
        }

        if let firstResponderHeistId = snapshot.firstResponderHeistId,
           !liveHeistIds.contains(firstResponderHeistId) {
            throw ValidationError.invalidFirstResponderHeistId(heistId: firstResponderHeistId)
        }

        for path in dispatchReferences.containerRefsByPath.keys.sorted() {
            switch snapshot.hierarchy.node(at: path) {
            case nil:
                throw ValidationError.containerRefForMissingPath(path: path)
            case .element:
                throw ValidationError.containerRefForElementPath(path: path)
            case .container:
                break
            }
        }

        for path in dispatchReferences.scrollableContainerViewsByPath.keys.sorted() {
            switch snapshot.hierarchy.node(at: path) {
            case nil:
                throw ValidationError.scrollableViewForMissingPath(path: path)
            case .element:
                throw ValidationError.scrollableViewForElementPath(path: path)
            case .container(let container, _):
                guard container.isScrollable else {
                    throw ValidationError.scrollableViewForNonScrollablePath(path: path)
                }
            }
        }
    }

    enum ValidationError: Error, Equatable, CustomStringConvertible, LocalizedError {
        case duplicateHeistId(heistId: HeistId, firstPath: TreePath, duplicatePath: TreePath)
        case missingHeistId(path: TreePath)
        case heistIdForMissingPath(heistId: HeistId, path: TreePath)
        case heistIdForNonElementPath(heistId: HeistId, path: TreePath)
        case treeElementKeyMismatch(dictionaryHeistId: HeistId, elementHeistId: HeistId)
        case missingTreeElement(heistId: HeistId, path: TreePath)
        case treeElementPathMismatch(heistId: HeistId, snapshotPath: TreePath, treePath: TreePath)
        case treeElementMismatch(heistId: HeistId, path: TreePath)
        case treeContainerPathMismatch(dictionaryPath: TreePath, containerPath: TreePath)
        case containerMetadataForMissingPath(path: TreePath)
        case containerMetadataForElementPath(path: TreePath)
        case missingTreeContainer(path: TreePath)
        case treeContainerMismatch(path: TreePath)
        case invalidScrollMembership(path: TreePath, containerPath: TreePath)
        case observedScrollPointWithoutMembership(path: TreePath)
        case scrollInventoryForNonScrollablePath(path: TreePath)
        case strayElementRef(heistId: HeistId)
        case invalidFirstResponderHeistId(heistId: HeistId)
        case containerRefForMissingPath(path: TreePath)
        case containerRefForElementPath(path: TreePath)
        case scrollableViewForMissingPath(path: TreePath)
        case scrollableViewForElementPath(path: TreePath)
        case scrollableViewForNonScrollablePath(path: TreePath)

        var description: String {
            switch self {
            case .duplicateHeistId(let heistId, let firstPath, let duplicatePath):
                return """
                LiveCapture cannot represent duplicate live HeistId "\(heistId.rawValue)" \
                at paths \(firstPath.liveCaptureDiagnosticDescription) and \
                \(duplicatePath.liveCaptureDiagnosticDescription); live HeistIds must be \
                unique within a viewport snapshot.
                """

            case .missingHeistId(let path):
                return "Viewport element at \(path.liveCaptureDiagnosticDescription) has no HeistId."

            case .heistIdForMissingPath(let heistId, let path):
                return """
                LiveCapture cannot attach HeistId "\(heistId.rawValue)" to missing \
                path \(path.liveCaptureDiagnosticDescription).
                """

            case .heistIdForNonElementPath(let heistId, let path):
                return """
                LiveCapture cannot attach HeistId "\(heistId.rawValue)" to non-element \
                path \(path.liveCaptureDiagnosticDescription).
                """

            case .treeElementKeyMismatch(let dictionaryHeistId, let elementHeistId):
                return """
                InterfaceTree element key "\(dictionaryHeistId.rawValue)" does not match stored \
                HeistId "\(elementHeistId.rawValue)".
                """

            case .missingTreeElement(let heistId, let path):
                return """
                LiveCapture cannot find tree element "\(heistId.rawValue)" for viewport \
                path \(path.liveCaptureDiagnosticDescription).
                """

            case .treeElementPathMismatch(let heistId, let snapshotPath, let treePath):
                return """
                LiveCapture cannot pair tree element "\(heistId.rawValue)" at \
                \(treePath.liveCaptureDiagnosticDescription) with viewport path \
                \(snapshotPath.liveCaptureDiagnosticDescription).
                """

            case .treeElementMismatch(let heistId, let path):
                return """
                LiveCapture cannot pair tree element "\(heistId.rawValue)" with different \
                viewport element content at path \(path.liveCaptureDiagnosticDescription).
                """

            case .treeContainerPathMismatch(let dictionaryPath, let containerPath):
                return """
                InterfaceTree container key \(dictionaryPath.liveCaptureDiagnosticDescription) does not match stored \
                path \(containerPath.liveCaptureDiagnosticDescription).
                """

            case .containerMetadataForMissingPath(let path):
                return "Container metadata points at missing path \(path.liveCaptureDiagnosticDescription)."

            case .containerMetadataForElementPath(let path):
                return "Container metadata points at element path \(path.liveCaptureDiagnosticDescription)."

            case .missingTreeContainer(let path):
                return "InterfaceTree has no semantic container for viewport path \(path.liveCaptureDiagnosticDescription)."

            case .treeContainerMismatch(let path):
                return "InterfaceTree container does not match viewport capture at \(path.liveCaptureDiagnosticDescription)."

            case .invalidScrollMembership(let path, let containerPath):
                return """
                Scroll membership at \(path.liveCaptureDiagnosticDescription) points at a missing, non-scrollable, \
                or non-ancestor container \(containerPath.liveCaptureDiagnosticDescription).
                """

            case .observedScrollPointWithoutMembership(let path):
                return "Observed scroll point at \(path.liveCaptureDiagnosticDescription) has no scroll membership."

            case .scrollInventoryForNonScrollablePath(let path):
                return "Scroll inventory points at non-scrollable container \(path.liveCaptureDiagnosticDescription)."

            case .strayElementRef(let heistId):
                return """
                LiveCapture cannot attach stray element ref for HeistId \
                "\(heistId.rawValue)"; every live element ref must be backed by the snapshot.
                """

            case .invalidFirstResponderHeistId(let heistId):
                return """
                LiveCapture cannot attach first responder HeistId "\(heistId.rawValue)"; \
                first responder state must reference a snapshot element.
                """

            case .containerRefForMissingPath(let path):
                return """
                LiveCapture cannot attach container ref to missing path \
                \(path.liveCaptureDiagnosticDescription).
                """

            case .containerRefForElementPath(let path):
                return """
                LiveCapture cannot attach container ref to element path \
                \(path.liveCaptureDiagnosticDescription).
                """

            case .scrollableViewForMissingPath(let path):
                return """
                LiveCapture cannot attach scrollable view ref to missing path \
                \(path.liveCaptureDiagnosticDescription).
                """

            case .scrollableViewForElementPath(let path):
                return """
                LiveCapture cannot attach scrollable view ref to element path \
                \(path.liveCaptureDiagnosticDescription).
                """

            case .scrollableViewForNonScrollablePath(let path):
                return """
                LiveCapture cannot attach scrollable view ref to non-scrollable container path \
                \(path.liveCaptureDiagnosticDescription).
                """
            }
        }

        var errorDescription: String? {
            description
        }
    }

}

private extension TreePath {
    var liveCaptureDiagnosticDescription: String {
        "[\(indices.map(String.init).joined(separator: ", "))]"
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
