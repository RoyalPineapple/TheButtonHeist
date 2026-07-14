import AccessibilitySnapshotModel
import ThePlans

package struct AccessibilityNodeRecord: Equatable, Sendable {
    package let path: TreePath
    package let node: AccessibilityHierarchy
    package let traversalIndex: Int?

    package init(path: TreePath, node: AccessibilityHierarchy, traversalIndex: Int?) {
        self.path = path
        self.node = node
        self.traversalIndex = traversalIndex
    }
}

package struct AccessibilityElementNodeRecord: Equatable, Sendable {
    package let path: TreePath
    package let element: AccessibilityElement
    package let traversalIndex: Int

    package init(path: TreePath, element: AccessibilityElement, traversalIndex: Int) {
        self.path = path
        self.element = element
        self.traversalIndex = traversalIndex
    }

    package var node: AccessibilityHierarchy {
        .element(element, traversalIndex: traversalIndex)
    }
}

package struct AccessibilityHierarchyGraph: Equatable, Sendable {
    package let nodesInPathOrder: [AccessibilityNodeRecord]
    package let elementsInTraversalOrder: [AccessibilityElementNodeRecord]

    private let nodesByPath: [TreePath: AccessibilityHierarchy]

    package init(tree: [AccessibilityHierarchy]) {
        let records: [(
            node: AccessibilityNodeRecord,
            element: AccessibilityElementNodeRecord?
        )] = tree.pathIndexedSubtrees.map { subtree in
            let node = subtree.hierarchy
            switch node {
            case .element(let element, let traversalIndex):
                return (
                    node: AccessibilityNodeRecord(
                        path: subtree.path,
                        node: node,
                        traversalIndex: traversalIndex
                    ),
                    element: AccessibilityElementNodeRecord(
                        path: subtree.path,
                        element: element,
                        traversalIndex: traversalIndex
                    )
                )
            case .container:
                return (
                    node: AccessibilityNodeRecord(
                        path: subtree.path,
                        node: node,
                        traversalIndex: nil
                    ),
                    element: nil
                )
            }
        }
        let nodesInPathOrder = records.map(\.node)
        let elements = records.compactMap(\.element)
        let nodesByPath = Dictionary(uniqueKeysWithValues: nodesInPathOrder.map { ($0.path, $0.node) })

        self.nodesInPathOrder = nodesInPathOrder
        self.elementsInTraversalOrder = elements.sorted {
            if $0.traversalIndex != $1.traversalIndex {
                return $0.traversalIndex < $1.traversalIndex
            }
            return $0.path < $1.path
        }
        self.nodesByPath = nodesByPath
    }

    package func node(at path: TreePath) -> AccessibilityHierarchy? {
        nodesByPath[path]
    }
}

package enum InterfaceGraphValidationError: Error, Equatable, CustomStringConvertible {
    case duplicateElementAnnotationPath(TreePath)
    case duplicateContainerAnnotationPath(TreePath)
    case elementAnnotationForMissingPath(TreePath)
    case elementAnnotationForContainerPath(TreePath)
    case containerAnnotationForMissingPath(TreePath)
    case containerAnnotationForElementPath(TreePath)
    case traceIdentityForMissingPath(TreePath)
    case traceIdentityForContainerPath(TreePath)

    package var description: String {
        switch self {
        case .duplicateElementAnnotationPath(let path):
            return "duplicate element annotation path \(path.diagnosticDescription)"
        case .duplicateContainerAnnotationPath(let path):
            return "duplicate container annotation path \(path.diagnosticDescription)"
        case .elementAnnotationForMissingPath(let path):
            return "element annotation references missing path \(path.diagnosticDescription)"
        case .elementAnnotationForContainerPath(let path):
            return "element annotation references container path \(path.diagnosticDescription)"
        case .containerAnnotationForMissingPath(let path):
            return "container annotation references missing path \(path.diagnosticDescription)"
        case .containerAnnotationForElementPath(let path):
            return "container annotation references element path \(path.diagnosticDescription)"
        case .traceIdentityForMissingPath(let path):
            return "trace identity references missing path \(path.diagnosticDescription)"
        case .traceIdentityForContainerPath(let path):
            return "trace identity references container path \(path.diagnosticDescription)"
        }
    }
}

package struct InterfaceGraphElementRecord: Equatable, Sendable {
    package let path: TreePath
    package let traversalIndex: Int
    package let accessibilityElement: AccessibilityElement
    package let annotation: InterfaceElementAnnotation?
    package let traceIdentity: TraceElementIdentity?

    package init(
        path: TreePath,
        traversalIndex: Int,
        accessibilityElement: AccessibilityElement,
        annotation: InterfaceElementAnnotation?,
        traceIdentity: TraceElementIdentity?
    ) {
        self.path = path
        self.traversalIndex = traversalIndex
        self.accessibilityElement = accessibilityElement
        self.annotation = annotation
        self.traceIdentity = traceIdentity
    }

    package var node: AccessibilityHierarchy {
        .element(accessibilityElement, traversalIndex: traversalIndex)
    }

    package var projectedElement: HeistElement {
        HeistElement(accessibilityElement: accessibilityElement, annotation: annotation)
    }

    package var interfaceRecord: InterfaceElementRecord {
        InterfaceElementRecord(
            path: path,
            traversalIndex: traversalIndex,
            element: projectedElement,
            traceIdentity: traceIdentity
        )
    }
}

package struct InterfaceGraphContainerRecord: Equatable, Sendable {
    package let path: TreePath
    package let container: AccessibilityContainer
    package let node: AccessibilityHierarchy
    package let annotation: InterfaceContainerAnnotation?

    package init(
        path: TreePath,
        container: AccessibilityContainer,
        node: AccessibilityHierarchy,
        annotation: InterfaceContainerAnnotation?
    ) {
        self.path = path
        self.container = container
        self.node = node
        self.annotation = annotation
    }
}

package enum InterfaceGraphNodeKind: Equatable, Sendable {
    case element(InterfaceGraphElementRecord)
    case container(InterfaceGraphContainerRecord)
}

package struct InterfaceGraphNodeRecord: Equatable, Sendable {
    package let path: TreePath
    package let node: AccessibilityHierarchy
    package let traversalIndex: Int?
    package let kind: InterfaceGraphNodeKind

    package init(
        path: TreePath,
        node: AccessibilityHierarchy,
        traversalIndex: Int?,
        kind: InterfaceGraphNodeKind
    ) {
        self.path = path
        self.node = node
        self.traversalIndex = traversalIndex
        self.kind = kind
    }
}

package struct InterfaceElementProjectionMetadata: Equatable, Sendable {
    package let actions: [ElementAction]
    package let traceIdentity: TraceElementIdentity?

    package init(actions: [ElementAction], traceIdentity: TraceElementIdentity? = nil) {
        self.actions = actions
        self.traceIdentity = traceIdentity
    }
}

package struct InterfaceContainerProjectionMetadata: Equatable, Sendable {
    package let containerName: ContainerName?
    package let scrollInventory: ScrollInventory?

    package init(containerName: ContainerName?, scrollInventory: ScrollInventory? = nil) {
        self.containerName = containerName
        self.scrollInventory = scrollInventory
    }
}

package struct InterfaceGraph: Equatable, Sendable {
    package let hierarchy: AccessibilityHierarchyGraph
    package let elementAnnotationByPath: [TreePath: InterfaceElementAnnotation]
    package let containerAnnotationByPath: [TreePath: InterfaceContainerAnnotation]
    package let traceIdentityByPath: [TreePath: TraceElementIdentity]
    package let elementsInTraversalOrder: [InterfaceGraphElementRecord]
    package let nodesInPathOrder: [InterfaceGraphNodeRecord]

    private let elementRecordByPath: [TreePath: InterfaceGraphElementRecord]

    package init(
        projecting tree: [AccessibilityHierarchy],
        elementMetadata: (TreePath, AccessibilityElement, Int) -> InterfaceElementProjectionMetadata?,
        containerMetadata: (TreePath, AccessibilityContainer) -> InterfaceContainerProjectionMetadata?
    ) {
        let hierarchy = AccessibilityHierarchyGraph(tree: tree)
        var elementAnnotationByPath: [TreePath: InterfaceElementAnnotation] = [:]
        var containerAnnotationByPath: [TreePath: InterfaceContainerAnnotation] = [:]
        var traceIdentityByPath: [TreePath: TraceElementIdentity] = [:]

        for record in hierarchy.nodesInPathOrder {
            switch record.node {
            case .element(let element, let traversalIndex):
                guard let metadata = elementMetadata(record.path, element, traversalIndex) else { continue }
                elementAnnotationByPath[record.path] = InterfaceElementAnnotation(
                    path: record.path,
                    actions: metadata.actions
                )
                traceIdentityByPath[record.path] = metadata.traceIdentity
            case .container(let container, _):
                guard let metadata = containerMetadata(record.path, container) else { continue }
                containerAnnotationByPath[record.path] = InterfaceContainerAnnotation(
                    path: record.path,
                    containerName: metadata.containerName,
                    scrollInventory: metadata.scrollInventory
                )
            }
        }

        self.init(
            hierarchy: hierarchy,
            elementAnnotationByPath: elementAnnotationByPath,
            containerAnnotationByPath: containerAnnotationByPath,
            traceIdentityByPath: traceIdentityByPath
        )
    }

    package init(
        tree: [AccessibilityHierarchy],
        annotations: InterfaceAnnotations = .empty,
        traceIdentities: InterfaceTraceIdentities = .empty
    ) throws(InterfaceGraphValidationError) {
        let hierarchy = AccessibilityHierarchyGraph(tree: tree)
        let elementAnnotationByPath = try Self.uniqueElementAnnotations(annotations.elements)
        let containerAnnotationByPath = try Self.uniqueContainerAnnotations(annotations.containers)
        let traceIdentityByPath = traceIdentities.byPath

        try Self.validateElementAnnotations(elementAnnotationByPath, in: hierarchy)
        try Self.validateContainerAnnotations(containerAnnotationByPath, in: hierarchy)
        try Self.validateTraceIdentities(traceIdentityByPath, in: hierarchy)

        self.init(
            hierarchy: hierarchy,
            elementAnnotationByPath: elementAnnotationByPath,
            containerAnnotationByPath: containerAnnotationByPath,
            traceIdentityByPath: traceIdentityByPath
        )
    }

    private init(
        hierarchy: AccessibilityHierarchyGraph,
        elementAnnotationByPath: [TreePath: InterfaceElementAnnotation],
        containerAnnotationByPath: [TreePath: InterfaceContainerAnnotation],
        traceIdentityByPath: [TreePath: TraceElementIdentity]
    ) {
        let nodeRecords = hierarchy.nodesInPathOrder.map { record in
            let kind: InterfaceGraphNodeKind
            switch record.node {
            case .element(let element, let traversalIndex):
                kind = .element(InterfaceGraphElementRecord(
                    path: record.path,
                    traversalIndex: traversalIndex,
                    accessibilityElement: element,
                    annotation: elementAnnotationByPath[record.path],
                    traceIdentity: traceIdentityByPath[record.path]
                ))
            case .container(let container, _):
                kind = .container(InterfaceGraphContainerRecord(
                    path: record.path,
                    container: container,
                    node: record.node,
                    annotation: containerAnnotationByPath[record.path]
                ))
            }
            return InterfaceGraphNodeRecord(
                path: record.path,
                node: record.node,
                traversalIndex: record.traversalIndex,
                kind: kind
            )
        }
        let elementRecords = nodeRecords.compactMap { record -> InterfaceGraphElementRecord? in
            guard case .element(let element) = record.kind else { return nil }
            return element
        }.sorted {
            if $0.traversalIndex != $1.traversalIndex {
                return $0.traversalIndex < $1.traversalIndex
            }
            return $0.path < $1.path
        }
        let elementRecordByPath = Dictionary(uniqueKeysWithValues: elementRecords.map { ($0.path, $0) })

        self.hierarchy = hierarchy
        self.elementAnnotationByPath = elementAnnotationByPath
        self.containerAnnotationByPath = containerAnnotationByPath
        self.traceIdentityByPath = traceIdentityByPath
        self.elementsInTraversalOrder = elementRecords
        self.nodesInPathOrder = nodeRecords
        self.elementRecordByPath = elementRecordByPath
    }

    package func node(at path: TreePath) -> AccessibilityHierarchy? {
        hierarchy.node(at: path)
    }

    package func element(at path: TreePath) -> InterfaceGraphElementRecord? {
        elementRecordByPath[path]
    }

    package func annotationsForSubtree(
        originalPath: TreePath,
        rootPath: TreePath
    ) -> InterfaceAnnotations {
        guard let node = hierarchy.node(at: originalPath) else {
            preconditionFailure("InterfaceGraph cannot select annotations for missing path \(originalPath.diagnosticDescription)")
        }
        let elements = node.compactMapSubtrees(path: rootPath) { node, newPath -> InterfaceElementAnnotation? in
            guard case .element = node,
                  let oldPath = originalPath.oldPath(forSubtreePath: newPath, rootedAt: rootPath),
                  let annotation = elementAnnotationByPath[oldPath]
            else { return nil }
            return InterfaceElementAnnotation(path: newPath, actions: annotation.actions)
        }
        let containers = node.compactMapSubtrees(path: rootPath) { node, newPath -> InterfaceContainerAnnotation? in
            guard case .container = node,
                  let oldPath = originalPath.oldPath(forSubtreePath: newPath, rootedAt: rootPath),
                  let annotation = containerAnnotationByPath[oldPath]
            else { return nil }
            return InterfaceContainerAnnotation(
                path: newPath,
                containerName: annotation.containerName,
                scrollInventory: annotation.scrollInventory
            )
        }
        return InterfaceAnnotations(elements: elements, containers: containers)
    }

    package func traceIdentitiesForSubtree(
        originalPath: TreePath,
        rootPath: TreePath
    ) -> InterfaceTraceIdentities {
        guard let node = hierarchy.node(at: originalPath) else {
            preconditionFailure("InterfaceGraph cannot select trace identities for missing path \(originalPath.diagnosticDescription)")
        }
        let identities = node.compactMapSubtrees(path: rootPath) { node, newPath -> (TreePath, TraceElementIdentity)? in
            guard case .element = node,
                  let oldPath = originalPath.oldPath(forSubtreePath: newPath, rootedAt: rootPath),
                  let identity = traceIdentityByPath[oldPath]
            else { return nil }
            return (newPath, identity)
        }
        return InterfaceTraceIdentities(Dictionary(uniqueKeysWithValues: identities))
    }

    private static func uniqueElementAnnotations(
        _ annotations: [InterfaceElementAnnotation]
    ) throws(InterfaceGraphValidationError) -> [TreePath: InterfaceElementAnnotation] {
        var byPath: [TreePath: InterfaceElementAnnotation] = [:]
        for annotation in annotations {
            guard byPath[annotation.path] == nil else {
                throw .duplicateElementAnnotationPath(annotation.path)
            }
            byPath[annotation.path] = annotation
        }
        return byPath
    }

    private static func uniqueContainerAnnotations(
        _ annotations: [InterfaceContainerAnnotation]
    ) throws(InterfaceGraphValidationError) -> [TreePath: InterfaceContainerAnnotation] {
        var byPath: [TreePath: InterfaceContainerAnnotation] = [:]
        for annotation in annotations {
            guard byPath[annotation.path] == nil else {
                throw .duplicateContainerAnnotationPath(annotation.path)
            }
            byPath[annotation.path] = annotation
        }
        return byPath
    }

    private static func validateElementAnnotations(
        _ annotations: [TreePath: InterfaceElementAnnotation],
        in hierarchy: AccessibilityHierarchyGraph
    ) throws(InterfaceGraphValidationError) {
        for path in annotations.keys.sorted() {
            switch hierarchy.node(at: path) {
            case nil:
                throw .elementAnnotationForMissingPath(path)
            case .container:
                throw .elementAnnotationForContainerPath(path)
            case .element:
                break
            }
        }
    }

    private static func validateContainerAnnotations(
        _ annotations: [TreePath: InterfaceContainerAnnotation],
        in hierarchy: AccessibilityHierarchyGraph
    ) throws(InterfaceGraphValidationError) {
        for path in annotations.keys.sorted() {
            switch hierarchy.node(at: path) {
            case nil:
                throw .containerAnnotationForMissingPath(path)
            case .element:
                throw .containerAnnotationForElementPath(path)
            case .container:
                break
            }
        }
    }

    private static func validateTraceIdentities(
        _ identities: [TreePath: TraceElementIdentity],
        in hierarchy: AccessibilityHierarchyGraph
    ) throws(InterfaceGraphValidationError) {
        for path in identities.keys.sorted() {
            switch hierarchy.node(at: path) {
            case nil:
                throw .traceIdentityForMissingPath(path)
            case .container:
                throw .traceIdentityForContainerPath(path)
            case .element:
                break
            }
        }
    }
}

private extension TreePath {
    var diagnosticDescription: String {
        "[\(indices.map(String.init).joined(separator: ", "))]"
    }

    func oldPath(forSubtreePath subtreePath: TreePath, rootedAt rootPath: TreePath) -> TreePath? {
        guard let relativePath = subtreePath.removingPrefix(rootPath) else { return nil }
        return appending(contentsOf: relativePath)
    }
}
