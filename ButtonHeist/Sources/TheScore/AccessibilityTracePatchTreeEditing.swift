import Foundation
import AccessibilitySnapshotModel

extension Array where Element == AccessibilityHierarchy {
    func hasSameShape(as other: [AccessibilityHierarchy]) -> Bool {
        guard count == other.count else { return false }
        return zip(self, other).allSatisfy { $0.hasSameShape(as: $1) }
    }

    var elementByPath: [TreePath: AccessibilityElement] {
        Dictionary(pathIndexedElements.map { ($0.path, $0.element) }, uniquingKeysWith: { _, latest in latest })
    }

    var containerByPath: [TreePath: AccessibilityContainer] {
        let entries: [(TreePath, AccessibilityContainer)] = compactMapSubtrees { node, path in
            guard case .container(let container, _) = node else { return nil }
            return (path, container)
        }
        return Dictionary(entries, uniquingKeysWith: { _, latest in latest })
    }

    func updatingElement(path: TreePath, with element: AccessibilityElement) -> [AccessibilityHierarchy] {
        guard let rootIndex = path.indices.first,
              indices.contains(rootIndex)
        else { return self }
        return enumerated().map { index, root in
            guard index == rootIndex else { return root }
            return root.updatingElement(path: TreePath([Int](path.indices.dropFirst())), with: element)
        }
    }

    func updatingContainer(path: TreePath, with container: AccessibilityContainer) -> [AccessibilityHierarchy] {
        enumerated().map { index, node in
            guard path.indices.first == index else { return node }
            return node.updatingContainer(path: TreePath([Int](path.indices.dropFirst())), with: container)
        }
    }

    func inserting(
        _ node: AccessibilityHierarchy,
        at location: TreeLocation,
        annotations: InterfaceAnnotations
    ) -> [AccessibilityHierarchy] {
        guard let parentPath = parentPath(for: location, annotations: annotations) else { return self }
        guard let rootIndex = parentPath.indices.first else {
            var roots = self
            roots.insert(node, at: bounded(location.index, count: roots.count))
            return roots
        }

        return enumerated().map { index, root in
            guard index == rootIndex else { return root }
            return root.inserting(
                node,
                inContainerAt: [Int](parentPath.indices.dropFirst()),
                childIndex: location.index
            )
        }
    }

    func removing(
        _ removal: TreeRemoval,
        annotations: InterfaceAnnotations
    ) -> [AccessibilityHierarchy] {
        guard let path = path(for: removal.ref, annotations: annotations)
            ?? path(for: removal.location, annotations: annotations)
        else { return self }
        return removing(at: path)
    }

    private func parentPath(
        for location: TreeLocation,
        annotations: InterfaceAnnotations
    ) -> TreePath? {
        guard let parentId = location.parentId else { return .root }
        return path(for: TreeNodeRef(id: parentId, kind: .container), annotations: annotations)
    }

    private func path(
        for location: TreeLocation,
        annotations: InterfaceAnnotations
    ) -> TreePath? {
        guard let parentPath = parentPath(for: location, annotations: annotations) else { return nil }
        return TreePath(parentPath.indices + [location.index])
    }

    private func path(
        for ref: TreeNodeRef,
        annotations: InterfaceAnnotations
    ) -> TreePath? {
        let elementAnnotations = annotations.elementByPath
        let containerAnnotations = annotations.containerByPath
        return compactMapSubtrees { node, path -> TreePath? in
            switch (ref.kind, node) {
            case (.element, .element)
                where elementAnnotations[path]?.heistId == ref.id:
                return path
            case (.container, .container)
                where containerAnnotations[path]?.stableId == ref.id:
                return path
            default:
                return nil
            }
        }.first
    }

    private func removing(at path: TreePath) -> [AccessibilityHierarchy] {
        guard let rootIndex = path.indices.first,
              indices.contains(rootIndex)
        else { return self }
        guard path.indices.count > 1 else {
            var roots = self
            roots.remove(at: rootIndex)
            return roots
        }

        return enumerated().map { index, root in
            guard index == rootIndex else { return root }
            return root.removing(at: [Int](path.indices.dropFirst()))
        }
    }
}

extension AccessibilityHierarchy {
    func hasSameShape(as other: AccessibilityHierarchy) -> Bool {
        switch (self, other) {
        case (.element, .element):
            return true
        case (.container(_, let lhsChildren), .container(_, let rhsChildren)):
            return lhsChildren.hasSameShape(as: rhsChildren)
        case (.element, .container), (.container, .element):
            return false
        }
    }

    func updatingElement(path: TreePath, with replacement: AccessibilityElement) -> AccessibilityHierarchy {
        switch self {
        case .element(_, let traversalIndex) where path.indices.isEmpty:
            return .element(replacement, traversalIndex: traversalIndex)
        case .element:
            return self
        case .container(let container, let children):
            guard let first = path.indices.first else { return self }
            let remainingPath = TreePath([Int](path.indices.dropFirst()))
            return .container(
                container,
                children: children.enumerated().map { index, child in
                    index == first ? child.updatingElement(path: remainingPath, with: replacement) : child
                }
            )
        }
    }

    func updatingContainer(path: TreePath, with replacement: AccessibilityContainer) -> AccessibilityHierarchy {
        guard let first = path.indices.first else {
            guard case .container(_, let children) = self else { return self }
            return .container(replacement, children: children)
        }
        guard case .container(let container, let children) = self else { return self }
        let remainingPath = TreePath([Int](path.indices.dropFirst()))
        return .container(
            container,
            children: children.enumerated().map { index, child in
                index == first ? child.updatingContainer(path: remainingPath, with: replacement) : child
            }
        )
    }

    func inserting(
        _ node: AccessibilityHierarchy,
        inContainerAt path: [Int],
        childIndex: Int
    ) -> AccessibilityHierarchy {
        guard case .container(let container, var children) = self else { return self }
        guard let first = path.first else {
            children.insert(node, at: bounded(childIndex, count: children.count))
            return .container(container, children: children)
        }
        guard children.indices.contains(first) else { return self }
        children[first] = children[first].inserting(
            node,
            inContainerAt: [Int](path.dropFirst()),
            childIndex: childIndex
        )
        return .container(container, children: children)
    }

    func removing(at path: [Int]) -> AccessibilityHierarchy {
        guard case .container(let container, var children) = self,
              let first = path.first,
              children.indices.contains(first)
        else { return self }
        guard path.count > 1 else {
            children.remove(at: first)
            return .container(container, children: children)
        }
        children[first] = children[first].removing(at: [Int](path.dropFirst()))
        return .container(container, children: children)
    }
}

private func bounded(_ index: Int, count: Int) -> Int {
    min(max(index, 0), count)
}
