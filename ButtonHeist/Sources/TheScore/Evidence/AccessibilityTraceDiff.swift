import ThePlans
import Foundation
import AccessibilitySnapshotModel

/// Computes canonical change facts between two accessibility captures.
///
/// Captures stay the durable truth; this derives the fact stream on demand.
enum AccessibilityTraceDiff {

    static func projectChangeFacts(
        between before: AccessibilityTrace.Capture,
        and after: AccessibilityTrace.Capture
    ) -> [AccessibilityTrace.ChangeFact] {
        let edge = AccessibilityTrace.CaptureEdge(before: before, after: after)
        let interactionDigest = AccessibilityTrace.InteractionDigest(between: before, and: after)
        let metadata = AccessibilityTrace.ChangeFactMetadata(
            captureEdge: edge,
            interactionDigest: interactionDigest,
            transient: after.transition.transient,
            accessibilityNotifications: after.transition.accessibilityNotifications
        )
        let change = AccessibilityObservationChangeReducer.reduce(
            before: before,
            after: after
        )

        switch change {
        case .screenChanged:
            return projectScreenBoundaryFacts(
                before: before.interface,
                after: after.interface,
                metadata: metadata
            )
        case .elementChanged:
            return projectSameScreenFacts(
                before: before.interface,
                after: after.interface,
                metadata: metadata
            )
        }
    }

    private static func projectScreenBoundaryFacts(
        before: Interface,
        after: Interface,
        metadata: AccessibilityTrace.ChangeFactMetadata
    ) -> [AccessibilityTrace.ChangeFact] {
        let elementMetadata = metadata.filteringNotifications(isElementChangeNotification)
        let screenMetadata = metadata.filteringNotifications(isScreenChangeNotification)
        let disappearances = AccessibilityTrace.ChangeFact.elementsChanged(
            AccessibilityTrace.ElementsChangeFact(
                disappeared: before.graph.nodesInPathOrder.map {
                    AccessibilityTrace.InterfaceChangeNode(record: $0)
                },
                metadata: elementMetadata
            )
        )
        let marker = AccessibilityTrace.ChangeFact.screenChanged(AccessibilityTrace.ScreenChangeFact(
            metadata: screenMetadata
        ))
        let appearances = AccessibilityTrace.ChangeFact.elementsChanged(
            AccessibilityTrace.ElementsChangeFact(
                appeared: after.graph.nodesInPathOrder.map {
                    AccessibilityTrace.InterfaceChangeNode(record: $0)
                },
                metadata: elementMetadata
            )
        )
        return [disappearances, marker, appearances]
    }

    private static func projectSameScreenFacts(
        before: Interface,
        after: Interface,
        metadata: AccessibilityTrace.ChangeFactMetadata
    ) -> [AccessibilityTrace.ChangeFact] {
        let beforeRecords = before.projectedElementRecords.map(ElementDiffRecord.init)
        let afterRecords = after.projectedElementRecords.map(ElementDiffRecord.init)
        let edits = AccessibilityTraceElementDiff.projectElementEdits(
            beforeRecords: beforeRecords,
            afterRecords: afterRecords
        )
        let unpairedEdits = metadata.interactionDigest?.elementSetChanged == true
            ? AccessibilityTraceElementDiff.projectElementEditsWithoutMoveSuppression(
                beforeRecords: beforeRecords,
                afterRecords: afterRecords
            )
            : nil
        let effectiveEdits = edits.isEmpty ? (unpairedEdits ?? edits) : edits
        let disappearedContainers = containerNodesRemoved(from: before, after: after)
        let appearedContainers = containerNodesAdded(to: after, before: before)
        let fact = AccessibilityTrace.ElementsChangeFact(
            appeared: lifecycleNodes(
                in: after,
                elements: effectiveEdits.added,
                containers: appearedContainers
            ),
            disappeared: lifecycleNodes(
                in: before,
                elements: effectiveEdits.removed,
                containers: disappearedContainers
            ),
            updated: effectiveEdits.updated,
            metadata: metadata.filteringNotifications(isElementChangeNotification)
        )

        guard fact.hasLifecycleOrUpdateFacts
            || fact.isNotificationOnly
            || !metadata.transient.isEmpty
            || metadata.interactionDigest?.firstResponderChanged == true
        else { return [] }

        return [
            .elementsChanged(fact),
        ]
    }

    private static func isElementChangeNotification(_ evidence: AccessibilityNotificationEvidence) -> Bool {
        switch evidence.kind {
        case .elementChanged:
            true
        case .screenChanged, .announcement, .unknown:
            false
        }
    }

    private static func isScreenChangeNotification(_ evidence: AccessibilityNotificationEvidence) -> Bool {
        switch evidence.kind {
        case .screenChanged:
            true
        case .elementChanged, .announcement, .unknown:
            false
        }
    }

    private static func lifecycleNodes(
        in interface: Interface,
        elements: [HeistElement],
        containers: [InterfaceGraphContainerRecord]
    ) -> [AccessibilityTrace.InterfaceChangeNode] {
        var remainingElements = elements
        var remainingContainers = containers

        return interface.graph.nodesInPathOrder.compactMap { record in
            switch record.kind {
            case .element(let elementRecord):
                guard let index = remainingElements.firstIndex(of: elementRecord.projectedElement) else {
                    return nil
                }
                remainingElements.remove(at: index)
                return AccessibilityTrace.InterfaceChangeNode(record: record)

            case .container(let containerRecord):
                guard let index = remainingContainers.firstIndex(where: {
                    containerRecordsDescribeSameNode($0, containerRecord)
                }) else { return nil }
                remainingContainers.remove(at: index)
                return AccessibilityTrace.InterfaceChangeNode(record: record)
            }
        }
    }

    private static func containerNodesRemoved(
        from before: Interface,
        after: Interface
    ) -> [InterfaceGraphContainerRecord] {
        unmatchedContainerNodes(in: before, against: after)
    }

    private static func containerNodesAdded(
        to after: Interface,
        before: Interface
    ) -> [InterfaceGraphContainerRecord] {
        unmatchedContainerNodes(in: after, against: before)
    }

    private static func unmatchedContainerNodes(
        in source: Interface,
        against reference: Interface
    ) -> [InterfaceGraphContainerRecord] {
        var referenceContainers = reference.graph.nodesInPathOrder.compactMap(\.containerRecord)
        return source.graph.nodesInPathOrder.compactMap(\.containerRecord).filter { sourceRecord in
            guard let matchIndex = referenceContainers.firstIndex(where: {
                containerRecordsDescribeSameNode(sourceRecord, $0)
            }) else { return true }
            referenceContainers.remove(at: matchIndex)
            return false
        }
    }

    private static func containerRecordsDescribeSameNode(
        _ lhs: InterfaceGraphContainerRecord,
        _ rhs: InterfaceGraphContainerRecord
    ) -> Bool {
        if let leftIdentifier = lhs.container.identifier, !leftIdentifier.isEmpty,
           let rightIdentifier = rhs.container.identifier, !rightIdentifier.isEmpty {
            return leftIdentifier == rightIdentifier && lhs.container.type == rhs.container.type
        }
        if let leftName = lhs.annotation?.containerName,
           let rightName = rhs.annotation?.containerName {
            return leftName == rightName && lhs.container.type == rhs.container.type
        }
        return lhs.path == rhs.path && lhs.container == rhs.container
    }
}

private extension InterfaceGraphNodeRecord {
    var containerRecord: InterfaceGraphContainerRecord? {
        guard case .container(let record) = kind else { return nil }
        return record
    }
}
