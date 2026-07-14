import AccessibilitySnapshotModel
import ThePlans

package struct AccessibilityHierarchyRemoval<ID: Hashable & Sendable>: Sendable {
    package let hierarchy: [AccessibilityHierarchy]
    package let idsByPath: [TreePath: ID]
    package let pathMap: [TreePath: TreePath]

    package init(
        hierarchy: [AccessibilityHierarchy],
        idsByPath: [TreePath: ID],
        pathMap: [TreePath: TreePath]
    ) {
        self.hierarchy = hierarchy
        self.idsByPath = idsByPath
        self.pathMap = pathMap
    }
}

private struct AccessibilityHierarchyRemovalMetadata<ID: Hashable & Sendable> {
    var idsByPath: [TreePath: ID] = [:]
    var pathMap: [TreePath: TreePath] = [:]

    mutating func recordPath(from oldPath: TreePath, to newPath: TreePath) {
        guard pathMap.updateValue(newPath, forKey: oldPath) == nil else {
            preconditionFailure("Accessibility hierarchy removal produced a duplicate source path")
        }
    }

    mutating func record(id: ID, at path: TreePath) {
        guard idsByPath.updateValue(id, forKey: path) == nil else {
            preconditionFailure("Accessibility hierarchy removal produced a duplicate ID path")
        }
    }
}

private struct AccessibilityHierarchyRemovalPath {
    let old: TreePath
    let new: TreePath
}

package extension Array where Element == AccessibilityHierarchy {
    func removingElements<ID: Hashable & Sendable>(
        withIds removedIds: Set<ID>,
        idsByPath: [TreePath: ID]
    ) -> AccessibilityHierarchyRemoval<ID> {
        var metadata = AccessibilityHierarchyRemovalMetadata<ID>()
        let hierarchy = enumerated().reduce(
            into: [AccessibilityHierarchy]()
        ) { hierarchy, indexedRoot in
            let (oldIndex, root) = indexedRoot
            let rootPath = AccessibilityHierarchyRemovalPath(
                old: TreePath([oldIndex]),
                new: TreePath([hierarchy.count])
            )
            guard let transformed = root.compactingElements(
                context: rootPath,
                into: &metadata,
                onElement: { element, traversalIndex, path, metadata in
                    transformedElement(
                        element,
                        traversalIndex: traversalIndex,
                        path: path,
                        removedIds: removedIds,
                        idsByPath: idsByPath,
                        metadata: &metadata
                    )
                },
                onContainer: { _, path, metadata in
                    metadata.recordPath(from: path.old, to: path.new)
                    return path
                },
                childContext: { path, oldIndex, newIndex in
                    AccessibilityHierarchyRemovalPath(
                        old: path.old.appending(oldIndex),
                        new: path.new.appending(newIndex)
                    )
                }
            ) else { return }
            hierarchy.append(transformed)
        }
        return AccessibilityHierarchyRemoval(
            hierarchy: hierarchy,
            idsByPath: metadata.idsByPath,
            pathMap: metadata.pathMap
        )
    }
}

private func transformedElement<ID: Hashable & Sendable>(
    _ element: AccessibilityElement,
    traversalIndex: Int,
    path: AccessibilityHierarchyRemovalPath,
    removedIds: Set<ID>,
    idsByPath: [TreePath: ID],
    metadata: inout AccessibilityHierarchyRemovalMetadata<ID>
) -> AccessibilityHierarchy? {
    guard let id = idsByPath[path.old] else {
        metadata.recordPath(from: path.old, to: path.new)
        return .element(element, traversalIndex: traversalIndex)
    }
    guard !removedIds.contains(id) else { return nil }
    metadata.recordPath(from: path.old, to: path.new)
    metadata.record(id: id, at: path.new)
    return .element(element, traversalIndex: traversalIndex)
}
