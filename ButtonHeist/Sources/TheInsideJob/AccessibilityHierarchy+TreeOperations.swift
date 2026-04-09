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
    func folded<Result>(
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
    /// - `first`: maximum number of results to collect. 0 (default) means no limit — walk the
    ///   entire tree. Use `first: 1` for first-match, `first: 2` for unique-match, etc.
    /// - `context`: the initial value at the root.
    /// - `container`: transforms the context at each container boundary.
    /// - `element`: transforms each leaf element into an optional result. Nil values are dropped.
    ///
    /// Returns `true` when the limit was reached (early exit signal for internal recursion).
    @discardableResult
    fileprivate func compactMap<Context, Result>(
        first maxCount: Int = 0,
        context: Context,
        into results: inout [Result],
        container: (Context, AccessibilityContainer) -> Context,
        element: (AccessibilityElement, Int, Context) -> Result?
    ) -> Bool {
        switch self {
        case let .element(accessibilityElement, traversalIndex):
            if let result = element(accessibilityElement, traversalIndex, context) {
                results.append(result)
                if maxCount > 0, results.count >= maxCount { return true }
            }
            return false
        case let .container(accessibilityContainer, children):
            let childContext = container(context, accessibilityContainer)
            for child in children {
                let limitReached = child.compactMap(
                    first: maxCount, context: childContext, into: &results,
                    container: container, element: element
                )
                if limitReached { return true }
            }
            return false
        }
    }
}

extension Array where Element == AccessibilityHierarchy {
    /// Transforms elements across all roots top-down with inherited context, collecting non-nil results.
    ///
    /// - `first`: maximum number of results to collect. 0 (default) means no limit.
    /// - `context`: the initial value at the root.
    /// - `container`: transforms the context at each container boundary.
    /// - `element`: transforms each leaf element into an optional result. Nil values are dropped.
    func compactMap<Context, Result>(
        first maxCount: Int = 0,
        context: Context,
        container: (Context, AccessibilityContainer) -> Context,
        element: (AccessibilityElement, Int, Context) -> Result?
    ) -> [Result] {
        var results: [Result] = []
        for root in self {
            let limitReached = root.compactMap(
                first: maxCount, context: context, into: &results,
                container: container, element: element
            )
            if limitReached { break }
        }
        return results
    }
}

// MARK: - Bottom-Up Fold with Shared Accumulator

extension AccessibilityHierarchy {
    /// Bottom-up fold that threads a shared mutable accumulator through the recursion.
    ///
    /// Like `folded(onElement:onContainer:)` but with an `inout Accumulator` parameter
    /// so container nodes can record side-channel data (fingerprints, counts, etc.)
    /// without allocating intermediate collections at every leaf.
    ///
    /// - `accumulator`: shared mutable state threaded through all nodes.
    /// - `onElement`: produces the leaf result, may write into the accumulator.
    /// - `onContainer`: receives the container, already-folded child results, and the
    ///   accumulator. Produces the container result and may write into the accumulator.
    @discardableResult
    private func folded<Accumulator, Result>(
        into accumulator: inout Accumulator,
        onElement: (AccessibilityElement, Int, inout Accumulator) -> Result,
        onContainer: (AccessibilityContainer, [Result], inout Accumulator) -> Result
    ) -> Result {
        switch self {
        case let .element(element, traversalIndex):
            return onElement(element, traversalIndex, &accumulator)
        case let .container(container, children):
            let foldedChildren = children.map {
                $0.folded(into: &accumulator, onElement: onElement, onContainer: onContainer)
            }
            return onContainer(container, foldedChildren, &accumulator)
        }
    }
}

// MARK: - Leaf Extraction

extension AccessibilityHierarchy {
    /// The accessibility elements in this subtree, preserving traversal index.
    /// Order follows the tree's depth-first traversal (children visited left-to-right).
    /// The array-level `elements` property handles cross-root sorting.
    var elements: [(element: AccessibilityElement, traversalIndex: Int)] {
        [self].compactMap(context: (), container: { _, _ in () }, element: { element, traversalIndex, _ in
            (element, traversalIndex)
        })
    }

    /// The container nodes in this subtree, depth-first (outermost first).
    var containers: [AccessibilityContainer] {
        folded(
            onElement: { _, _ in [] },
            onContainer: { container, childContainers in [container] + childContainers.flatMap { $0 } }
        )
    }

    /// Bottom-up fingerprint for container fingerprint computation.
    /// Combines element content fingerprints and container identity into a Merkle hash.
    /// Records each container's fingerprint into the shared dictionary.
    @discardableResult
    fileprivate func computeFingerprint(into result: inout [AccessibilityContainer: Int]) -> Int {
        folded(
            into: &result,
            onElement: { element, _, _ in
                var hasher = Hasher()
                hasher.combine(0)
                hasher.combine(element.contentFingerprint)
                return hasher.finalize()
            },
            onContainer: { container, childFingerprints, accumulator in
                var hasher = Hasher()
                hasher.combine(1)
                hasher.combine(container)
                for childFingerprint in childFingerprints {
                    hasher.combine(childFingerprint)
                }
                let fingerprint = hasher.finalize()
                accumulator[container] = fingerprint
                return fingerprint
            }
        )
    }
}

// MARK: - Array Conveniences

extension Array where Element == AccessibilityHierarchy {
    /// The accessibility elements across all roots, sorted by traversal index.
    var elements: [(element: AccessibilityElement, traversalIndex: Int)] {
        flatMap(\.elements).sorted { $0.traversalIndex < $1.traversalIndex }
    }

    /// The accessibility elements across all roots, sorted by traversal index, without the index tuple.
    /// Convenience for `.elements.map(\.element)` when you only need the elements in traversal order.
    var sortedElements: [AccessibilityElement] {
        elements.map(\.element)
    }

    /// All container nodes across all roots, depth-first (outermost first).
    var containers: [AccessibilityContainer] {
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
