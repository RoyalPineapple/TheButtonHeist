import AccessibilitySnapshotParser

// MARK: - Container Convenience

extension AccessibilityContainer {
    /// Whether this container is scrollable.
    var isScrollable: Bool {
        if case .scrollable = type { return true }
        return false
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
    /// This is the general-purpose tree destructor — `convertHierarchyNode` and `containers`
    /// are both built on it. Use it when the output type differs from `AccessibilityHierarchy`.
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

// MARK: - Top-Down Context Propagation

extension AccessibilityHierarchy {
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

    /// Transforms leaf elements, collecting non-nil results. No context propagation.
    public func compactMap<Result>(
        _ transform: (AccessibilityElement, Int) -> Result?
    ) -> [Result] {
        compactMap(context: (), container: { _, _ in () }, element: { element, traversalIndex, _ in
            transform(element, traversalIndex)
        })
    }

}

extension Array where Element == AccessibilityHierarchy {
    /// Transforms elements across all roots top-down with inherited context, collecting non-nil results.
    public func compactMap<Context, Result>(
        context: Context,
        container: (Context, AccessibilityContainer) -> Context,
        element: (AccessibilityElement, Int, Context) -> Result?
    ) -> [Result] {
        flatMap { $0.compactMap(context: context, container: container, element: element) }
    }

    /// Transforms leaf elements across all roots, collecting non-nil results. No context propagation.
    public func compactMap<Result>(
        _ transform: (AccessibilityElement, Int) -> Result?
    ) -> [Result] {
        flatMap { $0.compactMap(transform) }
    }

}

// MARK: - Leaf Extraction

extension AccessibilityHierarchy {
    /// The accessibility elements in this subtree, preserving traversal index.
    /// Order follows the tree's depth-first traversal (children visited left-to-right).
    /// The array-level `elements` property handles cross-root sorting.
    public var elements: [(element: AccessibilityElement, traversalIndex: Int)] {
        compactMap { element, traversalIndex in (element, traversalIndex) }
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
    /// The accessibility elements across all roots, sorted by traversal index.
    public var elements: [(element: AccessibilityElement, traversalIndex: Int)] {
        flatMap(\.elements).sorted { $0.traversalIndex < $1.traversalIndex }
    }

    /// The accessibility elements across all roots, sorted by traversal index, without the index tuple.
    /// Use when you need `[AccessibilityElement]` in traversal order (avoids the intermediate tuple array
    /// that `.elements.map(\.element)` would allocate).
    public var sortedElements: [AccessibilityElement] {
        elements.map(\.element)
    }

    /// All container nodes across all roots, depth-first (outermost first).
    public var containers: [AccessibilityContainer] {
        flatMap(\.containers)
    }

    // MARK: - Container Queries

    /// Scrollable containers in pre-order (outermost first).
    var scrollableContainers: [AccessibilityContainer] {
        containers.filter(\.isScrollable)
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
