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
/// `InterfaceObservation` only as part of an observed capture. Ephemeral index, not source of
/// truth: keyed by `TreePath` / `HeistId`, rebuilt wholesale on every parse,
/// and invalidated by the next parse (last-read-wins).
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
        dispatchReferences.firstResponderHeistId ?? snapshot.firstResponderHeistId
    }

    var scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] {
        dispatchReferences.scrollableContainerViewsByPath
    }

    private init(
        snapshot: Snapshot,
        liveElementTable: LiveElementTable,
        dispatchReferences: DispatchReferences
    ) {
        self.snapshot = snapshot
        self.dispatchReferences = dispatchReferences
        elementIndex = LiveElementIndex(
            validatedTable: liveElementTable,
            containerRefsByPath: dispatchReferences.containerRefsByPath,
            scrollableContainerViewsByPath: dispatchReferences.scrollableContainerViewsByPath
        )
    }

    static func build(
        validating tree: InterfaceTree,
        dispatchReferences: DispatchReferences = .empty
    ) throws -> LiveCapture {
        let table = try LiveElementTable(
            validating: tree,
            dispatchReferences: dispatchReferences
        )
        return LiveCapture(
            snapshot: tree.viewportCapture,
            liveElementTable: table,
            dispatchReferences: dispatchReferences
        )
    }

    var heistIds: Set<HeistId> {
        elementIndex.heistIds
    }

    func contains(heistId: HeistId) -> Bool {
        elementIndex.contains(heistId: heistId)
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

    func heistId(matchingObjectIdentifier objectIdentifier: ObjectIdentifier) -> HeistId? {
        elementIndex.heistId(matchingObjectIdentifier: objectIdentifier)
    }

    func scrollView(for heistId: HeistId) -> UIScrollView? {
        elementIndex.scrollView(for: heistId)
    }

    func scrollView(for container: InterfaceTree.Container) -> UIScrollView? {
        scrollView(forContainerPath: container.path)
    }

    func containerObject(forPath path: TreePath) -> NSObject? {
        elementIndex.containerObject(forPath: path)
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
        elementIndex.scrollableView(forContainerPath: path)
    }

    // MARK: - Snapshot

    /// Value-only capture metadata retained by settled semantic storage.
    ///
    /// This preserves parser hierarchy, ids, container names, and
    /// scroll membership evidence without carrying weak UIKit refs or live dispatch
    /// lookup tables.
    struct Snapshot: Sendable, Equatable {
        let hierarchy: [AccessibilityHierarchy]
        let containerNamesByPath: [TreePath: ContainerName]
        let heistIdsByPath: [TreePath: HeistId]
        let containerContentFramesByPath: [TreePath: ContentRect]
        let containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership]
        let containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint]
        let scrollInventoriesByPath: [TreePath: ScrollInventory]
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
            Set(heistIdsByPath.values)
        }

        func contains(heistId: HeistId) -> Bool {
            heistIds.contains(heistId)
        }

        func element(for heistId: HeistId) -> AccessibilityElement? {
            guard let path = heistIdsByPath.first(where: { $0.value == heistId })?.key,
                  case .element(let element, _) = hierarchy.node(at: path)
            else { return nil }
            return element
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
        weak var view: UIScrollView?

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
        let treeElement: InterfaceTree.Element
        let ref: ElementRef?
        let isFirstResponder: Bool

        init(
            path: TreePath,
            treeElement: InterfaceTree.Element,
            ref: ElementRef? = nil,
            isFirstResponder: Bool = false
        ) {
            self.path = path
            self.treeElement = treeElement
            self.ref = ref
            self.isFirstResponder = isFirstResponder
        }

        var heistId: HeistId {
            treeElement.heistId
        }

        var element: AccessibilityElement {
            treeElement.element
        }
    }

    struct LiveElementTable: Equatable {
        let entries: [LiveElementEntry]

        init(entries: [LiveElementEntry]) throws {
            try Self.validate(entries: entries)
            self.entries = entries
        }

        init(
            validating tree: InterfaceTree,
            dispatchReferences: DispatchReferences
        ) throws {
            let snapshot = tree.viewportCapture
            var entries: [LiveElementEntry] = []
            let indexedElements = Dictionary(
                uniqueKeysWithValues: snapshot.hierarchy.pathIndexedElements.map { ($0.path, $0) }
            )

            for (path, heistId) in snapshot.heistIdsByPath {
                guard snapshot.hierarchy.node(at: path) != nil else {
                    throw LiveElementTableValidationError.heistIdForMissingPath(
                        heistId: heistId,
                        path: path
                    )
                }
                guard indexedElements[path] != nil else {
                    throw LiveElementTableValidationError.heistIdForNonElementPath(
                        heistId: heistId,
                        path: path
                    )
                }
            }

            var pathsByHeistId: [HeistId: TreePath] = [:]
            for item in snapshot.hierarchy.pathIndexedElements {
                guard let heistId = snapshot.heistIdsByPath[item.path] else { continue }
                if let firstPath = pathsByHeistId[heistId] {
                    throw LiveElementTableValidationError.duplicateHeistId(
                        heistId: heistId,
                        firstPath: firstPath,
                        duplicatePath: item.path
                    )
                }
                pathsByHeistId[heistId] = item.path
            }

            for item in snapshot.hierarchy.pathIndexedElements {
                guard let heistId = snapshot.heistIdsByPath[item.path] else { continue }
                guard let treeElement = tree.elements[heistId] else {
                    throw LiveElementTableValidationError.missingTreeElement(
                        heistId: heistId,
                        path: item.path
                    )
                }
                guard treeElement.path == item.path else {
                    throw LiveElementTableValidationError.treeElementPathMismatch(
                        heistId: heistId,
                        snapshotPath: item.path,
                        treePath: treeElement.path
                    )
                }
                guard treeElement.heistId == heistId,
                      treeElement.element == item.element
                else {
                    throw LiveElementTableValidationError.treeElementMismatch(
                        heistId: heistId,
                        path: item.path
                    )
                }
                entries.append(LiveElementEntry(
                    path: item.path,
                    treeElement: treeElement,
                    ref: dispatchReferences.elementRefs[heistId],
                    isFirstResponder: dispatchReferences.firstResponderHeistId == heistId
                ))
            }

            try Self.validate(entries: entries)
            try Self.validate(
                dispatchReferences: dispatchReferences,
                snapshot: snapshot,
                liveHeistIds: Set(entries.map(\.heistId))
            )
            self.entries = entries
        }

        private static func validate(entries: [LiveElementEntry]) throws {
            var pathsByHeistId: [HeistId: TreePath] = [:]
            var heistIdsByPath: [TreePath: HeistId] = [:]

            for entry in entries {
                if let firstPath = pathsByHeistId[entry.heistId] {
                    throw LiveElementTableValidationError.duplicateHeistId(
                        heistId: entry.heistId,
                        firstPath: firstPath,
                        duplicatePath: entry.path
                    )
                }
                if let firstHeistId = heistIdsByPath[entry.path] {
                    throw LiveElementTableValidationError.duplicateElementPath(
                        path: entry.path,
                        firstHeistId: firstHeistId,
                        duplicateHeistId: entry.heistId
                    )
                }
                pathsByHeistId[entry.heistId] = entry.path
                heistIdsByPath[entry.path] = entry.heistId
            }
        }

        private static func validate(
            dispatchReferences: DispatchReferences,
            snapshot: Snapshot,
            liveHeistIds: Set<HeistId>
        ) throws {
            for heistId in dispatchReferences.elementRefs.keys.sorted() where !liveHeistIds.contains(heistId) {
                throw LiveElementTableValidationError.strayElementRef(heistId: heistId)
            }

            if let firstResponderHeistId = dispatchReferences.firstResponderHeistId,
               !liveHeistIds.contains(firstResponderHeistId) {
                throw LiveElementTableValidationError.invalidFirstResponderHeistId(
                    heistId: firstResponderHeistId
                )
            }

            for path in dispatchReferences.containerRefsByPath.keys.sorted() {
                switch snapshot.hierarchy.node(at: path) {
                case nil:
                    throw LiveElementTableValidationError.containerRefForMissingPath(path: path)
                case .element:
                    throw LiveElementTableValidationError.containerRefForElementPath(path: path)
                case .container:
                    break
                }
            }

            for path in dispatchReferences.scrollableContainerViewsByPath.keys.sorted() {
                switch snapshot.hierarchy.node(at: path) {
                case nil:
                    throw LiveElementTableValidationError.scrollableViewForMissingPath(path: path)
                case .element:
                    throw LiveElementTableValidationError.scrollableViewForElementPath(path: path)
                case .container(let container, _):
                    guard container.isScrollable else {
                        throw LiveElementTableValidationError.scrollableViewForNonScrollablePath(path: path)
                    }
                }
            }
        }
    }

    enum LiveElementTableValidationError: Error, Equatable, CustomStringConvertible, LocalizedError {
        case duplicateHeistId(heistId: HeistId, firstPath: TreePath, duplicatePath: TreePath)
        case duplicateElementPath(path: TreePath, firstHeistId: HeistId, duplicateHeistId: HeistId)
        case heistIdForMissingPath(heistId: HeistId, path: TreePath)
        case heistIdForNonElementPath(heistId: HeistId, path: TreePath)
        case missingTreeElement(heistId: HeistId, path: TreePath)
        case treeElementPathMismatch(heistId: HeistId, snapshotPath: TreePath, treePath: TreePath)
        case treeElementMismatch(heistId: HeistId, path: TreePath)
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
                LiveElementIndex cannot index duplicate live HeistId "\(heistId.rawValue)" \
                at paths \(firstPath.liveCaptureDiagnosticDescription) and \
                \(duplicatePath.liveCaptureDiagnosticDescription); live HeistIds must be \
                unique before building lookup indexes.
                """

            case .duplicateElementPath(let path, let firstHeistId, let duplicateHeistId):
                return """
                LiveElementIndex cannot index duplicate live path \
                \(path.liveCaptureDiagnosticDescription) for HeistIds \
                "\(firstHeistId.rawValue)" and "\(duplicateHeistId.rawValue)".
                """

            case .heistIdForMissingPath(let heistId, let path):
                return """
                LiveElementIndex cannot attach HeistId "\(heistId.rawValue)" to missing \
                path \(path.liveCaptureDiagnosticDescription).
                """

            case .heistIdForNonElementPath(let heistId, let path):
                return """
                LiveElementIndex cannot attach HeistId "\(heistId.rawValue)" to non-element \
                path \(path.liveCaptureDiagnosticDescription).
                """

            case .missingTreeElement(let heistId, let path):
                return """
                LiveElementIndex cannot find tree element "\(heistId.rawValue)" for viewport \
                path \(path.liveCaptureDiagnosticDescription).
                """

            case .treeElementPathMismatch(let heistId, let snapshotPath, let treePath):
                return """
                LiveElementIndex cannot pair tree element "\(heistId.rawValue)" at \
                \(treePath.liveCaptureDiagnosticDescription) with viewport path \
                \(snapshotPath.liveCaptureDiagnosticDescription).
                """

            case .treeElementMismatch(let heistId, let path):
                return """
                LiveElementIndex cannot pair tree element "\(heistId.rawValue)" with different \
                viewport element content at path \(path.liveCaptureDiagnosticDescription).
                """

            case .strayElementRef(let heistId):
                return """
                LiveElementIndex cannot attach stray element ref for HeistId \
                "\(heistId.rawValue)"; every live element ref must be backed by a live entry.
                """

            case .invalidFirstResponderHeistId(let heistId):
                return """
                LiveElementIndex cannot attach first responder HeistId "\(heistId.rawValue)"; \
                first responder state must reference a live element entry.
                """

            case .containerRefForMissingPath(let path):
                return """
                LiveElementIndex cannot attach container ref to missing path \
                \(path.liveCaptureDiagnosticDescription).
                """

            case .containerRefForElementPath(let path):
                return """
                LiveElementIndex cannot attach container ref to element path \
                \(path.liveCaptureDiagnosticDescription).
                """

            case .scrollableViewForMissingPath(let path):
                return """
                LiveElementIndex cannot attach scrollable view ref to missing path \
                \(path.liveCaptureDiagnosticDescription).
                """

            case .scrollableViewForElementPath(let path):
                return """
                LiveElementIndex cannot attach scrollable view ref to element path \
                \(path.liveCaptureDiagnosticDescription).
                """

            case .scrollableViewForNonScrollablePath(let path):
                return """
                LiveElementIndex cannot attach scrollable view ref to non-scrollable container path \
                \(path.liveCaptureDiagnosticDescription).
                """
            }
        }

        var errorDescription: String? {
            description
        }
    }

    // MARK: - Live Element Index

    struct LiveElementIndex: Equatable {
        private let entriesByPath: [TreePath: LiveElementEntry]
        private let pathsByHeistId: [HeistId: TreePath]
        private let orderedPaths: [TreePath]
        private let containerRefsByPath: [TreePath: ContainerRef]
        private let scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]

        fileprivate init(
            validatedTable table: LiveElementTable,
            containerRefsByPath: [TreePath: ContainerRef],
            scrollableContainerViewsByPath: [TreePath: ScrollableViewRef]
        ) {
            let entries = table.entries
            entriesByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
            pathsByHeistId = Dictionary(uniqueKeysWithValues: entries.map { ($0.heistId, $0.path) })
            orderedPaths = entries.map(\.path)
            self.containerRefsByPath = containerRefsByPath
            self.scrollableContainerViewsByPath = scrollableContainerViewsByPath
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

        func heistId(matchingObjectIdentifier objectIdentifier: ObjectIdentifier) -> HeistId? {
            orderedElementEntries.first { entry in
                entry.ref?.object.map(ObjectIdentifier.init) == objectIdentifier
            }?.heistId
        }

        func scrollView(for heistId: HeistId) -> UIScrollView? {
            elementEntry(for: heistId)?.ref?.scrollView
        }

        func containerObject(forPath path: TreePath) -> NSObject? {
            containerRefsByPath[path]?.object
        }

        func scrollableView(forContainerPath path: TreePath) -> UIScrollView? {
            scrollableContainerViewsByPath[path]?.view
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
