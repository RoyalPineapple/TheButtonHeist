import Foundation
import AccessibilitySnapshotModel

public extension AccessibilityTrace.AccessibilityPatch {
    static func between(
        _ before: AccessibilityTrace.Capture,
        _ after: AccessibilityTrace.Capture
    ) -> AccessibilityTrace.AccessibilityPatch? {
        between(
            before.interface,
            after.interface,
            context: after.context,
            transition: after.transition
        )
    }

    static func between(
        _ before: Interface,
        _ after: Interface,
        context: AccessibilityTrace.Context,
        transition: AccessibilityTrace.Transition = .empty
    ) -> AccessibilityTrace.AccessibilityPatch? {
        AccessibilityTracePatchProjection.project(
            between: before,
            and: after,
            context: context,
            transition: transition
        ).patch
    }

    func apply(
        to capture: AccessibilityTrace.Capture,
        sequence: Int
    ) -> AccessibilityTrace.Capture {
        let interface = apply(to: capture.interface)
        return AccessibilityTrace.Capture(
            sequence: sequence,
            interface: interface,
            parentHash: capture.hash,
            context: context,
            transition: transition
        )
    }

    func apply(to interface: Interface) -> Interface {
        var tree = interface.tree
        var lookupAnnotations = interface.annotations

        for operation in operations {
            switch operation {
            case .updateElement(let path, let element):
                tree = tree.updatingElement(path: path, with: element)
            case .updateContainer(let path, let container):
                tree = tree.updatingContainer(path: path, with: container)
            case .insertSubtree(let insertion):
                tree = tree.inserting(insertion.node, at: insertion.location, annotations: lookupAnnotations)
                lookupAnnotations = annotations
            case .removeSubtree(let removal):
                tree = tree.removing(removal, annotations: lookupAnnotations)
            case .moveSubtree(let move, let node):
                tree = tree.removing(TreeRemoval(ref: move.ref, location: move.from), annotations: lookupAnnotations)
                tree = tree.inserting(node, at: move.to, annotations: annotations)
                lookupAnnotations = annotations
            case .replaceTree(let replacement):
                tree = replacement
                lookupAnnotations = annotations
            }
        }

        return Interface(
            timestamp: timestamp,
            tree: tree,
            annotations: annotations
        )
    }
}

enum AccessibilityTracePatchProjection {
    enum FullReplacementReason: String, Sendable {
        case incrementalProjectionDidNotReconstructTarget
    }

    enum Decision: Sendable, Equatable {
        case incremental(AccessibilityTrace.AccessibilityPatch)
        case fullReplacement(AccessibilityTrace.AccessibilityPatch, reason: FullReplacementReason)

        var patch: AccessibilityTrace.AccessibilityPatch {
            switch self {
            case .incremental(let patch),
                 .fullReplacement(let patch, _):
                return patch
            }
        }
    }

    static func project(
        between before: Interface,
        and after: Interface,
        context: AccessibilityTrace.Context,
        transition: AccessibilityTrace.Transition = .empty
    ) -> Decision {
        let structuralOperations = before.tree.hasSameShape(as: after.tree) ? [] :
            AccessibilityTrace.AccessibilityPatchOperation.structuralOperations(between: before, and: after)
        let structurallyPatched = AccessibilityTrace.AccessibilityPatch(
            operations: structuralOperations,
            timestamp: after.timestamp,
            annotations: after.annotations,
            context: context,
            transition: transition
        ).apply(to: before)
        let operations = structuralOperations + valueOperations(between: structurallyPatched, and: after)
        let patch = AccessibilityTrace.AccessibilityPatch(
            operations: operations,
            timestamp: after.timestamp,
            annotations: after.annotations,
            context: context,
            transition: transition
        )
        guard patch.apply(to: before) == after else {
            return .fullReplacement(
                fullReplacementPatch(for: after, context: context, transition: transition),
                reason: .incrementalProjectionDidNotReconstructTarget
            )
        }
        return .incremental(patch)
    }

    private static func fullReplacementPatch(
        for after: Interface,
        context: AccessibilityTrace.Context,
        transition: AccessibilityTrace.Transition
    ) -> AccessibilityTrace.AccessibilityPatch {
        AccessibilityTrace.AccessibilityPatch(
            operations: [.replaceTree(tree: after.tree)],
            timestamp: after.timestamp,
            annotations: after.annotations,
            context: context,
            transition: transition
        )
    }
}

extension AccessibilityTrace.AccessibilityPatchOperation {
    static func structuralOperations(
        between before: Interface,
        and after: Interface
    ) -> [Self] {
        let edits = AccessibilityTraceTreeDiff.projectTreeEdits(before: before, after: after)
        let afterRecords = traceHierarchyRecords(in: after)

        let removals = edits.removed
            .reversed()
            .map(Self.removeSubtree)
        let moves = edits.moved.compactMap { move -> Self? in
            guard let record = afterRecords[move.ref] else { return nil }
            return .moveSubtree(
                move,
                node: record.node
            )
        }
        let insertions = edits.inserted.map(Self.insertSubtree)

        return removals + moves + insertions
    }
}

private func valueOperations(
    between before: Interface,
    and after: Interface
) -> [AccessibilityTrace.AccessibilityPatchOperation] {
    guard before.tree.hasSameShape(as: after.tree) else { return [] }

    let beforeElements = before.tree.elementByPath
    let afterElements = after.tree.elementByPath
    let beforeContainers = before.tree.containerByPath
    let afterContainers = after.tree.containerByPath

    let elementOperations: [AccessibilityTrace.AccessibilityPatchOperation] =
        afterElements.keys.sorted().compactMap { path in
            guard let afterElement = afterElements[path],
                  beforeElements[path] != afterElement
            else { return nil }
            return AccessibilityTrace.AccessibilityPatchOperation.updateElement(
                path: path,
                element: afterElement
            )
        }

    let containerOperations: [AccessibilityTrace.AccessibilityPatchOperation] =
        afterContainers.keys.sorted().compactMap { path in
            guard let afterContainer = afterContainers[path],
                  beforeContainers[path] != afterContainer
            else { return nil }
            return AccessibilityTrace.AccessibilityPatchOperation.updateContainer(path: path, container: afterContainer)
        }

    return elementOperations + containerOperations
}
