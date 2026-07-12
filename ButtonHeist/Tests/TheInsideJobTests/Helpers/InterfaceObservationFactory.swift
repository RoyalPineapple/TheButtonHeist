#if canImport(UIKit)
#if DEBUG
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import ThePlans
@testable import TheScore

private func requireValidTestValue<Value>(_ build: () throws -> Value) -> Value {
    do {
        return try build()
    } catch {
        preconditionFailure("Invalid interface observation test fixture: \(error)")
    }
}

private func makeTestTree(
    snapshot: LiveCapture.Snapshot,
    elements: [HeistId: InterfaceTree.Element] = [:]
) -> InterfaceTree {
    let normalizedElements = snapshot.hierarchy.pathIndexedElements.reduce(into: elements) { result, item in
        guard let heistId = snapshot.heistIdsByPath[item.path] else { return }
        let supplied = elements[heistId]
        result[heistId] = InterfaceTree.Element(
            heistId: heistId,
            path: item.path,
            scrollMembership: supplied?.scrollMembership,
            observedScrollContentActivationPoint: supplied?.observedScrollContentActivationPoint,
            element: item.element
        )
    }
    let containers = Dictionary(
        uniqueKeysWithValues: snapshot.hierarchy.pathIndexedContainers.map { item in
            (
                item.path,
                InterfaceTree.Container(
                    container: item.container,
                    path: item.path,
                    containerName: snapshot.containerNamesByPath[item.path],
                    contentRect: snapshot.containerContentFramesByPath[item.path],
                    scrollMembership: snapshot.containerScrollMembershipsByPath[item.path],
                    observedScrollContentActivationPoint: snapshot
                        .containerObservedScrollContentActivationPointsByPath[item.path],
                    scrollInventory: snapshot.scrollInventoriesByPath[item.path]
                )
            )
        }
    )
    return InterfaceTree(
        elements: normalizedElements,
        containers: containers,
        viewportCapture: snapshot
    )
}

extension LiveCapture {

    static var empty: LiveCapture {
        requireValidTestValue {
            try LiveCapture.build(validating: .empty)
        }
    }

    init(
        hierarchy: [AccessibilityHierarchy],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdsByPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: ElementRef],
        containerRefsByPath: [TreePath: ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: ContentRect] = [:],
        containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership] = [:],
        containerObservedScrollContentActivationPointsByPath: [
            TreePath: InterfaceTree.ObservedScrollContentActivationPoint
        ] = [:],
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
        self = requireValidTestValue {
            try LiveCapture.build(
                validating: makeTestTree(snapshot: snapshot),
                dispatchReferences: DispatchReferences(
                    elementRefs: elementRefs,
                    containerRefsByPath: containerRefsByPath,
                    firstResponderHeistId: firstResponderHeistId,
                    scrollableContainerViewsByPath: scrollableContainerViewsByPath
                )
            )
        }
    }

    init(
        snapshot: Snapshot,
        dispatchReferences: DispatchReferences = .empty
    ) {
        self = requireValidTestValue {
            try LiveCapture.build(
                validating: makeTestTree(snapshot: snapshot),
                dispatchReferences: dispatchReferences
            )
        }
    }
}

/// Test-only `InterfaceObservation` factory.
///
/// Replaces the per-file `installScreen` / `seedScreen` /
/// `installScreenWithOffViewportEntry` helpers that all rebuilt the same
/// `InterfaceObservation` value from a list of `(AccessibilityElement, heistId)` pairs.
///
/// Off-viewport entries live in `InterfaceObservation.tree.elements` (so target resolution
/// sees them) but are not present in the live hierarchy — modeling an element
/// retained from a previous exploration that has since scrolled out of view.
extension InterfaceObservation {

    init(
        tree: InterfaceTree,
        liveCapture: LiveCapture
    ) {
        let snapshotTree = makeTestTree(
            snapshot: liveCapture.snapshot,
            elements: tree.elements
        )
        let alignedTree = InterfaceTree(
            elements: snapshotTree.elements,
            containers: tree.containers.merging(snapshotTree.containers) { current, _ in current },
            viewportCapture: liveCapture.snapshot
        )
        self = requireValidTestValue {
            try InterfaceObservation.build(
                tree: alignedTree,
                dispatchReferences: liveCapture.dispatchReferences
            )
        }
    }

    init(
        elements: [HeistId: InterfaceTree.Element],
        hierarchy: [AccessibilityHierarchy],
        elementRefs: [HeistId: LiveCapture.ElementRef] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViewsByPath: [TreePath: LiveCapture.ScrollableViewRef] = [:]
    ) {
        self.init(
            elements: elements,
            hierarchy: hierarchy,
            heistIdsByPath: [:],
            elementRefs: elementRefs,
            firstResponderHeistId: firstResponderHeistId,
            scrollableContainerViewsByPath: scrollableContainerViewsByPath
        )
    }

    init(
        elements: [HeistId: InterfaceTree.Element],
        hierarchy: [AccessibilityHierarchy],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdsByPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: LiveCapture.ElementRef] = [:],
        containerRefsByPath: [TreePath: LiveCapture.ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: ContentRect] = [:],
        containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership] = [:],
        containerObservedScrollContentActivationPointsByPath: [
            TreePath: InterfaceTree.ObservedScrollContentActivationPoint
        ] = [:],
        scrollInventoriesByPath: [TreePath: ScrollInventory] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViewsByPath: [TreePath: LiveCapture.ScrollableViewRef] = [:]
    ) {
        let snapshot = LiveCapture.Snapshot(
            hierarchy: hierarchy,
            containerNamesByPath: containerNamesByPath,
            heistIdsByPath: heistIdsByPath,
            containerContentFramesByPath: containerContentFramesByPath,
            containerScrollMembershipsByPath: containerScrollMembershipsByPath,
            containerObservedScrollContentActivationPointsByPath: containerObservedScrollContentActivationPointsByPath,
            scrollInventoriesByPath: scrollInventoriesByPath
        )
        self = requireValidTestValue {
            try InterfaceObservation.build(
                tree: makeTestTree(snapshot: snapshot, elements: elements),
                dispatchReferences: LiveCapture.DispatchReferences(
                    elementRefs: elementRefs,
                    containerRefsByPath: containerRefsByPath,
                    firstResponderHeistId: firstResponderHeistId,
                    scrollableContainerViewsByPath: scrollableContainerViewsByPath
                )
            )
        }
    }

    struct TestEntry {
        let element: AccessibilityElement
        let heistId: HeistId
        let object: NSObject?

        init(
            _ element: AccessibilityElement,
            heistId: HeistId,
            object: NSObject? = nil
        ) {
            self.element = element
            self.heistId = heistId
            self.object = object
        }

        init(
            label: String = "Element",
            heistId: HeistId? = nil,
            value: String? = nil,
            identifier: String? = nil,
            traits: UIAccessibilityTraits = .none,
            frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 44),
            object: NSObject? = nil
        ) {
            self.init(
                AccessibilityElement.make(
                    label: label,
                    value: value,
                    identifier: identifier,
                    traits: traits,
                    frame: frame
                ),
                heistId: heistId ?? HeistId(rawValue: label),
                object: object
            )
        }
    }

    /// An entry that is registered but is not in the live hierarchy. Used to
    /// simulate off-viewport interface state without a real scrollable container.
    struct OffViewportEntry {
        let element: AccessibilityElement
        let heistId: HeistId
        let scrollMembership: InterfaceTree.ScrollMembership?

        init(
            _ element: AccessibilityElement,
            heistId: HeistId,
            scrollContainerPath: TreePath? = nil,
            scrollIndex: Int? = nil
        ) {
            self.element = element
            self.heistId = heistId
            self.scrollMembership = scrollContainerPath.map {
                InterfaceTree.ScrollMembership(containerPath: $0, index: scrollIndex)
            }
        }
    }

    /// Build a `InterfaceObservation` from a flat list of `(element, heistId)` pairs. The
    /// hierarchy is constructed from the live pairs in order; off-viewport
    /// entries are added to `elements` but not to `hierarchy`.
    static func makeForTests(
        _ entries: [TestEntry],
        offViewport: [OffViewportEntry] = [],
        firstResponderHeistId: HeistId? = nil
    ) -> InterfaceObservation {
        makeForTests(
            elements: entries.map { (element: $0.element, heistId: $0.heistId) },
            objects: Dictionary(uniqueKeysWithValues: entries.map { ($0.heistId, $0.object) }),
            offViewport: offViewport,
            firstResponderHeistId: firstResponderHeistId
        )
    }

    static func makeForTests(
        elements liveElements: [(element: AccessibilityElement, heistId: HeistId)] = [],
        objects: [HeistId: NSObject?] = [:],
        offViewport: [OffViewportEntry] = [],
        firstResponderHeistId: HeistId? = nil
    ) -> InterfaceObservation {
        var treeElements: [HeistId: InterfaceTree.Element] = [:]
        var hierarchy: [AccessibilityHierarchy] = []
        var heistIdsByPath: [TreePath: HeistId] = [:]
        var elementRefs: [HeistId: LiveCapture.ElementRef] = [:]
        for (index, pair) in liveElements.enumerated() {
            treeElements[pair.heistId] = InterfaceTree.Element(
                heistId: pair.heistId,
                scrollMembership: nil,
                element: pair.element
            )
            elementRefs[pair.heistId] = LiveCapture.ElementRef(
                object: objects[pair.heistId] ?? nil,
                scrollView: nil
            )
            hierarchy.append(.element(pair.element, traversalIndex: index))
            heistIdsByPath[TreePath([index])] = pair.heistId
        }
        for entry in offViewport {
            treeElements[entry.heistId] = InterfaceTree.Element(
                heistId: entry.heistId,
                scrollMembership: entry.scrollMembership,
                element: entry.element
            )
        }
        return InterfaceObservation(
            elements: treeElements,
            hierarchy: hierarchy,
            heistIdsByPath: heistIdsByPath,
            elementRefs: elementRefs,
            firstResponderHeistId: firstResponderHeistId,
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
