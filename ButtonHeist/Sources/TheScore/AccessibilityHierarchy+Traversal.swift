import ThePlans
import AccessibilitySnapshotModel

public struct PathIndexedAccessibilityElement {
    public let element: AccessibilityElement
    public let path: TreePath
    public let traversalIndex: Int

    public init(element: AccessibilityElement, path: TreePath, traversalIndex: Int) {
        self.element = element
        self.path = path
        self.traversalIndex = traversalIndex
    }
}

public extension AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        guard let childIndex = path.indices.first else { return self }
        guard case .container(_, let children) = self,
              children.indices.contains(childIndex)
        else { return nil }
        return children[childIndex].node(at: TreePath([Int](path.indices.dropFirst())))
    }

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

public extension Array where Element == AccessibilityHierarchy {
    func node(at path: TreePath) -> AccessibilityHierarchy? {
        guard let rootIndex = path.indices.first,
              indices.contains(rootIndex)
        else { return nil }
        guard path.indices.count > 1 else { return self[rootIndex] }
        return self[rootIndex].node(at: TreePath([Int](path.indices.dropFirst())))
    }

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

    func compactMapSubtrees<Result>(
        _ transform: (AccessibilityHierarchy, TreePath) -> Result?
    ) -> [Result] {
        enumerated().flatMap { index, root in
            root.compactMapSubtrees(path: TreePath([index]), transform)
        }
    }
}

public extension TreePath {
    func hasPrefix(_ prefix: TreePath) -> Bool {
        guard prefix.indices.count <= indices.count else { return false }
        return zip(prefix.indices, indices).allSatisfy { $0 == $1 }
    }
}
