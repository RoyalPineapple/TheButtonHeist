import AccessibilitySnapshotModel

package struct AccessibilityElementTraversalRecord: Equatable, Sendable {
    package let element: AccessibilityElement
    package let traversalIndex: Int

    package init(element: AccessibilityElement, traversalIndex: Int) {
        self.element = element
        self.traversalIndex = traversalIndex
    }
}

// MARK: - Top-Down Context Propagation

package extension Array where Element == AccessibilityHierarchy {
    /// Transforms elements across all roots top-down with inherited context, collecting non-nil results.
    ///
    /// - `first`: maximum number of results to collect. 0 (default) means no limit.
    /// - `context`: the initial value at the root.
    /// - `container`: transforms the context at each container boundary.
    /// - `element`: transforms each leaf element into an optional result. Nil values are dropped.
    func compactMap<Context, Result>(
        first maxCount: Int = 0,
        context: Context,
        container transformContext: (Context, AccessibilityContainer) -> Context,
        element transformElement: (AccessibilityElement, Int, Context) -> Result?
    ) -> [Result] {
        var results: [Result] = []
        for root in self {
            let completed = root.foldedPreorder(
                context: context,
                into: &results,
                onElement: { accessibilityElement, traversalIndex, context, results in
                    if let result = transformElement(
                        accessibilityElement,
                        traversalIndex,
                        context
                    ) {
                        results.append(result)
                    }
                    return maxCount <= 0 || results.count < maxCount
                },
                onContainer: { accessibilityContainer, _, context, _ in
                    (transformContext(context, accessibilityContainer), true)
                },
                descend: { context, _ in context }
            )
            guard completed else { break }
        }
        return results
    }
}

// MARK: - Leaf Extraction

package extension AccessibilityHierarchy {
    /// The accessibility elements in this subtree, preserving traversal index.
    /// Order follows the tree's depth-first traversal (children visited left-to-right).
    /// The array-level `elements` property handles cross-root sorting.
    var elements: [AccessibilityElementTraversalRecord] {
        pathIndexedElements().map { indexedElement in
            AccessibilityElementTraversalRecord(
                element: indexedElement.element,
                traversalIndex: indexedElement.traversalIndex
            )
        }
    }

    /// The container nodes in this subtree, depth-first (outermost first).
    var containers: [AccessibilityContainer] {
        pathIndexedContainers().map(\.container)
    }

    /// Bottom-up fingerprint for container fingerprint computation.
    /// Combines element content fingerprints and container identity into a Merkle hash.
    /// Records each container's fingerprint into the shared dictionary.
    @discardableResult
    fileprivate func computeFingerprint(into result: inout [AccessibilityContainer: Int]) -> Int {
        folded(
            into: &result,
            onElement: { element, _, _ in
                hierarchyContentFingerprint(for: element)
            },
            onContainer: { container, childFingerprints, fingerprints in
                let fingerprint = hierarchyContentFingerprint(
                    for: container,
                    childFingerprints: childFingerprints
                )
                fingerprints[container] = fingerprint
                return fingerprint
            }
        )
    }
}

// MARK: - Array Conveniences

package extension Array where Element == AccessibilityHierarchy {
    /// The accessibility elements across all roots, sorted by traversal index.
    var elements: [AccessibilityElementTraversalRecord] {
        pathIndexedElements.map { indexedElement in
            AccessibilityElementTraversalRecord(
                element: indexedElement.element,
                traversalIndex: indexedElement.traversalIndex
            )
        }
    }

    /// The accessibility elements across all roots, sorted by traversal index, without traversal metadata.
    /// Convenience for `.elements.map(\.element)` when you only need the elements in traversal order.
    var sortedElements: [AccessibilityElement] {
        elements.map(\.element)
    }

    /// All container nodes across all roots, depth-first (outermost first).
    var containers: [AccessibilityContainer] {
        pathIndexedContainers.map(\.container)
    }

    // MARK: - Container Queries

    /// Scrollable containers in pre-order (outermost first).
    var scrollableContainers: [AccessibilityContainer] {
        containers.filter(\.isScrollable)
    }

    /// Each container mapped to its subtree content fingerprint.
    /// The canonical fold threads one shared dictionary through its derived computation.
    var containerFingerprints: [AccessibilityContainer: Int] {
        var result: [AccessibilityContainer: Int] = [:]
        for root in self {
            _ = root.computeFingerprint(into: &result)
        }
        return result
    }
}
