import ThePlans
import AccessibilitySnapshotModel

package struct PathIndexedAccessibilitySubtree {
    package let hierarchy: AccessibilityHierarchy
    package let path: TreePath
}

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

private enum AccessibilityHierarchyTraversal {
    enum ContainerDecision<Position> {
        case stop
        case descend(from: Position)
    }

    private enum Frame<Position> {
        case node(AccessibilityHierarchy, Position)
        case child(AccessibilityHierarchy, contentsPosition: Position, index: Int)
        case leave(AccessibilityContainer, childCount: Int, position: Position)
    }

    @discardableResult
    static func walk<Position>(
        roots: [AccessibilityHierarchy],
        rootPosition: (Int) -> Position,
        onElement: (AccessibilityElement, Int, Position) -> Bool,
        onContainerEnter: (
            AccessibilityContainer,
            [AccessibilityHierarchy],
            Position
        ) -> ContainerDecision<Position>,
        onContainerLeave: (
            AccessibilityContainer,
            Int,
            Position
        ) -> Void,
        descend: (Position, Int) -> Position
    ) -> Bool {
        var frames: [Frame<Position>] = []
        frames.reserveCapacity(roots.count)
        for index in roots.indices.reversed() {
            frames.append(.node(roots[index], rootPosition(index)))
        }

        while let frame = frames.popLast() {
            switch frame {
            case .node(.element(let element, let traversalIndex), let position):
                guard onElement(element, traversalIndex, position) else { return false }
            case .node(.container(let container, let children), let position):
                switch onContainerEnter(container, children, position) {
                case .stop:
                    return false
                case .descend(let contentsPosition):
                    frames.append(.leave(container, childCount: children.count, position: position))
                    for index in children.indices.reversed() {
                        frames.append(.child(children[index], contentsPosition: contentsPosition, index: index))
                    }
                }
            case .child(let hierarchy, let contentsPosition, let index):
                frames.append(.node(hierarchy, descend(contentsPosition, index)))
            case .leave(let container, let childCount, let position):
                onContainerLeave(container, childCount, position)
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
        var results: [Result] = []
        AccessibilityHierarchyTraversal.walk(
            roots: [self],
            rootPosition: { _ in context },
            onElement: { element, traversalIndex, context in
                results.append(onElement(element, traversalIndex, context, &accumulator))
                return true
            },
            onContainerEnter: { _, _, context in
                .descend(from: context)
            },
            onContainerLeave: { container, childCount, context in
                let childResults: [Result]
                if childCount == 0 {
                    childResults = []
                } else {
                    childResults = Array(results.suffix(childCount))
                    results.removeLast(childCount)
                }
                results.append(onContainer(container, childResults, context, &accumulator))
            },
            descend: descend
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
        ) -> (contentsContext: Context, shouldContinue: Bool),
        descend: (Context, Int) -> Context
    ) -> Bool {
        AccessibilityHierarchyTraversal.walk(
            roots: [self],
            rootPosition: { _ in context },
            onElement: { element, traversalIndex, context in
                onElement(element, traversalIndex, context, &accumulator)
            },
            onContainerEnter: { container, children, context in
                let step = onContainer(container, children, context, &accumulator)
                guard step.shouldContinue else { return .stop }
                return .descend(from: step.contentsContext)
            },
            onContainerLeave: { _, _, _ in },
            descend: descend
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
            rootPosition: { _ in context },
            onElement: { element, traversalIndex, context in
                guard let transformed = onElement(
                    element,
                    traversalIndex,
                    context,
                    &accumulator
                ) else { return true }
                record(transformed)
                return true
            },
            onContainerEnter: { container, _, context in
                transformedChildren.append([])
                return .descend(from: onContainer(container, context, &accumulator))
            },
            onContainerLeave: { container, _, _ in
                record(.container(
                    container,
                    children: transformedChildren.removeLast()
                ))
            },
            descend: { context, oldIndex in
                let newIndex = transformedChildren.last?.count ?? 0
                return childContext(context, oldIndex, newIndex)
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
    var result: [Result] = []
    AccessibilityHierarchyTraversal.walk(
        roots: roots,
        rootPosition: rootPath,
        onElement: { element, traversalIndex, path in
            if let transformed = transform(
                .element(element, traversalIndex: traversalIndex),
                path
            ) {
                result.append(transformed)
            }
            return true
        },
        onContainerEnter: { container, children, path in
            if let transformed = transform(.container(container, children: children), path) {
                result.append(transformed)
            }
            return .descend(from: path)
        },
        onContainerLeave: { _, _, _ in },
        descend: { path, index in path.appending(index) }
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

package extension AccessibilityHierarchy {
    func pathIndexedSubtrees(path: TreePath = .root) -> [PathIndexedAccessibilitySubtree] {
        compactMapSubtrees(path: path) { hierarchy, path in
            PathIndexedAccessibilitySubtree(hierarchy: hierarchy, path: path)
        }
    }

    func pathIndexedElements(path: TreePath = .root) -> [PathIndexedAccessibilityElement] {
        compactMapSubtrees(path: path) { hierarchy, path in
            guard case .element(let element, let traversalIndex) = hierarchy else { return nil }
            return PathIndexedAccessibilityElement(
                element: element,
                path: path,
                traversalIndex: traversalIndex
            )
        }
    }

    func pathIndexedContainers(path: TreePath = .root) -> [PathIndexedAccessibilityContainer] {
        compactMapSubtrees(path: path) { hierarchy, path in
            guard case .container(let container, _) = hierarchy else { return nil }
            return PathIndexedAccessibilityContainer(container: container, path: path)
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
        compactMapAccessibilityHierarchySubtrees(
            roots: self,
            rootPath: { TreePath([$0]) },
            transform: transform
        )
    }
}

package extension Array where Element == AccessibilityHierarchy {
    var pathIndexedSubtrees: [PathIndexedAccessibilitySubtree] {
        compactMapSubtrees { hierarchy, path in
            PathIndexedAccessibilitySubtree(hierarchy: hierarchy, path: path)
        }
    }

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
