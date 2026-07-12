import ThePlans
import Foundation
import AccessibilitySnapshotModel

/// Computes the compact delta between two accessibility captures. Captures stay
/// the durable truth; this derives the diff fact on demand.
enum AccessibilityTraceDiff {

    static func projectDelta(
        between before: AccessibilityTrace.Capture,
        and after: AccessibilityTrace.Capture,
        projection: AccessibilityTrace.DeltaProjection = .semantic
    ) -> AccessibilityTrace.Delta {
        let edge = AccessibilityTrace.CaptureEdge(before: before, after: after)
        let interactionDigest = AccessibilityTrace.InteractionDigest(between: before, and: after)
        let change = AccessibilityObservationChangeReducer.reduce(
            before: before,
            after: after,
            projection: projection
        )
        let screenChanged = change.isScreenChange

        if !change.isChange {
            return .noChange(AccessibilityTrace.NoChange(
                elementCount: after.interface.projectedElements.count,
                captureEdge: edge,
                interactionDigest: interactionDigest,
                transient: after.transition.transient
            ))
        }

        let interfaceDelta = projectInterfaceDelta(
            before.interface,
            after.interface,
            isScreenChange: screenChanged,
            projection: projection,
            captureEdge: edge,
            interactionDigest: interactionDigest,
            transition: after.transition
        )

        guard before.context != after.context else { return interfaceDelta }
        if case .noChange = interfaceDelta {
            return .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: after.interface.projectedElements.count,
                edits: ElementEdits(),
                captureEdge: edge,
                interactionDigest: interactionDigest,
                transient: after.transition.transient,
                accessibilityNotifications: after.transition.accessibilityNotifications.filter {
                    $0.kind.isElementChangeEvidence
                }
            ))
        }
        return interfaceDelta
    }

    private static func projectInterfaceDelta(
        _ before: Interface,
        _ after: Interface,
        isScreenChange: Bool,
        projection: AccessibilityTrace.DeltaProjection,
        captureEdge: AccessibilityTrace.CaptureEdge,
        interactionDigest: AccessibilityTrace.InteractionDigest,
        transition: AccessibilityTrace.Transition
    ) -> AccessibilityTrace.Delta {
        let beforeRecords = before.projectedElementRecords.map(ElementDiffRecord.init)
        let afterRecords = after.projectedElementRecords.map(ElementDiffRecord.init)
        let afterElements = afterRecords.map(\.element)

        if isScreenChange {
            return .screenChanged(AccessibilityTrace.ScreenChanged(
                elementCount: afterElements.count,
                captureEdge: captureEdge,
                newInterface: after,
                interactionDigest: interactionDigest,
                transient: transition.transient,
                accessibilityNotifications: transition.accessibilityNotifications.filter {
                    $0.kind == .screenChanged
                }
            ))
        }

        let edits = AccessibilityTraceElementDiff.projectElementEdits(
            beforeRecords: beforeRecords,
            afterRecords: afterRecords,
            projection: projection
        )
        let unpairedEdits = interactionDigest.elementSetChanged
            ? AccessibilityTraceElementDiff.projectElementEditsWithoutMoveSuppression(
                beforeRecords: beforeRecords,
                afterRecords: afterRecords,
                projection: projection
            )
            : nil
        return projectElementDelta(
            edits: edits,
            unpairedEdits: unpairedEdits,
            elementCount: afterElements.count,
            captureEdge: captureEdge,
            interactionDigest: interactionDigest,
            transient: transition.transient,
            accessibilityNotifications: transition.accessibilityNotifications.filter {
                $0.kind.isElementChangeEvidence
            }
        )
    }

    private static func projectElementDelta(
        edits: ElementEdits,
        unpairedEdits: ElementEdits?,
        elementCount: Int,
        captureEdge: AccessibilityTrace.CaptureEdge,
        interactionDigest: AccessibilityTrace.InteractionDigest,
        transient: [HeistElement],
        accessibilityNotifications: [AccessibilityNotificationEvidence]
    ) -> AccessibilityTrace.Delta {
        if edits.isEmpty {
            if let unpairedEdits, !unpairedEdits.isEmpty {
                return .elementsChanged(AccessibilityTrace.ElementsChanged(
                    elementCount: elementCount,
                    edits: unpairedEdits,
                    captureEdge: captureEdge,
                    interactionDigest: interactionDigest,
                    transient: transient,
                    accessibilityNotifications: accessibilityNotifications
                ))
            }
            return .noChange(AccessibilityTrace.NoChange(
                elementCount: elementCount,
                captureEdge: captureEdge,
                interactionDigest: interactionDigest,
                transient: transient
            ))
        }
        return .elementsChanged(AccessibilityTrace.ElementsChanged(
            elementCount: elementCount,
            edits: edits,
            captureEdge: captureEdge,
            interactionDigest: interactionDigest,
            transient: transient,
            accessibilityNotifications: accessibilityNotifications
        ))
    }
}
