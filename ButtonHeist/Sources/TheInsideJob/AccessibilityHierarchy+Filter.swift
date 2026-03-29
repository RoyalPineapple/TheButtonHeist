import AccessibilitySnapshotParser

// MARK: - Tree Filtering

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

// MARK: - Array Convenience

extension Array where Element == AccessibilityHierarchy {
    /// Filters each root node in the array, removing nodes that don't match the predicate.
    /// Container structure is preserved for branches that contain matching descendants.
    public func filteredHierarchy(
        _ isIncluded: (AccessibilityHierarchy) -> Bool
    ) -> [AccessibilityHierarchy] {
        compactMap { $0.filtered(isIncluded) }
    }
}
