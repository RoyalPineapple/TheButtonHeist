import Foundation
import AccessibilitySnapshotModel

struct AccessibilityTraceHierarchyRecord {
    let ref: TreeNodeRef
    let location: TreeLocation
    let path: TreePath
    let node: AccessibilityHierarchy
    let element: HeistElement?
    let ancestors: [HeistContainer]
}

enum AccessibilityTraceTreeDiff {

    static func projectTreeEdits(before: Interface, after: Interface) -> ElementEdits {
        let oldRecords = traceHierarchyRecords(in: before)
        let newRecords = traceHierarchyRecords(in: after)
        let oldIds = Set(oldRecords.keys)
        let newIds = Set(newRecords.keys)

        let insertedIds = newIds.subtracting(oldIds)
        let removedIds = oldIds.subtracting(newIds)
        let insertedContainerIds = Set(insertedIds.compactMap { $0.kind == .container ? $0.id : nil })
        let removedContainerIds = Set(removedIds.compactMap { $0.kind == .container ? $0.id : nil })
        let inferredPairs = AccessibilityTraceMoveInference.inferFunctionalTreePairs(
            oldRecords: oldRecords,
            newRecords: newRecords,
            removedIds: removedIds,
            insertedIds: insertedIds
        )
        let inferredInsertedIds = Set(inferredPairs.map(\.insertedId))
        let inferredRemovedIds = Set(inferredPairs.map(\.removedId))

        let inserted = insertedIds.subtracting(inferredInsertedIds)
            .filter { identifier in
                guard let record = newRecords[identifier] else { return false }
                return !record.ancestors.contains(where: insertedContainerIds.contains)
            }
            .compactMap { identifier -> TreeInsertion? in
                guard let record = newRecords[identifier] else { return nil }
                return TreeInsertion(
                    location: record.location,
                    node: record.node,
                    annotations: after.annotations(
                        forSubtree: record.node,
                        originalPath: record.path,
                        rootPath: .root
                    )
                )
            }
            .sorted(by: treeInsertionOrder)

        let removed = removedIds.subtracting(inferredRemovedIds)
            .filter { identifier in
                guard let record = oldRecords[identifier] else { return false }
                return !record.ancestors.contains(where: removedContainerIds.contains)
            }
            .compactMap { identifier -> TreeRemoval? in
                guard let record = oldRecords[identifier] else { return nil }
                return TreeRemoval(ref: record.ref, location: record.location)
            }
            .sorted(by: treeRemovalOrder)

        let inferredMoves = inferredPairs.compactMap { pair -> TreeMove? in
            guard let old = oldRecords[pair.removedId],
                  let new = newRecords[pair.insertedId] else { return nil }
            guard old.location != new.location else { return nil }
            return TreeMove(ref: old.ref, from: old.location, to: new.location)
        }
        let rawMoved = oldIds.intersection(newIds).compactMap { identifier -> TreeMove? in
            guard let old = oldRecords[identifier], let new = newRecords[identifier] else { return nil }
            guard old.location != new.location else { return nil }
            return TreeMove(ref: new.ref, from: old.location, to: new.location)
        } + inferredMoves
        let movedContainerIds = Set(rawMoved.compactMap { $0.ref.kind == .container ? $0.ref.id : nil })
        let moved = rawMoved
            .filter { move in
                let ancestors = newRecords[move.ref]?.ancestors ?? []
                return !ancestors.contains(where: movedContainerIds.contains)
            }
            .sorted(by: treeMoveOrder)

        return ElementEdits(treeInserted: inserted, treeRemoved: removed, treeMoved: moved)
    }
}

func traceHierarchyRecords(in interface: Interface) -> [TreeNodeRef: AccessibilityTraceHierarchyRecord] {
    let elementAnnotations = interface.annotations.elementByPath
    let containerAnnotations = interface.annotations.containerByPath
    var result: [TreeNodeRef: AccessibilityTraceHierarchyRecord] = [:]
    for (index, node) in interface.tree.enumerated() {
        collectTreeRecords(
            node,
            path: TreePath([index]),
            parentId: nil,
            index: index,
            ancestors: [],
            elementAnnotations: elementAnnotations,
            containerAnnotations: containerAnnotations,
            into: &result
        )
    }
    return result
}

private func collectTreeRecords(
    _ node: AccessibilityHierarchy,
    path: TreePath,
    parentId: HeistContainer?,
    index: Int,
    ancestors: [HeistContainer],
    elementAnnotations: [TreePath: InterfaceElementAnnotation],
    containerAnnotations: [TreePath: InterfaceContainerAnnotation],
    into result: inout [TreeNodeRef: AccessibilityTraceHierarchyRecord]
) {
    let projection = elementProjection(for: node, path: path, annotations: elementAnnotations)
    let ref = treeRef(for: node, path: path, element: projection, containerAnnotations: containerAnnotations)
    let location = TreeLocation(parentId: parentId, index: index)
    let childParentId: HeistContainer?
    let childAncestors: [HeistContainer]
    if let ref {
        result[ref] = AccessibilityTraceHierarchyRecord(
            ref: ref,
            location: location,
            path: path,
            node: node,
            element: projection,
            ancestors: ancestors
        )
        childParentId = ref.id
        childAncestors = ancestors + [ref.id]
    } else {
        childParentId = parentId
        childAncestors = ancestors
    }

    guard case .container(_, let children) = node else { return }
    for (childIndex, child) in children.enumerated() {
        collectTreeRecords(
            child,
            path: path.appending(childIndex),
            parentId: childParentId,
            index: childIndex,
            ancestors: childAncestors,
            elementAnnotations: elementAnnotations,
            containerAnnotations: containerAnnotations,
            into: &result
        )
    }
}

private func elementProjection(
    for node: AccessibilityHierarchy,
    path: TreePath,
    annotations: [TreePath: InterfaceElementAnnotation]
) -> HeistElement? {
    switch node {
    case .element(let element, _):
        return HeistElement(
            accessibilityElement: element,
            annotation: annotations[path]
        )
    case .container:
        return nil
    }
}

private func treeRef(
    for node: AccessibilityHierarchy,
    path: TreePath,
    element: HeistElement?,
    containerAnnotations: [TreePath: InterfaceContainerAnnotation]
) -> TreeNodeRef? {
    switch node {
    case .element:
        guard let element, !element.heistId.isEmpty else { return nil }
        return TreeNodeRef(id: element.heistId, kind: .element)
    case .container:
        guard let stableId = containerAnnotations[path]?.stableId else { return nil }
        return TreeNodeRef(id: stableId, kind: .container)
    }
}

private func treeInsertionOrder(_ lhs: TreeInsertion, _ rhs: TreeInsertion) -> Bool {
    compare(lhs.location, rhs.location)
}

private func treeRemovalOrder(_ lhs: TreeRemoval, _ rhs: TreeRemoval) -> Bool {
    compare(lhs.location, rhs.location)
}

private func treeMoveOrder(_ lhs: TreeMove, _ rhs: TreeMove) -> Bool {
    compare(lhs.to, rhs.to)
}

private func compare(_ lhs: TreeLocation, _ rhs: TreeLocation) -> Bool {
    switch (lhs.parentId, rhs.parentId) {
    case let (left?, right?) where left != right:
        return left < right
    case (nil, _?):
        return true
    case (_?, nil):
        return false
    default:
        return lhs.index < rhs.index
    }
}
