#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Interface Observation

/// One interface-tree state paired with the live UIKit evidence for its viewport.
/// Exploration may merge tree facts, but live evidence always comes from the
/// latest parser read and is never merged.
struct InterfaceObservation: Equatable {

    let tree: InterfaceTree
    let liveCapture: LiveCapture

    static var empty: InterfaceObservation {
        InterfaceObservation(
            tree: .empty,
            liveCapture: .empty
        )
    }

    // MARK: - Init

    /// Convenience init for tests and call sites that don't have container /
    /// element index data — defaults the live indices to empty maps.
    init(
        elements: [HeistId: InterfaceTree.Element],
        hierarchy: [AccessibilityHierarchy],
        elementRefs: [HeistId: LiveCapture.ElementRef] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViewsByPath: [TreePath: LiveCapture.ScrollableViewRef] = [:]
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
            tree: InterfaceTree(
                elements: elements,
                containers: Self.containers(from: liveCapture)
            ),
            liveCapture: liveCapture
        )
    }

    /// Memberwise init. Explicit so the convenience overload above can call it.
    init(
        elements: [HeistId: InterfaceTree.Element],
        hierarchy: [AccessibilityHierarchy],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdsByPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: LiveCapture.ElementRef] = [:],
        containerRefsByPath: [TreePath: LiveCapture.ContainerRef] = [:],
        containerContentFramesByPath: [TreePath: ContentRect] = [:],
        containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership] = [:],
        containerObservedScrollContentActivationPointsByPath: [TreePath: InterfaceTree.ObservedScrollContentActivationPoint] = [:],
        scrollInventoriesByPath: [TreePath: ScrollInventory] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViewsByPath: [TreePath: LiveCapture.ScrollableViewRef] = [:]
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
            tree: InterfaceTree(
                elements: elements,
                containers: Self.containers(from: liveCapture)
            ),
            liveCapture: liveCapture
        )
    }

    init(
        tree: InterfaceTree,
        liveCapture: LiveCapture
    ) {
        self.tree = InterfaceTree(
            elements: tree.elements,
            containers: tree.containers,
            viewportCapture: liveCapture.snapshot
        )
        self.liveCapture = liveCapture
    }

    // MARK: - Derived Properties

    var summaryElement: AccessibilityElement? {
        tree.summaryElement
    }

    var name: String? {
        tree.name
    }

    var id: String? {
        tree.id
    }

    var elementIDs: Set<HeistId> {
        tree.elementIDs
    }

    var elementCount: Int {
        tree.elementCount
    }

    var viewportElementIDs: Set<HeistId> {
        tree.viewportElementIDs
    }

    var interfaceHash: String {
        tree.interfaceHash
    }

    func findElement(heistId: HeistId) -> InterfaceTree.Element? {
        tree.findElement(heistId: heistId)
    }

    var orderedContainers: [InterfaceTree.Container] {
        tree.orderedContainers
    }

    var viewportOnly: InterfaceObservation {
        return InterfaceObservation(
            tree: tree.viewportOnly,
            liveCapture: liveCapture
        )
    }

    var orderedElements: [InterfaceTree.Element] {
        tree.orderedElements
    }

    private static func containers(from liveCapture: LiveCapture) -> [TreePath: InterfaceTree.Container] {
        Dictionary(
            uniqueKeysWithValues: liveCapture.hierarchy.pathIndexedContainers.map { item in
                (
                    item.path,
                    InterfaceTree.Container(
                        container: item.container,
                        path: item.path,
                        containerName: liveCapture.containerNamesByPath[item.path],
                        contentRect: liveCapture.containerContentFrame(forPath: item.path),
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
