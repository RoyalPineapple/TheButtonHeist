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
            accessibilityNotifications: after.transition.accessibilityNotifications
        )
        let change = AccessibilityObservationChangeReducer.reduce(
            between: before,
            and: after
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

    /// A screen boundary is three facts in causal order: the old screen's nodes
    /// depart, the screen identity moves, the new screen's nodes arrive.
    ///
    /// There is no element identity across a replacement, so nothing is diffed
    /// and nothing is paired. Every node in `before` departed and every node in
    /// `after` arrived — a similarly shaped control on the new screen is a new
    /// object, not the old one persisting.
    ///
    /// Order carries the meaning. Two-legged steps do not evaluate their after
    /// leg until the before leg is satisfied, so `disappeared(X)` reads the
    /// departure tick and `appeared(X)` reads the arrival tick; fusing the three
    /// into one fact would offer both legs a single reading and let either match
    /// on the wrong side of the stitch.
    private static func projectScreenBoundaryFacts(
        before: Interface,
        after: Interface,
        metadata: AccessibilityTrace.ChangeFactMetadata
    ) -> [AccessibilityTrace.ChangeFact] {
        let elementMetadata = metadata.filteringNotifications(isElementChangeNotification)
        let departure = AccessibilityTrace.ElementsChangeFact(
            disappeared: allNodes(in: before),
            metadata: elementMetadata
        )
        let arrival = AccessibilityTrace.ElementsChangeFact(
            appeared: allNodes(in: after),
            metadata: elementMetadata
        )
        let screen = AccessibilityTrace.ScreenChangeFact(
            metadata: metadata.filteringNotifications(isScreenChangeNotification)
        )

        // An empty graph on either side has nothing to depart or arrive, so that
        // leg is omitted rather than delivered as a tick carrying no evidence.
        return [
            departure.hasLifecycleOrUpdateFacts ? .elementsChanged(departure) : nil,
            .screenChanged(screen),
            arrival.hasLifecycleOrUpdateFacts ? .elementsChanged(arrival) : nil,
        ].compactMap(\.self)
    }

    /// Every node in the graph, in path order, as lifecycle evidence.
    private static func allNodes(
        in interface: Interface
    ) -> [AccessibilityTrace.InterfaceChangeNode] {
        interface.graph.nodesInPathOrder.map(AccessibilityTrace.InterfaceChangeNode.init(record:))
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
