import AccessibilitySnapshotModel

public extension AccessibilityHierarchy {
    func pathIndexedElements(path: TreePath = .root) -> [(element: AccessibilityElement, path: TreePath, traversalIndex: Int)] {
        switch self {
        case .element(let element, let traversalIndex):
            return [(element, path, traversalIndex)]
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
    var pathIndexedElements: [(element: AccessibilityElement, path: TreePath, traversalIndex: Int)] {
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
