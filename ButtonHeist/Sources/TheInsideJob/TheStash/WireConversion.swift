#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Float Sanitization

extension CGFloat {
    /// Replace NaN/infinity with 0 so JSONEncoder doesn't throw.
    /// UIPickerView's 3D-transformed cells can produce non-finite frame coordinates.
    var sanitizedForJSON: CGFloat {
        isFinite ? self : 0
    }
}

extension Double {
    /// Replace NaN/infinity with 0 so JSONEncoder doesn't throw.
    /// Portable parser points use Double instead of UIKit's CGFloat.
    var sanitizedForJSON: Double {
        isFinite ? self : 0
    }
}

// MARK: - Wire Conversion

extension TheStash {

    /// Convert internal accessibility types (`AccessibilityElement`,
    /// `AccessibilityHierarchy`, `InterfaceObservation`) to their wire-facing projections.
    /// Pure transform — no stored state. Delta projection is capture-backed in
    /// TheScore.
    @MainActor enum WireConversion { // swiftlint:disable:this agent_main_actor_value_type

    // MARK: - Element Conversion

    static func convert(_ element: AccessibilityElement) -> HeistElement {
        let frame = element.bhFrame
        let activationPoint = activationPointEvidence(for: element)
        return HeistElement(
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: element.traits.heistTraits,
            frameX: frame.origin.x.sanitizedForJSON,
            frameY: frame.origin.y.sanitizedForJSON,
            frameWidth: frame.size.width.sanitizedForJSON,
            frameHeight: frame.size.height.sanitizedForJSON,
            activationPointEvidence: activationPoint,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: {
                let projected = element.projectedCustomContent
                return projected.isEmpty ? nil : projected
            }(),
            rotors: {
                let valid = element.customRotors.filter { !$0.name.isEmpty }
                return valid.isEmpty ? nil : valid.map { HeistRotor(name: $0.name) }
            }(),
            actions: element.projectedActionSet.orderedActions
        )
    }

    private static func activationPointEvidence(for element: AccessibilityElement) -> ActivationPointEvidence {
        let point = element.bhResolvedActivationPoint
        guard point.x.isFinite, point.y.isFinite else { return .unavailable }
        let screenPoint = ScreenPoint(x: Double(point.x), y: Double(point.y))
        return element.usesDefaultActivationPoint
            ? .defaultCenter(screenPoint)
            : .explicit(screenPoint)
    }

    // MARK: - Interface Conversion

    /// Convert the interface tree into the canonical wire capture. The parser
    /// hierarchy remains the tree; Button Heist metadata is attached as
    /// annotations keyed by capture-local tree path.
    static func toInterface(
        from tree: InterfaceTree,
        timestamp: Date = Date()
    ) -> Interface {
        Interface(
            timestamp: timestamp,
            projecting: tree.viewportCapture.hierarchy,
            elementMetadata: { path, element, _ in
                InterfaceElementProjectionMetadata(
                    actions: element.projectedActionSet.orderedActions,
                    traceIdentity: tree.viewportCapture.heistIdsByPath[path]?.traceElementIdentity
                )
            },
            containerMetadata: { path, _ in
                InterfaceContainerProjectionMetadata(
                    containerName: tree.containers[path]?.containerName,
                    scrollInventory: tree.containers[path]?.scrollInventory
                )
            }
        )
    }

    /// Convert a InterfaceObservation into the public discovery interface.
    ///
    /// The latest parser hierarchy is still the tree authority. Known elements
    /// and containers absent from that capture are grafted under their owning
    /// semantic scroll container so public `get_interface` does not discard
    /// the command's exploration work.
    static func toDiscoveryInterface(
        from tree: InterfaceTree,
        timestamp: Date = Date()
    ) -> Interface {
        discoveryProjection(from: tree, timestamp: timestamp).interface
    }

    static func discoveryProjection(
        from tree: InterfaceTree,
        timestamp: Date = Date()
    ) -> DiscoveryProjection {
        var elementAnnotations = elementAnnotations(from: tree)
        var containerAnnotations = containerAnnotations(from: tree)
        var containerPathBySourcePath = Dictionary(
            uniqueKeysWithValues: containerAnnotations.map { ($0.path, $0.path) }
        )
        var traceIdentitiesByPath = traceIdentities(from: tree).byPath
        let containerAnnotationsByPath = Dictionary(
            containerAnnotations.map { ($0.path, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let capturedElementIds = Set(tree.viewportCapture.heistIdsByPath.values)
        let capturedContainerPaths = Set(containerAnnotations.map(\.path))
        var emittedHeistIds = capturedElementIds
        var emittedContainerPaths = capturedContainerPaths
        var nextTraversalIndex = (tree.viewportCapture.hierarchy.pathIndexedElements.map(\.traversalIndex).max() ?? -1) + 1

        var childrenByContainerPath = DiscoveryChildren(
            tree: tree,
            capturedElementIds: capturedElementIds,
            capturedContainerPaths: capturedContainerPaths
        )

        func appendDiscoveryChildren(
            for containerPath: TreePath,
            to children: inout [AccessibilityHierarchy],
            path: TreePath
        ) {
            for child in childrenByContainerPath.removeChildren(parent: containerPath) {
                switch child.kind {
                case .element(let entry):
                    guard emittedHeistIds.insert(entry.heistId).inserted else { continue }
                    let childPath = path.appending(children.count)
                    children.append(.element(entry.element, traversalIndex: nextTraversalIndex))
                    nextTraversalIndex += 1
                    traceIdentitiesByPath[childPath] = entry.heistId.traceElementIdentity
                    elementAnnotations.append(InterfaceElementAnnotation(
                        path: childPath,
                        actions: entry.element.projectedActionSet.orderedActions
                    ))
                case .container(let entry):
                    guard emittedContainerPaths.insert(entry.path).inserted else {
                        continue
                    }
                    let childPath = path.appending(children.count)
                    containerPathBySourcePath[entry.path] = childPath
                    var nestedChildren: [AccessibilityHierarchy] = []
                    appendDiscoveryChildren(
                        for: entry.path,
                        to: &nestedChildren,
                        path: childPath
                    )
                    children.append(.container(entry.container, children: nestedChildren))
                    containerAnnotations.append(InterfaceContainerAnnotation(
                        path: childPath,
                        containerName: entry.containerName,
                        scrollInventory: entry.scrollInventory
                    ))
                }
            }
        }

        var foldAccumulator: Void = ()
        let hierarchy = tree.viewportCapture.hierarchy.enumerated().map { index, node -> AccessibilityHierarchy in
            node.folded(
                context: TreePath([index]),
                into: &foldAccumulator,
                onElement: { element, traversalIndex, _, _ in
                    .element(element, traversalIndex: traversalIndex)
                },
                onContainer: { container, children, path, _ in
                    var convertedChildren = children
                    if containerAnnotationsByPath[path] != nil {
                        appendDiscoveryChildren(for: path, to: &convertedChildren, path: path)
                    }
                    return .container(container, children: convertedChildren)
                },
                descend: { path, childIndex in path.appending(childIndex) }
            )
        }
        let elementAnnotationByPath = InterfaceAnnotations(elements: elementAnnotations).elementByPath
        let containerAnnotationByPath = InterfaceAnnotations(containers: containerAnnotations).containerByPath
        let interface = Interface(
            timestamp: timestamp,
            projecting: hierarchy,
            elementMetadata: { path, _, _ in
                guard let annotation = elementAnnotationByPath[path] else { return nil }
                return InterfaceElementProjectionMetadata(
                    actions: annotation.actions,
                    traceIdentity: traceIdentitiesByPath[path]
                )
            },
            containerMetadata: { path, _ in
                guard let annotation = containerAnnotationByPath[path] else { return nil }
                return InterfaceContainerProjectionMetadata(
                    containerName: annotation.containerName,
                    scrollInventory: annotation.scrollInventory
                )
            }
        )
        return DiscoveryProjection(
            interface: interface,
            containerPathBySourcePath: containerPathBySourcePath
        )
    }

    /// Convert the committed semantic screen into a trace-facing interface.
    ///
    /// Exploration commits the full targetable element set into
    /// the full interface tree; the latest live capture remains viewport-local
    /// evidence for action dispatch. Post-action traces compare semantic
    /// captures, so known off-viewport elements must be present here even when
    /// they are absent from the latest live parser hierarchy.
    static func toSemanticInterface(
        from tree: InterfaceTree,
        timestamp: Date = Date()
    ) -> Interface {
        semanticInterface(entries: tree.orderedElements, tree: tree, timestamp: timestamp)
    }

    private static func semanticInterface(
        entries: [InterfaceTree.Element],
        tree: InterfaceTree,
        timestamp: Date
    ) -> Interface {
        var pathAllocator = SemanticProjectionPathAllocator()
        let containerPlacements = semanticContainerPlacements(
            containersByPath: tree.containers,
            pathAllocator: &pathAllocator
        )
        let containersByProjectedPath = Dictionary(
            uniqueKeysWithValues: containerPlacements.map { ($0.path, $0.entry) }
        )
        let projectedContainerPathByOriginalPath = Dictionary(
            uniqueKeysWithValues: containerPlacements.map { ($0.entry.path, $0.path) }
        )
        let elementPlacements = semanticElementPlacements(
            entries: entries,
            projectedContainerPathByOriginalPath: projectedContainerPathByOriginalPath,
            pathAllocator: &pathAllocator
        )
        let elementsByPath = Dictionary(uniqueKeysWithValues: elementPlacements.map { ($0.path, $0.entry) })
        let traversalIndexByHeistId = Dictionary(uniqueKeysWithValues: entries.enumerated().map { index, entry in
            (entry.heistId, index)
        })
        let childPathsByParent = Dictionary(
            grouping: Array(elementsByPath.keys) + Array(containersByProjectedPath.keys)
        ) { path in
            path.parent ?? .root
        }.mapValues { paths in
            Array(Set(paths)).sorted()
        }

        var traversalIndex = 0
        var elementAnnotations: [InterfaceElementAnnotation] = []
        var containerAnnotations: [InterfaceContainerAnnotation] = []
        var traceIdentities: [TreePath: TraceElementIdentity] = [:]

        func buildNode(path: TreePath) -> AccessibilityHierarchy? {
            if let entry = elementsByPath[path] {
                let index = traversalIndex
                traversalIndex += 1
                elementAnnotations.append(InterfaceElementAnnotation(
                    path: path,
                    actions: entry.element.projectedActionSet.orderedActions
                ))
                traceIdentities[path] = entry.heistId.traceElementIdentity
                return .element(entry.element, traversalIndex: traversalIndexByHeistId[entry.heistId] ?? index)
            }
            guard let entry = containersByProjectedPath[path] else { return nil }
            containerAnnotations.append(InterfaceContainerAnnotation(
                path: path,
                containerName: entry.containerName,
                scrollInventory: entry.scrollInventory
            ))
            let children = (childPathsByParent[path] ?? []).compactMap(buildNode)
            return .container(entry.container, children: children)
        }

        let roots = (childPathsByParent[.root] ?? []).compactMap(buildNode)
        let elementAnnotationByPath = InterfaceAnnotations(elements: elementAnnotations).elementByPath
        let containerAnnotationByPath = InterfaceAnnotations(containers: containerAnnotations).containerByPath
        return Interface(
            timestamp: timestamp,
            projecting: roots,
            elementMetadata: { path, _, _ in
                guard let annotation = elementAnnotationByPath[path] else { return nil }
                return InterfaceElementProjectionMetadata(
                    actions: annotation.actions,
                    traceIdentity: traceIdentities[path]
                )
            },
            containerMetadata: { path, _ in
                guard let annotation = containerAnnotationByPath[path] else { return nil }
                return InterfaceContainerProjectionMetadata(
                    containerName: annotation.containerName,
                    scrollInventory: annotation.scrollInventory
                )
            }
        )
    }

    private static func semanticContainerPlacements(
        containersByPath: [TreePath: InterfaceTree.Container],
        pathAllocator: inout SemanticProjectionPathAllocator
    ) -> [SemanticContainerPlacement] {
        var projectedPathByOriginalPath: [TreePath: TreePath] = [:]

        return containersByPath.values
            .sorted { $0.path < $1.path }
            .map { entry in
                let parent = semanticContainerRepairParent(
                    for: entry,
                    projectedPathByOriginalPath: projectedPathByOriginalPath
                )
                let path = pathAllocator.nextChildPath(parent: parent)
                projectedPathByOriginalPath[entry.path] = path
                return SemanticContainerPlacement(path: path, entry: entry)
            }
    }

    private static func semanticElementPlacements(
        entries: [InterfaceTree.Element],
        projectedContainerPathByOriginalPath: [TreePath: TreePath],
        pathAllocator: inout SemanticProjectionPathAllocator
    ) -> [SemanticElementPlacement] {
        entries.map { entry in
            let parent = semanticElementRepairParent(
                for: entry,
                projectedContainerPathByOriginalPath: projectedContainerPathByOriginalPath
            )
            let path = pathAllocator.nextChildPath(parent: parent)
            return SemanticElementPlacement(path: path, entry: entry)
        }
    }

    private static func semanticContainerRepairParent(
        for entry: InterfaceTree.Container,
        projectedPathByOriginalPath: [TreePath: TreePath]
    ) -> TreePath {
        if let containerPath = entry.scrollMembership?.containerPath,
           let projectedPath = projectedPathByOriginalPath[containerPath] {
            return projectedPath
        }

        var parent = entry.path.parent
        while let candidate = parent {
            if candidate == .root { return .root }
            if let projectedPath = projectedPathByOriginalPath[candidate] {
                return projectedPath
            }
            parent = candidate.parent
        }
        return .root
    }

    private static func semanticElementRepairParent(
        for entry: InterfaceTree.Element,
        projectedContainerPathByOriginalPath: [TreePath: TreePath]
    ) -> TreePath {
        if let containerPath = entry.scrollMembership?.containerPath,
           let projectedPath = projectedContainerPathByOriginalPath[containerPath] {
            return projectedPath
        }

        var parent = entry.path.parent
        while let candidate = parent {
            if candidate == .root { return .root }
            if let projectedPath = projectedContainerPathByOriginalPath[candidate] {
                return projectedPath
            }
            parent = candidate.parent
        }
        return .root
    }

    // MARK: - Private Helpers

    private static func elementAnnotations(from tree: InterfaceTree) -> [InterfaceElementAnnotation] {
        tree.viewportCapture.hierarchy.compactMapSubtrees { node, path in
            guard case .element(let element, _) = node else { return nil }
            return InterfaceElementAnnotation(
                path: path,
                actions: element.projectedActionSet.orderedActions
            )
        }
    }

    private static func traceIdentities(from tree: InterfaceTree) -> InterfaceTraceIdentities {
        InterfaceTraceIdentities(Dictionary(uniqueKeysWithValues: tree.viewportCapture.heistIdsByPath.map { path, heistId in
            (path, heistId.traceElementIdentity)
        }))
    }

    private static func containerAnnotations(from tree: InterfaceTree) -> [InterfaceContainerAnnotation] {
        tree.viewportCapture.hierarchy.compactMapSubtrees { node, path in
            guard case .container = node else { return nil }
            return InterfaceContainerAnnotation(
                path: path,
                containerName: tree.containers[path]?.containerName,
                scrollInventory: tree.containers[path]?.scrollInventory
            )
        }
    }
    }
}

extension TheStash.WireConversion {
    struct DiscoveryProjection {
        let interface: Interface
        let containerPathBySourcePath: [TreePath: TreePath]
    }
}

private struct SemanticElementPlacement {
    let path: TreePath
    let entry: InterfaceTree.Element
}

private struct SemanticContainerPlacement {
    let path: TreePath
    let entry: InterfaceTree.Container
}

private struct SemanticProjectionPathAllocator {
    private var nextChildIndexByParent: [TreePath: Int] = [:]

    mutating func nextChildPath(parent: TreePath) -> TreePath {
        let index = nextChildIndexByParent[parent, default: 0]
        nextChildIndexByParent[parent] = index + 1
        return parent.appending(index)
    }
}

private struct DiscoveryChildren {
    enum ChildKind {
        case element(InterfaceTree.Element)
        case container(InterfaceTree.Container)
    }

    struct Child {
        let sortKey: SortKey
        let kind: ChildKind
    }

    struct SortKey: Comparable {
        let index: Int?
        let stableName: String

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            switch (lhs.index, rhs.index) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            return lhs.stableName < rhs.stableName
        }
    }

    private var childrenByParent: [TreePath: [Child]]

    init(
        tree: InterfaceTree,
        capturedElementIds: Set<HeistId>,
        capturedContainerPaths: Set<TreePath>
    ) {
        var childrenByParent: [TreePath: [Child]] = [:]
        for entry in tree.elements.values {
            guard !capturedElementIds.contains(entry.heistId),
                  let membership = entry.scrollMembership
            else { continue }
            childrenByParent[membership.containerPath, default: []].append(Child(
                sortKey: SortKey(
                    index: membership.index,
                    stableName: entry.heistId.rawValue
                ),
                kind: .element(entry)
            ))
        }
        for entry in tree.containers.values {
            guard !capturedContainerPaths.contains(entry.path),
                  let membership = entry.scrollMembership
            else { continue }
            let stableName = entry.containerName?.rawValue ?? entry.path.indices.map(String.init).joined(separator: ".")
            childrenByParent[membership.containerPath, default: []].append(Child(
                sortKey: SortKey(
                    index: membership.index,
                    stableName: stableName
                ),
                kind: .container(entry)
            ))
        }
        self.childrenByParent = childrenByParent.mapValues { children in
            children.sorted { $0.sortKey < $1.sortKey }
        }
    }

    mutating func removeChildren(parent: TreePath) -> [Child] {
        childrenByParent.removeValue(forKey: parent) ?? []
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
