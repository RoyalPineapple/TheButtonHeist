#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Wire Conversion

extension TheVault {

    /// Convert internal accessibility types (`AccessibilityElement`,
    /// `AccessibilityHierarchy`, `InterfaceObservation`) to their wire-facing projections.
    /// Pure transform — no stored state. Delta projection is capture-backed in
    /// TheScore.
    @MainActor enum WireConversion {

    // MARK: - Element Conversion

    static func convert(_ element: AccessibilityElement) -> HeistElement {
        HeistElement(
            accessibilityElement: element,
            actions: element.projectedActionSet.orderedActions
        )
    }

    // MARK: - Interface Conversion

    static func discoveryProjection(
        from tree: InterfaceTree,
        timestamp: Date = Date()
    ) -> DiscoveryProjection {
        InterfaceTreeProjection.discovery(from: tree, timestamp: timestamp).discoveryProjection
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
        InterfaceTreeProjection.semantic(from: tree, timestamp: timestamp).interface
    }

    }
}

extension TheVault.WireConversion {
    struct DiscoveryProjection {
        let interface: Interface
        let containerPathBySourcePath: [TreePath: TreePath]
    }
}

@MainActor
private struct InterfaceTreeProjection {
    let interface: Interface
    let containerPathBySourcePath: [TreePath: TreePath]

    var discoveryProjection: TheVault.WireConversion.DiscoveryProjection {
        TheVault.WireConversion.DiscoveryProjection(
            interface: interface,
            containerPathBySourcePath: containerPathBySourcePath
        )
    }

    static func discovery(
        from tree: InterfaceTree,
        timestamp: Date
    ) -> InterfaceTreeProjection {
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

        return InterfaceTreeProjection(
            interface: interface(
                timestamp: timestamp,
                hierarchy: hierarchy,
                elementAnnotations: elementAnnotations,
                containerAnnotations: containerAnnotations,
                traceIdentitiesByPath: traceIdentitiesByPath
            ),
            containerPathBySourcePath: containerPathBySourcePath
        )
    }

    static func semantic(
        from tree: InterfaceTree,
        timestamp: Date
    ) -> InterfaceTreeProjection {
        let entries = tree.orderedElements
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
        var traceIdentitiesByPath: [TreePath: TraceElementIdentity] = [:]

        func buildNode(path: TreePath) -> AccessibilityHierarchy? {
            if let entry = elementsByPath[path] {
                let index = traversalIndex
                traversalIndex += 1
                elementAnnotations.append(InterfaceElementAnnotation(
                    path: path,
                    actions: entry.element.projectedActionSet.orderedActions
                ))
                traceIdentitiesByPath[path] = entry.heistId.traceElementIdentity
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
        return InterfaceTreeProjection(
            interface: interface(
                timestamp: timestamp,
                hierarchy: roots,
                elementAnnotations: elementAnnotations,
                containerAnnotations: containerAnnotations,
                traceIdentitiesByPath: traceIdentitiesByPath
            ),
            containerPathBySourcePath: projectedContainerPathByOriginalPath
        )
    }

    private static func interface(
        timestamp: Date,
        hierarchy: [AccessibilityHierarchy],
        elementAnnotations: [InterfaceElementAnnotation],
        containerAnnotations: [InterfaceContainerAnnotation],
        traceIdentitiesByPath: [TreePath: TraceElementIdentity]
    ) -> Interface {
        let elementAnnotationByPath = InterfaceAnnotations(elements: elementAnnotations).elementByPath
        let containerAnnotationByPath = InterfaceAnnotations(containers: containerAnnotations).containerByPath
        return Interface(
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
