import ThePlans
import AccessibilitySnapshotModel

package struct PathIndexedAccessibilityElement: Equatable, Sendable {
    package let element: AccessibilityElement
    package let path: TreePath
    package let traversalIndex: Int

    package init(element: AccessibilityElement, path: TreePath, traversalIndex: Int) {
        self.element = element
        self.path = path
        self.traversalIndex = traversalIndex
    }
}

package struct PathIndexedAccessibilityContainer: Equatable, Sendable {
    package let container: AccessibilityContainer
    package let path: TreePath

    package init(container: AccessibilityContainer, path: TreePath) {
        self.container = container
        self.path = path
    }
}

package enum AccessibilityHierarchyTraversal {
    enum Event {
        case enter(AccessibilityHierarchy, index: Int)
        case leave(AccessibilityContainer, childCount: Int)
    }

    @discardableResult
    static func walk(
        roots: [AccessibilityHierarchy],
        visit: (Event) -> Bool
    ) -> Bool {
        var events: [Event] = []
        events.reserveCapacity(roots.count)
        for index in roots.indices.reversed() {
            events.append(.enter(roots[index], index: index))
        }

        while let event = events.popLast() {
            guard visit(event) else { return false }
            guard case .enter(.container(let container, let children), _) = event else { continue }
            events.append(.leave(container, childCount: children.count))
            for index in children.indices.reversed() {
                events.append(.enter(children[index], index: index))
            }
        }
        return true
    }
}

package extension AccessibilityContainer {
    /// Whether this container can expose off-viewport content by scrolling.
    var isScrollable: Bool {
        if case .scrollable = type { return true }
        return scrollableContentSize != nil
    }
}

// MARK: - Derived Traversals

package extension AccessibilityHierarchy {
    func folded<Context, Accumulator, Result>(
        context: Context,
        into accumulator: inout Accumulator,
        onElement: (
            AccessibilityElement,
            Int,
            Context,
            inout Accumulator
        ) -> Result,
        onContainer: (
            AccessibilityContainer,
            [Result],
            Context,
            inout Accumulator
        ) -> Result,
        descend: (Context, Int) -> Context
    ) -> Result {
        var contexts: [Context] = []
        var results: [Result] = []
        AccessibilityHierarchyTraversal.walk(
            roots: [self],
            visit: { event in
                switch event {
                case .enter(.element(let element, let traversalIndex), let index):
                    let nodeContext = contexts.last.map { descend($0, index) } ?? context
                    results.append(onElement(element, traversalIndex, nodeContext, &accumulator))
                case .enter(.container, let index):
                    contexts.append(contexts.last.map { descend($0, index) } ?? context)
                case .leave(let container, let childCount):
                    let nodeContext = contexts.removeLast()
                    let childResults: [Result]
                    if childCount == 0 {
                        childResults = []
                    } else {
                        childResults = Array(results.suffix(childCount))
                        results.removeLast(childCount)
                    }
                    results.append(onContainer(container, childResults, nodeContext, &accumulator))
                }
                return true
            }
        )

        precondition(results.count == 1, "accessibility hierarchy fold must produce one root result")
        return results.removeLast()
    }

    func folded<Accumulator, Result>(
        into accumulator: inout Accumulator,
        onElement: (AccessibilityElement, Int, inout Accumulator) -> Result,
        onContainer: (AccessibilityContainer, [Result], inout Accumulator) -> Result
    ) -> Result {
        folded(
            context: (),
            into: &accumulator,
            onElement: { element, traversalIndex, _, accumulator in
                onElement(element, traversalIndex, &accumulator)
            },
            onContainer: { container, children, _, accumulator in
                onContainer(container, children, &accumulator)
            },
            descend: { _, _ in () }
        )
    }

    func folded<Result>(
        onElement: (AccessibilityElement, Int) -> Result,
        onContainer: (AccessibilityContainer, [Result]) -> Result
    ) -> Result {
        var accumulator: Void = ()
        return folded(
            into: &accumulator,
            onElement: { element, traversalIndex, _ in
                onElement(element, traversalIndex)
            },
            onContainer: { container, children, _ in
                onContainer(container, children)
            }
        )
    }

    @discardableResult
    func foldedPreorder<Context, Accumulator>(
        context: Context,
        into accumulator: inout Accumulator,
        onElement: (
            AccessibilityElement,
            Int,
            Context,
            inout Accumulator
        ) -> Bool,
        onContainer: (
            AccessibilityContainer,
            [AccessibilityHierarchy],
            Context,
            inout Accumulator
        ) -> Context,
        descend: (Context, Int) -> Context
    ) -> Bool {
        var contexts: [Context] = []
        return AccessibilityHierarchyTraversal.walk(
            roots: [self],
            visit: { event in
                switch event {
                case .enter(.element(let element, let traversalIndex), let index):
                    let nodeContext = contexts.last.map { descend($0, index) } ?? context
                    return onElement(element, traversalIndex, nodeContext, &accumulator)
                case .enter(.container(let container, let children), let index):
                    let nodeContext = contexts.last.map { descend($0, index) } ?? context
                    contexts.append(onContainer(container, children, nodeContext, &accumulator))
                    return true
                case .leave:
                    contexts.removeLast()
                    return true
                }
            }
        )
    }

    func compactingElements<Context, Accumulator>(
        context: Context,
        into accumulator: inout Accumulator,
        onElement: (
            AccessibilityElement,
            Int,
            Context,
            inout Accumulator
        ) -> AccessibilityHierarchy?,
        onContainer: (
            AccessibilityContainer,
            Context,
            inout Accumulator
        ) -> Context,
        childContext: (Context, Int, Int) -> Context
    ) -> AccessibilityHierarchy? {
        var result: AccessibilityHierarchy?
        var contexts: [Context] = []
        var transformedChildren: [[AccessibilityHierarchy]] = []
        func record(_ transformed: AccessibilityHierarchy) {
            if transformedChildren.isEmpty {
                result = transformed
            } else {
                transformedChildren[transformedChildren.count - 1].append(transformed)
            }
        }
        AccessibilityHierarchyTraversal.walk(
            roots: [self],
            visit: { event in
                switch event {
                case .enter(let hierarchy, let oldIndex):
                    let nodeContext = contexts.last.map {
                        childContext($0, oldIndex, transformedChildren.last?.count ?? 0)
                    } ?? context
                    switch hierarchy {
                    case .element(let element, let traversalIndex):
                        if let transformed = onElement(element, traversalIndex, nodeContext, &accumulator) {
                            record(transformed)
                        }
                    case .container(let container, _):
                        contexts.append(onContainer(container, nodeContext, &accumulator))
                        transformedChildren.append([])
                    }
                case .leave(let container, _):
                    contexts.removeLast()
                    record(.container(container, children: transformedChildren.removeLast()))
                }
                return true
            }
        )
        return result
    }
}

private func compactMapAccessibilityHierarchySubtrees<Result>(
    roots: [AccessibilityHierarchy],
    rootPath: (Int) -> TreePath,
    transform: (AccessibilityHierarchy, TreePath) -> Result?
) -> [Result] {
    var paths: [TreePath] = []
    var result: [Result] = []
    AccessibilityHierarchyTraversal.walk(
        roots: roots,
        visit: { event in
            switch event {
            case .enter(let hierarchy, let index):
                let path = paths.last?.appending(index) ?? rootPath(index)
                if let transformed = transform(hierarchy, path) {
                    result.append(transformed)
                }
                if case .container = hierarchy {
                    paths.append(path)
                }
            case .leave:
                paths.removeLast()
            }
            return true
        }
    )
    return result
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
        compactMapAccessibilityHierarchySubtrees(
            roots: [self],
            rootPath: { _ in path },
            transform: transform
        )
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
        compactMapAccessibilityHierarchySubtrees(
            roots: self,
            rootPath: { TreePath([$0]) },
            transform: transform
        )
    }
}

package extension Array where Element == AccessibilityHierarchy {
    var pathIndexedElements: [PathIndexedAccessibilityElement] {
        compactMapSubtrees { hierarchy, path -> PathIndexedAccessibilityElement? in
            guard case .element(let element, let traversalIndex) = hierarchy else {
                return nil
            }
            return PathIndexedAccessibilityElement(
                element: element,
                path: path,
                traversalIndex: traversalIndex
            )
        }
            .sorted {
                if $0.traversalIndex != $1.traversalIndex {
                    return $0.traversalIndex < $1.traversalIndex
                }
                return $0.path < $1.path
            }
    }

    var pathIndexedContainers: [PathIndexedAccessibilityContainer] {
        compactMapSubtrees { hierarchy, path in
            guard case .container(let container, _) = hierarchy else { return nil }
            return PathIndexedAccessibilityContainer(container: container, path: path)
        }
    }

    var scrollablePathIndexedContainers: [PathIndexedAccessibilityContainer] {
        pathIndexedContainers.filter(\.container.isScrollable)
    }
}
