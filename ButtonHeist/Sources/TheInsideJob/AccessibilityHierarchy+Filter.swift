import AccessibilitySnapshotParser

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

// MARK: - Reduce

extension AccessibilityHierarchy {
    /// Folds the tree into a single value via pre-order depth-first traversal.
    ///
    /// Each node is combined into the accumulator before its children, left to right.
    /// This mirrors `forEach` order — parent first, then children.
    public func reduced<Result>(
        _ initialResult: Result,
        _ combine: (Result, AccessibilityHierarchy) -> Result
    ) -> Result {
        var result = combine(initialResult, self)
        for child in children {
            result = child.reduced(result, combine)
        }
        return result
    }

    /// Folds the tree into a single value via pre-order depth-first traversal,
    /// with a throwing combine closure.
    public func reduced<Result>(
        _ initialResult: Result,
        _ combine: (Result, AccessibilityHierarchy) throws -> Result
    ) rethrows -> Result {
        var result = try combine(initialResult, self)
        for child in children {
            result = try child.reduced(result, combine)
        }
        return result
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

    /// Reduces all roots into a single value, visiting each tree left-to-right in pre-order.
    public func reducedHierarchy<Result>(
        _ initialResult: Result,
        _ combine: (Result, AccessibilityHierarchy) -> Result
    ) -> Result {
        var result = initialResult
        for root in self {
            result = root.reduced(result, combine)
        }
        return result
    }
}
