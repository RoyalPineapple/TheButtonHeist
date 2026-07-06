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

package struct AccessibilityContainerNodeRecord: Equatable, Sendable {
    package let path: TreePath
    package let container: AccessibilityContainer
    package let node: AccessibilityHierarchy

    package init(path: TreePath, container: AccessibilityContainer, node: AccessibilityHierarchy) {
        self.path = path
        self.container = container
        self.node = node
    }
}

package struct AccessibilityHierarchyGraph: Equatable, Sendable {
    package let tree: [AccessibilityHierarchy]
    package let nodesInPathOrder: [AccessibilityNodeRecord]
    package let elementsInTraversalOrder: [AccessibilityElementNodeRecord]
    package let containersInPathOrder: [AccessibilityContainerNodeRecord]

    private let nodesByPath: [TreePath: AccessibilityHierarchy]

    package init(tree: [AccessibilityHierarchy]) {
        var nodesInPathOrder: [AccessibilityNodeRecord] = []
        var elements: [AccessibilityElementNodeRecord] = []
        var containers: [AccessibilityContainerNodeRecord] = []
        var nodesByPath: [TreePath: AccessibilityHierarchy] = [:]

        func visit(_ node: AccessibilityHierarchy, path: TreePath) {
            let traversalIndex: Int?
            switch node {
            case .element(_, let index):
                traversalIndex = index
            case .container:
                traversalIndex = nil
            }

            if nodesByPath.updateValue(node, forKey: path) != nil {
                preconditionFailure("AccessibilityHierarchyGraph cannot index duplicate path \(path.diagnosticDescription)")
            }
            nodesInPathOrder.append(AccessibilityNodeRecord(
                path: path,
                node: node,
                traversalIndex: traversalIndex
            ))

            switch node {
            case .element(let element, let traversalIndex):
                elements.append(AccessibilityElementNodeRecord(
                    path: path,
                    element: element,
                    traversalIndex: traversalIndex
                ))

            case .container(let container, let children):
                containers.append(AccessibilityContainerNodeRecord(
                    path: path,
                    container: container,
                    node: node
                ))
                for (index, child) in children.enumerated() {
                    visit(child, path: path.appending(index))
                }
            }
        }

        for (index, root) in tree.enumerated() {
            visit(root, path: TreePath([index]))
        }

        self.tree = tree
        self.nodesInPathOrder = nodesInPathOrder
        self.elementsInTraversalOrder = elements.sorted {
            if $0.traversalIndex != $1.traversalIndex {
                return $0.traversalIndex < $1.traversalIndex
            }
            return $0.path < $1.path
        }
        self.containersInPathOrder = containers
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

package struct InterfaceGraph: Equatable, Sendable {
    package let hierarchy: AccessibilityHierarchyGraph
    package let elementAnnotationByPath: [TreePath: InterfaceElementAnnotation]
    package let containerAnnotationByPath: [TreePath: InterfaceContainerAnnotation]
    package let traceIdentityByPath: [TreePath: TraceElementIdentity]
    package let elementsInTraversalOrder: [InterfaceGraphElementRecord]
    package let containersInPathOrder: [InterfaceGraphContainerRecord]
    package let nodesInPathOrder: [InterfaceGraphNodeRecord]

    package init(interface: Interface) throws(InterfaceGraphValidationError) {
        try self.init(
            tree: interface.tree,
            annotations: interface.annotations,
            traceIdentities: interface.traceIdentities
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

        let elementRecords = hierarchy.elementsInTraversalOrder.map { record in
            InterfaceGraphElementRecord(
                path: record.path,
                traversalIndex: record.traversalIndex,
                accessibilityElement: record.element,
                annotation: elementAnnotationByPath[record.path],
                traceIdentity: traceIdentityByPath[record.path]
            )
        }
        let containerRecords = hierarchy.containersInPathOrder.map { record in
            InterfaceGraphContainerRecord(
                path: record.path,
                container: record.container,
                node: record.node,
                annotation: containerAnnotationByPath[record.path]
            )
        }

        let elementsByPath = Dictionary(uniqueKeysWithValues: elementRecords.map { ($0.path, $0) })
        let containersByPath = Dictionary(uniqueKeysWithValues: containerRecords.map { ($0.path, $0) })
        let nodeRecords = hierarchy.nodesInPathOrder.map { record in
            let kind: InterfaceGraphNodeKind
            switch record.node {
            case .element:
                guard let elementRecord = elementsByPath[record.path] else {
                    preconditionFailure("InterfaceGraph missing element record for path \(record.path.diagnosticDescription)")
                }
                kind = .element(elementRecord)
            case .container:
                guard let containerRecord = containersByPath[record.path] else {
                    preconditionFailure("InterfaceGraph missing container record for path \(record.path.diagnosticDescription)")
                }
                kind = .container(containerRecord)
            }
            return InterfaceGraphNodeRecord(
                path: record.path,
                node: record.node,
                traversalIndex: record.traversalIndex,
                kind: kind
            )
        }

        self.hierarchy = hierarchy
        self.elementAnnotationByPath = elementAnnotationByPath
        self.containerAnnotationByPath = containerAnnotationByPath
        self.traceIdentityByPath = traceIdentityByPath
        self.elementsInTraversalOrder = elementRecords
        self.containersInPathOrder = containerRecords
        self.nodesInPathOrder = nodeRecords
    }

    package func node(at path: TreePath) -> AccessibilityHierarchy? {
        hierarchy.node(at: path)
    }

    package func element(at path: TreePath) -> InterfaceGraphElementRecord? {
        guard case .element(let record)? = nodesInPathOrder.first(where: { $0.path == path })?.kind else {
            return nil
        }
        return record
    }

    package func container(at path: TreePath) -> InterfaceGraphContainerRecord? {
        guard case .container(let record)? = nodesInPathOrder.first(where: { $0.path == path })?.kind else {
            return nil
        }
        return record
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
