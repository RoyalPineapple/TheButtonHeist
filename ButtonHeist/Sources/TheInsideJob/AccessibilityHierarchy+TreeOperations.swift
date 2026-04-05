import AccessibilitySnapshotParser

// MARK: - Container Convenience

extension AccessibilityContainer {
    /// Whether this container is scrollable.
    var isScrollable: Bool {
        if case .scrollable = type { return true }
        return false
    }
}

// MARK: - Filter

extension AccessibilityHierarchy {
    /// Returns a pruned copy of the tree containing only nodes where `isIncluded` returns true.
    ///
    /// For `.element` nodes, the element is kept when the predicate matches.
    /// For `.container` nodes, children are filtered recursively first. The container is kept
    /// when it has surviving children **or** the predicate matches the container itself.
    /// An empty container that matches the predicate is preserved (useful for finding
    /// specific container types like `.scrollable` or `.tabBar`).
    public func filtered(
        _ isIncluded: (AccessibilityHierarchy) -> Bool
    ) -> AccessibilityHierarchy? {
        switch self {
        case .element:
            return isIncluded(self) ? self : nil

        case let .container(container, children):
            let survivingChildren = children.compactMap { $0.filtered(isIncluded) }
            if !survivingChildren.isEmpty {
                return .container(container, children: survivingChildren)
            }
            if isIncluded(self) {
                return .container(container, children: [])
            }
            return nil
        }
    }
}

// MARK: - Map

extension AccessibilityHierarchy {
    /// Returns a new tree with `transform` applied to every node, bottom-up.
    ///
    /// Children are mapped before their parent, so the closure receives each container
    /// with its already-transformed children. This makes it safe to inspect or reshape
    /// subtrees during the transform.
    public func mapped(
        _ transform: (AccessibilityHierarchy) -> AccessibilityHierarchy
    ) -> AccessibilityHierarchy {
        switch self {
        case .element:
            return transform(self)

        case let .container(container, children):
            let mappedChildren = children.map { $0.mapped(transform) }
            return transform(.container(container, children: mappedChildren))
        }
    }
}

// MARK: - Fold (catamorphism — transform tree to a different type)

extension AccessibilityHierarchy {
    /// Transforms the tree into a value of a different type, bottom-up.
    ///
    /// For leaf elements: `onElement` receives the element and its traversal index.
    /// For containers: children are folded first, then `onContainer` receives the
    /// container metadata and the already-folded children.
    ///
    /// This is the general-purpose tree destructor — `mapped` and `convertHierarchyNode`
    /// are both special cases. Use it when the output type differs from `AccessibilityHierarchy`.
    public func folded<Result>(
        onElement: (AccessibilityElement, Int) -> Result,
        onContainer: (AccessibilityContainer, [Result]) -> Result
    ) -> Result {
        switch self {
        case let .element(element, traversalIndex):
            return onElement(element, traversalIndex)
        case let .container(container, children):
            let foldedChildren = children.map {
                $0.folded(onElement: onElement, onContainer: onContainer)
            }
            return onContainer(container, foldedChildren)
        }
    }
}

extension Array where Element == AccessibilityHierarchy {
    /// Folds each root into a different type, bottom-up.
    public func foldedHierarchy<Result>(
        onElement: (AccessibilityElement, Int) -> Result,
        onContainer: (AccessibilityContainer, [Result]) -> Result
    ) -> [Result] {
        map { $0.folded(onElement: onElement, onContainer: onContainer) }
    }
}

// MARK: - Top-Down Context Propagation

extension AccessibilityHierarchy {
    /// Walks the tree top-down, propagating a context value through containers to elements.
    ///
    /// - `context`: the initial value at the root.
    /// - `container`: transforms the context at each container boundary (parent context + container → child context).
    /// - `element`: called at each leaf with the element, its traversal index, and the inherited context.
    ///
    /// Use this when parent nodes establish context that child nodes need — e.g., a scroll
    /// view reference that propagates from a `.scrollable` container to its descendant elements.
    public func forEach<Context>(
        context: Context,
        container: (Context, AccessibilityContainer) -> Context,
        element: (AccessibilityElement, Int, Context) -> Void
    ) {
        switch self {
        case let .element(accessibilityElement, traversalIndex):
            element(accessibilityElement, traversalIndex, context)
        case let .container(accessibilityContainer, children):
            let childContext = container(context, accessibilityContainer)
            for child in children {
                child.forEach(context: childContext, container: container, element: element)
            }
        }
    }

    /// Transforms the tree's elements top-down with inherited context, collecting non-nil results.
    ///
    /// - `context`: the initial value at the root.
    /// - `container`: transforms the context at each container boundary.
    /// - `element`: transforms each leaf element into an optional result. Nil values are dropped.
    ///
    /// Combines `compactMap` with top-down context propagation — filter, transform, and
    /// inherit container context in a single pass.
    public func compactMap<Context, Result>(
        context: Context,
        container: (Context, AccessibilityContainer) -> Context,
        element: (AccessibilityElement, Int, Context) -> Result?
    ) -> [Result] {
        switch self {
        case let .element(accessibilityElement, traversalIndex):
            if let result = element(accessibilityElement, traversalIndex, context) {
                return [result]
            }
            return []
        case let .container(accessibilityContainer, children):
            let childContext = container(context, accessibilityContainer)
            return children.flatMap {
                $0.compactMap(context: childContext, container: container, element: element)
            }
        }
    }
}

extension Array where Element == AccessibilityHierarchy {
    /// Walks all roots top-down with inherited context.
    public func forEach<Context>(
        context: Context,
        container: (Context, AccessibilityContainer) -> Context,
        element: (AccessibilityElement, Int, Context) -> Void
    ) {
        for root in self {
            root.forEach(context: context, container: container, element: element)
        }
    }

    /// Transforms elements across all roots top-down with inherited context, collecting non-nil results.
    public func compactMap<Context, Result>(
        context: Context,
        container: (Context, AccessibilityContainer) -> Context,
        element: (AccessibilityElement, Int, Context) -> Result?
    ) -> [Result] {
        flatMap { $0.compactMap(context: context, container: container, element: element) }
    }
}

// MARK: - Leaf Extraction

extension AccessibilityHierarchy {
    /// The accessibility elements in this subtree, preserving traversal index.
    /// Order follows the tree's depth-first traversal (children visited left-to-right).
    /// The array-level `elements` property handles cross-root sorting.
    public var elements: [(element: AccessibilityElement, traversalIndex: Int)] {
        folded(
            onElement: { element, traversalIndex in [(element, traversalIndex)] },
            onContainer: { _, childLeaves in
                childLeaves.reduce(into: []) { result, leaves in result.append(contentsOf: leaves) }
            }
        )
    }

    /// The container nodes in this subtree, depth-first (outermost first).
    public var containers: [AccessibilityContainer] {
        folded(
            onElement: { _, _ in [] },
            onContainer: { container, childContainers in [container] + childContainers.flatMap { $0 } }
        )
    }

    /// Bottom-up fingerprint for container fingerprint computation.
    /// Combines element content fingerprints and container identity into a Merkle hash.
    /// Records each container's fingerprint into the shared dictionary.
    @discardableResult
    func computeFingerprint(into result: inout [AccessibilityContainer: Int]) -> Int {
        switch self {
        case .element(let element, _):
            var hasher = Hasher()
            hasher.combine(0)
            hasher.combine(element.contentFingerprint)
            return hasher.finalize()
        case .container(let container, let children):
            var hasher = Hasher()
            hasher.combine(1)
            hasher.combine(container)
            for child in children {
                hasher.combine(child.computeFingerprint(into: &result))
            }
            let fingerprint = hasher.finalize()
            result[container] = fingerprint
            return fingerprint
        }
    }
}

// MARK: - Array Conveniences

extension Array where Element == AccessibilityHierarchy {
    /// Filters each root node in the array, removing nodes that don't match the predicate.
    /// Container structure is preserved for branches that contain matching descendants.
    public func filteredHierarchy(
        _ isIncluded: (AccessibilityHierarchy) -> Bool
    ) -> [AccessibilityHierarchy] {
        compactMap { $0.filtered(isIncluded) }
    }

    /// Maps every node in every root, bottom-up.
    public func mappedHierarchy(
        _ transform: (AccessibilityHierarchy) -> AccessibilityHierarchy
    ) -> [AccessibilityHierarchy] {
        map { $0.mapped(transform) }
    }

    /// The accessibility elements across all roots, sorted by traversal index.
    public var elements: [(element: AccessibilityElement, traversalIndex: Int)] {
        flatMap(\.elements).sorted { $0.traversalIndex < $1.traversalIndex }
    }

    /// All container nodes across all roots, depth-first (outermost first).
    public var containers: [AccessibilityContainer] {
        flatMap(\.containers)
    }

    // MARK: - Container Queries

    /// Scrollable containers in pre-order (outermost first).
    var scrollableContainers: [AccessibilityContainer] {
        foldedHierarchy(
            onElement: { _, _ in [] },
            onContainer: { container, childResults in
                let descendants = childResults.flatMap { $0 }
                return container.isScrollable ? [container] + descendants : descendants
            }
        ).flatMap { $0 }
    }

    /// Each container mapped to its subtree content fingerprint.
    /// Uses a direct recursive walk with a single shared dictionary —
    /// no intermediate allocations at leaf nodes or dictionary merges.
    var containerFingerprints: [AccessibilityContainer: Int] {
        var result: [AccessibilityContainer: Int] = [:]
        for root in self {
            _ = root.computeFingerprint(into: &result)
        }
        return result
    }
}
