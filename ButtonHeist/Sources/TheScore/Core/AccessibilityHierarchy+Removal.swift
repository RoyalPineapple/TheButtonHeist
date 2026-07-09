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

package extension Array where Element == AccessibilityHierarchy {
    func removingElements<ID: Hashable & Sendable>(
        withIds removedIds: Set<ID>,
        idsByPath: [TreePath: ID]
    ) -> AccessibilityHierarchyRemoval<ID> {
        var hierarchy: [AccessibilityHierarchy] = []
        var remappedIdsByPath: [TreePath: ID] = [:]
        var pathMap: [TreePath: TreePath] = [:]
        for (oldIndex, node) in enumerated() {
            let oldPath = TreePath([oldIndex])
            let newPath = TreePath([hierarchy.count])
            guard let filteredNode = node.removingElements(
                withIds: removedIds,
                oldPath: oldPath,
                newPath: newPath,
                idsByPath: idsByPath,
                remappedIdsByPath: &remappedIdsByPath,
                pathMap: &pathMap
            ) else { continue }
            hierarchy.append(filteredNode)
        }
        return AccessibilityHierarchyRemoval(
            hierarchy: hierarchy,
            idsByPath: remappedIdsByPath,
            pathMap: pathMap
        )
    }
}

private extension AccessibilityHierarchy {
    func removingElements<ID: Hashable & Sendable>(
        withIds removedIds: Set<ID>,
        oldPath: TreePath,
        newPath: TreePath,
        idsByPath: [TreePath: ID],
        remappedIdsByPath: inout [TreePath: ID],
        pathMap: inout [TreePath: TreePath]
    ) -> AccessibilityHierarchy? {
        switch self {
        case .element(let element, let traversalIndex):
            guard let id = idsByPath[oldPath] else {
                pathMap[oldPath] = newPath
                return .element(element, traversalIndex: traversalIndex)
            }
            guard !removedIds.contains(id) else { return nil }
            pathMap[oldPath] = newPath
            remappedIdsByPath[newPath] = id
            return .element(element, traversalIndex: traversalIndex)

        case .container(let container, let children):
            pathMap[oldPath] = newPath
            var filteredChildren: [AccessibilityHierarchy] = []
            for (oldIndex, child) in children.enumerated() {
                let oldChildPath = oldPath.appending(oldIndex)
                let newChildPath = newPath.appending(filteredChildren.count)
                guard let filteredChild = child.removingElements(
                    withIds: removedIds,
                    oldPath: oldChildPath,
                    newPath: newChildPath,
                    idsByPath: idsByPath,
                    remappedIdsByPath: &remappedIdsByPath,
                    pathMap: &pathMap
                ) else { continue }
                filteredChildren.append(filteredChild)
            }
            return .container(container, children: filteredChildren)
        }
    }
}
