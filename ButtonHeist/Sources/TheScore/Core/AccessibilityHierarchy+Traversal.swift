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

private enum AccessibilityHierarchyFoldFrame<Context> {
    case visit(AccessibilityHierarchy, Context)
    case combine(AccessibilityContainer, Context, childCount: Int)
}

package extension AccessibilityContainer {
    /// Whether this container can expose off-viewport content by scrolling.
    var isScrollable: Bool {
        if case .scrollable = type { return true }
        return scrollableContentSize != nil
    }
}

// MARK: - Canonical Fold

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
        var frames: [AccessibilityHierarchyFoldFrame<Context>] = [.visit(self, context)]
        var results: [Result] = []

        while let frame = frames.popLast() {
            switch frame {
            case .visit(.element(let element, let traversalIndex), let context):
                results.append(onElement(element, traversalIndex, context, &accumulator))
            case .visit(.container(let container, let children), let context):
                frames.append(.combine(container, context, childCount: children.count))
                for index in children.indices.reversed() {
                    frames.append(.visit(children[index], descend(context, index)))
                }
            case .combine(let container, let context, let childCount):
                let childResults: [Result]
                if childCount == 0 {
                    childResults = []
                } else {
                    childResults = Array(results.suffix(childCount))
                    results.removeLast(childCount)
                }
                results.append(onContainer(container, childResults, context, &accumulator))
            }
        }

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
        var pending: [(hierarchy: AccessibilityHierarchy, context: Context)] = [(self, context)]
        while let next = pending.popLast() {
            switch next.hierarchy {
            case let .element(element, traversalIndex):
                guard onElement(element, traversalIndex, next.context, &accumulator) else {
                    return false
                }
            case let .container(container, children):
                let step = onContainer(container, children, next.context, &accumulator)
                guard step.shouldContinue else { return false }
                for index in children.indices.reversed() {
                    pending.append((
                        children[index],
                        descend(step.contentsContext, index)
                    ))
                }
            }
        }
        return true
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
        switch self {
        case let .element(element, traversalIndex):
            return onElement(
                element,
                traversalIndex,
                context,
                &accumulator
            )
        case let .container(container, children):
            let contentsContext = onContainer(container, context, &accumulator)
            let transformedChildren = children.enumerated().reduce(
                into: [AccessibilityHierarchy]()
            ) { result, indexedChild in
                let (oldIndex, child) = indexedChild
                let context = childContext(contentsContext, oldIndex, result.count)
                guard let transformed = child.compactingElements(
                    context: context,
                    into: &accumulator,
                    onElement: onElement,
                    onContainer: onContainer,
                    childContext: childContext
                ) else { return }
                result.append(transformed)
            }
            return .container(container, children: transformedChildren)
        }
    }

    fileprivate func appendCompactMapSubtrees<Result>(
        path: TreePath,
        into result: inout [Result],
        transform: (AccessibilityHierarchy, TreePath) -> Result?
    ) {
        foldedPreorder(
            context: path,
            into: &result,
            onElement: { element, traversalIndex, path, result in
                if let transformed = transform(
                    .element(element, traversalIndex: traversalIndex),
                    path
                ) {
                    result.append(transformed)
                }
                return true
            },
            onContainer: { container, children, path, result in
                if let transformed = transform(.container(container, children: children), path) {
                    result.append(transformed)
                }
                return (path, true)
            },
            descend: { path, index in path.appending(index) }
        )
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
        var result: [Result] = []
        appendCompactMapSubtrees(path: path, into: &result, transform: transform)
        return result
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
        var result: [Result] = []
        for (index, root) in enumerated() {
            root.appendCompactMapSubtrees(
                path: TreePath([index]),
                into: &result,
                transform: transform
            )
        }
        return result
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
