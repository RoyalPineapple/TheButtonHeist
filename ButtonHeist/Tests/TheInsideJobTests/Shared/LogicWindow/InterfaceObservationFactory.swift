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

private func testViewSpace(
    for element: AccessibilityElement,
    ownerPath: TreePath
) -> HeistElement.Geometry.ViewSpace {
    HeistElement.Geometry.ViewSpace(
        ownerPath: ownerPath,
        frame: try? ViewRect(validating: element.bhFrame),
        activationPoint: try? ViewPoint(validating: element.bhResolvedActivationPoint)
    )
}

func testGeometry(
    for element: AccessibilityElement,
    ownerPath: TreePath,
    screen: HeistElement.Geometry.ScreenSpace
) -> HeistElement.Geometry {
    HeistElement.Geometry(
        screen: screen,
        view: testViewSpace(for: element, ownerPath: ownerPath)
    )
}

private func inferredScrollMembership(
    for path: TreePath,
    in hierarchy: [AccessibilityHierarchy]
) -> InterfaceTree.ScrollMembership? {
    let scrollablePaths = Set(
        hierarchy.pathIndexedContainers.compactMap { item in
            item.container.isScrollable ? item.path : nil
        }
    )
    var ancestor = path.parent
    while let path = ancestor {
        if scrollablePaths.contains(path) {
            return InterfaceTree.ScrollMembership(containerPath: path, index: nil)
        }
        ancestor = path.parent
    }
    return nil
}

private func makeTestTree(
    snapshot: LiveCapture.Snapshot,
    elements: [HeistId: InterfaceTree.Element] = [:],
    containers: [TreePath: InterfaceTree.Container] = [:]
) -> InterfaceTree {
    let normalizedElements = snapshot.hierarchy.pathIndexedElements.reduce(into: elements) { result, item in
        guard let heistId = snapshot.heistIdsByPath[item.path] else { return }
        let supplied = elements[heistId]
        let inferredMembership = inferredScrollMembership(
            for: item.path,
            in: snapshot.hierarchy
        )
        let scrollMembership = inferredMembership.map {
            InterfaceTree.ScrollMembership(
                containerPath: $0.containerPath,
                index: supplied?.scrollMembership?.index
            )
        }
        let suppliedGeometry = supplied?.geometry
        result[heistId] = InterfaceTree.Element(
            heistId: heistId,
            path: item.path,
            scrollMembership: scrollMembership,
            geometry: HeistElement.Geometry(
                screen: suppliedGeometry?.screen
                    ?? TheVault.onscreenSpace(for: item.element),
                view: HeistElement.Geometry.ViewSpace(
                    ownerPath: scrollMembership?.containerPath ?? .root,
                    frame: suppliedGeometry?.view.frame
                        ?? (try? ViewRect(validating: item.element.bhFrame)),
                    activationPoint: suppliedGeometry?.view.activationPoint
                        ?? (try? ViewPoint(validating: item.element.bhResolvedActivationPoint))
                )
            ),
            element: item.element
        )
    }
    let normalizedContainers = snapshot.hierarchy.pathIndexedContainers.reduce(into: containers) { result, item in
        let supplied = containers[item.path]
        let inferredMembership = inferredScrollMembership(
            for: item.path,
            in: snapshot.hierarchy
        )
        let scrollMembership = inferredMembership.map {
            InterfaceTree.ScrollMembership(
                containerPath: $0.containerPath,
                index: supplied?.scrollMembership?.index
            )
        }
        result[item.path] = InterfaceTree.Container(
            container: item.container,
            path: item.path,
            containerName: supplied?.containerName,
            viewSpace: HeistElement.Geometry.ViewSpace(
                ownerPath: scrollMembership?.containerPath ?? .root,
                frame: supplied?.viewSpace.frame
                    ?? (try? ViewRect(validating: item.container.frame.cgRect)),
                activationPoint: supplied?.viewSpace.activationPoint
            ),
            scrollMembership: scrollMembership,
            scrollInventory: supplied?.scrollInventory
        )
    }
    return InterfaceTree(
        elements: normalizedElements,
        containers: normalizedContainers,
        viewportCapture: snapshot
    )
}

extension LiveCapture {
    static func makeForTests(
        hierarchy: [AccessibilityHierarchy] = [],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdsByPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: ElementRef] = [:],
        containerRefsByPath: [TreePath: ContainerRef] = [:],
        containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership] = [:],
        containerViewSpacesByPath: [
            TreePath: HeistElement.Geometry.ViewSpace
        ] = [:],
        scrollInventoriesByPath: [TreePath: ScrollInventory] = [:],
        firstResponderHeistId: HeistId? = nil,
        scrollableContainerViewsByPath: [TreePath: ScrollableViewRef] = [:]
    ) -> LiveCapture {
        let containersByPath = Dictionary(
            uniqueKeysWithValues: hierarchy.pathIndexedContainers.map { item in
                (
                    item.path,
                    InterfaceTree.Container(
                        container: item.container,
                        path: item.path,
                        containerName: containerNamesByPath[item.path],
                        viewSpace: containerViewSpacesByPath[item.path]
                            ?? HeistElement.Geometry.ViewSpace(
                                ownerPath: containerScrollMembershipsByPath[item.path]?.containerPath ?? .root,
                                frame: try? ViewRect(validating: item.container.frame.cgRect),
                                activationPoint: nil
                            ),
                        scrollMembership: containerScrollMembershipsByPath[item.path],
                        scrollInventory: scrollInventoriesByPath[item.path]
                    )
                )
            }
        )
        let snapshot = Snapshot(
            hierarchy: hierarchy,
            heistIdsByPath: heistIdsByPath,
            firstResponderHeistId: firstResponderHeistId
        )
        return requireValidTestValue {
            try LiveCapture.build(
                validating: makeTestTree(snapshot: snapshot, containers: containersByPath),
                dispatchReferences: DispatchReferences(
                    elementRefs: elementRefs,
                    containerRefsByPath: containerRefsByPath,
                    scrollableContainerViewsByPath: scrollableContainerViewsByPath
                )
            )
        }
    }

    static func makeForTests(
        snapshot: Snapshot,
        dispatchReferences: DispatchReferences = .empty
    ) -> LiveCapture {
        requireValidTestValue {
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
    static func makeForTests(
        tree: InterfaceTree,
        liveCapture: LiveCapture
    ) -> InterfaceObservation {
        let snapshotTree = makeTestTree(
            snapshot: liveCapture.snapshot,
            elements: tree.elements,
            containers: tree.containers
        )
        return requireValidTestValue {
            try InterfaceObservation.build(
                tree: snapshotTree,
                dispatchReferences: liveCapture.dispatchReferences
            )
        }
    }

    static func makeForTests(
        elements: [HeistId: InterfaceTree.Element],
        hierarchy: [AccessibilityHierarchy],
        containerNamesByPath: [TreePath: ContainerName] = [:],
        heistIdsByPath: [TreePath: HeistId] = [:],
        elementRefs: [HeistId: LiveCapture.ElementRef] = [:],
        containerRefsByPath: [TreePath: LiveCapture.ContainerRef] = [:],
        containerScrollMembershipsByPath: [TreePath: InterfaceTree.ScrollMembership] = [:],
        containerViewSpacesByPath: [
            TreePath: HeistElement.Geometry.ViewSpace
        ] = [:],
        scrollInventoriesByPath: [TreePath: ScrollInventory] = [:],
        firstResponderHeistId: HeistId?,
        scrollableContainerViewsByPath: [TreePath: LiveCapture.ScrollableViewRef] = [:]
    ) -> InterfaceObservation {
        let containersByPath = Dictionary(
            uniqueKeysWithValues: hierarchy.pathIndexedContainers.map { item in
                (
                    item.path,
                    InterfaceTree.Container(
                        container: item.container,
                        path: item.path,
                        containerName: containerNamesByPath[item.path],
                        viewSpace: containerViewSpacesByPath[item.path]
                            ?? HeistElement.Geometry.ViewSpace(
                                ownerPath: containerScrollMembershipsByPath[item.path]?.containerPath ?? .root,
                                frame: try? ViewRect(validating: item.container.frame.cgRect),
                                activationPoint: nil
                            ),
                        scrollMembership: containerScrollMembershipsByPath[item.path],
                        scrollInventory: scrollInventoriesByPath[item.path]
                    )
                )
            }
        )
        let snapshot = LiveCapture.Snapshot(
            hierarchy: hierarchy,
            heistIdsByPath: heistIdsByPath,
            firstResponderHeistId: firstResponderHeistId
        )
        return requireValidTestValue {
            try InterfaceObservation.build(
                tree: makeTestTree(
                    snapshot: snapshot,
                    elements: elements,
                    containers: containersByPath
                ),
                dispatchReferences: LiveCapture.DispatchReferences(
                    elementRefs: elementRefs,
                    containerRefsByPath: containerRefsByPath,
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
                path: TreePath([index]),
                scrollMembership: nil,
                geometry: testGeometry(
                    for: pair.element,
                    ownerPath: .root,
                    screen: TheVault.onscreenSpace(for: pair.element)
                ),
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
                geometry: testGeometry(
                    for: entry.element,
                    ownerPath: entry.scrollMembership?.containerPath ?? .root,
                    screen: .offscreen
                ),
                element: entry.element
            )
        }
        return InterfaceObservation.makeForTests(
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
