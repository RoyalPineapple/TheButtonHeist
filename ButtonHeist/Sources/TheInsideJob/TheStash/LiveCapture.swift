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

    var containerContentFramesByPath: [TreePath: CGRect] {
        snapshot.containerContentFramesByPath
    }

    var containerScrollMembershipsByPath: [TreePath: SemanticScreen.ScrollMembership] {
        snapshot.containerScrollMembershipsByPath
    }

    var containerObservedScrollContentActivationPointsByPath: [TreePath: SemanticScreen.ObservedScrollContentActivationPoint] {
        snapshot.containerObservedScrollContentActivationPointsByPath
    }

    var scrollInventoriesByPath: [TreePath: ScrollInventory] {
        snapshot.scrollInventoriesByPath
    }

    var firstResponderHeistId: HeistId? {
        dispatchReferences.firstResponderHeistId
    }

    var scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] {
        dispatchReferences.scrollableContainerViewsByPath
    }

    init(
        hierarchy: [AccessibilityHierarchy],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdsByPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: ElementRef],
        containerRefsByPath: [TreePath: ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: CGRect] = [:],
        containerScrollMembershipsByPath: [TreePath: SemanticScreen.ScrollMembership] = [:],
        containerObservedScrollContentActivationPointsByPath: [TreePath: SemanticScreen.ObservedScrollContentActivationPoint] = [:],
        scrollInventoriesByPath: [TreePath: ScrollInventory] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
    ) {
        let snapshot = Snapshot(
            hierarchy: hierarchy,
            containerNamesByPath: containerNamesByPath,
            heistIdsByPath: heistIdsByPath,
            containerContentFramesByPath: containerContentFramesByPath,
            containerScrollMembershipsByPath: containerScrollMembershipsByPath,
            containerObservedScrollContentActivationPointsByPath: containerObservedScrollContentActivationPointsByPath,
            scrollInventoriesByPath: scrollInventoriesByPath
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

    func containerScrollMembership(forPath path: TreePath) -> SemanticScreen.ScrollMembership? {
        snapshot.containerScrollMembership(forPath: path)
    }

    func containerObservedScrollContentActivationPoint(
        forPath path: TreePath
    ) -> SemanticScreen.ObservedScrollContentActivationPoint? {
        snapshot.containerObservedScrollContentActivationPoint(forPath: path)
    }

    func scrollInventory(forPath path: TreePath) -> ScrollInventory? {
        snapshot.scrollInventory(forPath: path)
    }

    func scrollView(for element: SemanticScreen.Element) -> UIScrollView? {
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
        let containerContentFramesByPath: [TreePath: CGRect]
        let containerScrollMembershipsByPath: [TreePath: SemanticScreen.ScrollMembership]
        let containerObservedScrollContentActivationPointsByPath: [TreePath: SemanticScreen.ObservedScrollContentActivationPoint]
        let scrollInventoriesByPath: [TreePath: ScrollInventory]

        init(
            hierarchy: [AccessibilityHierarchy],
            containerNamesByPath: [TreePath: ContainerName] = [:],
            heistIdsByPath: [TreePath: HeistId] = [:],
            containerContentFramesByPath: [TreePath: CGRect] = [:],
            containerScrollMembershipsByPath: [TreePath: SemanticScreen.ScrollMembership] = [:],
            containerObservedScrollContentActivationPointsByPath: [TreePath: SemanticScreen.ObservedScrollContentActivationPoint] = [:],
            scrollInventoriesByPath: [TreePath: ScrollInventory] = [:]
        ) {
            self.hierarchy = hierarchy
            self.containerNamesByPath = containerNamesByPath
            self.heistIdsByPath = heistIdsByPath
            self.containerContentFramesByPath = containerContentFramesByPath
            self.containerScrollMembershipsByPath = containerScrollMembershipsByPath
            self.containerObservedScrollContentActivationPointsByPath = containerObservedScrollContentActivationPointsByPath
            self.scrollInventoriesByPath = scrollInventoriesByPath
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

        func containerContentFrame(forPath path: TreePath) -> CGRect? {
            containerContentFramesByPath[path]
        }

        func containerScrollMembership(forPath path: TreePath) -> SemanticScreen.ScrollMembership? {
            containerScrollMembershipsByPath[path]
        }

        func containerObservedScrollContentActivationPoint(
            forPath path: TreePath
        ) -> SemanticScreen.ObservedScrollContentActivationPoint? {
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
        let heistId: HeistId
        let element: AccessibilityElement
        let ref: ElementRef?
    }

    struct LiveElementTable: Equatable {
        let entries: [LiveElementEntry]

        init(
            validating snapshot: Snapshot,
            dispatchReferences: DispatchReferences
        ) throws {
            var entries: [LiveElementEntry] = []
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
                entries.append(LiveElementEntry(
                    path: item.path,
                    heistId: heistId,
                    element: item.element,
                    ref: dispatchReferences.elementRefs[heistId]
                ))
                pathsByHeistId[heistId] = item.path
            }

            self.entries = entries
        }
    }

    enum LiveElementTableValidationError: Error, Equatable, CustomStringConvertible, LocalizedError {
        case duplicateHeistId(heistId: HeistId, firstPath: TreePath, duplicatePath: TreePath)

        var description: String {
            switch self {
            case .duplicateHeistId(let heistId, let firstPath, let duplicatePath):
                return """
                LiveElementIndex cannot index duplicate live HeistId "\(heistId.rawValue)" \
                at paths \(firstPath.liveCaptureDiagnosticDescription) and \
                \(duplicatePath.liveCaptureDiagnosticDescription); live HeistIds must be \
                unique before building lookup indexes.
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

        init(
            snapshot: Snapshot,
            dispatchReferences: DispatchReferences
        ) {
            do {
                let table = try LiveElementTable(
                    validating: snapshot,
                    dispatchReferences: dispatchReferences
                )
                self.init(
                    validatedTable: table,
                    dispatchReferences: dispatchReferences
                )
            } catch let error as LiveElementTableValidationError {
                preconditionFailure(error.description)
            } catch {
                preconditionFailure("LiveElementIndex failed to validate live element table: \(error)")
            }
        }

        private init(
            validatedTable table: LiveElementTable,
            dispatchReferences: DispatchReferences
        ) {
            let entries = table.entries
            entriesByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
            pathsByHeistId = Dictionary(uniqueKeysWithValues: entries.map { ($0.heistId, $0.path) })
            orderedPaths = entries.map(\.path)
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
