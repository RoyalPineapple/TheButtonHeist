import ThePlans
import AccessibilitySnapshotModel

package struct PathIndexedAccessibilityElement {
    package let element: AccessibilityElement
    package let path: TreePath
    package let traversalIndex: Int

    package init(element: AccessibilityElement, path: TreePath, traversalIndex: Int) {
        self.element = element
        self.path = path
        self.traversalIndex = traversalIndex
    }
}

package struct PathIndexedAccessibilityContainer {
    package let container: AccessibilityContainer
    package let path: TreePath

    package init(container: AccessibilityContainer, path: TreePath) {
        self.container = container
        self.path = path
    }
}

package extension AccessibilityContainer {
    /// Whether this container can expose off-viewport content by scrolling.
    var isScrollable: Bool {
        if case .scrollable = type { return true }
        return scrollableContentSize != nil
    }
}

public extension AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        var current = self
        for childIndex in path.indices {
            guard case .container(_, let children) = current,
                  children.indices.contains(childIndex)
            else { return nil }
            current = children[childIndex]
        }
        return current
    }

    func compactMapSubtrees<Result>(
        path: TreePath = .root,
        _ transform: (AccessibilityHierarchy, TreePath) -> Result?
    ) -> [Result] {
        var results: [Result] = []
        if let result = transform(self, path) {
            results.append(result)
        }
        if case .container(_, let children) = self {
            for (index, child) in children.enumerated() {
                results.append(contentsOf: child.compactMapSubtrees(path: path.appending(index), transform))
            }
        }
        return results
    }
}

package extension AccessibilityHierarchy {
    func pathIndexedElements(path: TreePath = .root) -> [PathIndexedAccessibilityElement] {
        switch self {
        case .element(let element, let traversalIndex):
            return [PathIndexedAccessibilityElement(
                element: element,
                path: path,
                traversalIndex: traversalIndex
            )]
        case .container(_, let children):
            return children.enumerated().flatMap { index, child in
                child.pathIndexedElements(path: path.appending(index))
            }
        }
    }

    func pathIndexedContainers(path: TreePath = .root) -> [PathIndexedAccessibilityContainer] {
        switch self {
        case .element:
            return []
        case .container(let container, let children):
            return [PathIndexedAccessibilityContainer(container: container, path: path)]
                + children.enumerated().flatMap { index, child in
                    child.pathIndexedContainers(path: path.appending(index))
                }
        }
    }
}

public extension Array where Element == AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        guard let rootIndex = path.indices.first,
              indices.contains(rootIndex)
        else { return nil }
        guard path.indices.count > 1 else { return self[rootIndex] }
        guard let subtreePath = path.removingPrefix(TreePath([rootIndex])) else { return nil }
        return self[rootIndex].node(at: subtreePath)
    }

    func compactMapSubtrees<Result>(
        _ transform: (AccessibilityHierarchy, TreePath) -> Result?
    ) -> [Result] {
        enumerated().flatMap { index, root in
            root.compactMapSubtrees(path: TreePath([index]), transform)
        }
    }
}

package extension Array where Element == AccessibilityHierarchy {
    var pathIndexedElements: [PathIndexedAccessibilityElement] {
        enumerated()
            .flatMap { index, root in root.pathIndexedElements(path: TreePath([index])) }
            .sorted {
                if $0.traversalIndex != $1.traversalIndex {
                    return $0.traversalIndex < $1.traversalIndex
                }
                return $0.path < $1.path
            }
    }

    var pathIndexedContainers: [PathIndexedAccessibilityContainer] {
        enumerated()
            .flatMap { index, root in root.pathIndexedContainers(path: TreePath([index])) }
    }

    var scrollablePathIndexedContainers: [PathIndexedAccessibilityContainer] {
        pathIndexedContainers.filter(\.container.isScrollable)
    }
}
