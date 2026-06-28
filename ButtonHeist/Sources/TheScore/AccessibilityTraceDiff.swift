import ThePlans
import Foundation
import AccessibilitySnapshotModel

/// Computes the compact delta between two accessibility captures. Captures stay
/// the durable truth; this derives the diff fact on demand.
enum AccessibilityTraceDiff {

    static func projectDelta(
        between before: AccessibilityTrace.Capture,
        and after: AccessibilityTrace.Capture
    ) -> AccessibilityTrace.Delta {
        let edge = AccessibilityTrace.CaptureEdge(before: before, after: after)
        let interactionDigest = AccessibilityTrace.InteractionDigest(between: before, and: after)
        let screenChanged = before.context.screenId != after.context.screenId
            || after.transition.screenChangeReason != nil

        if !screenChanged, before.hash == after.hash {
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
            captureEdge: edge,
            interactionDigest: interactionDigest,
            transient: after.transition.transient
        )

        guard before.context != after.context else { return interfaceDelta }
        if case .noChange = interfaceDelta {
            return .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: after.interface.projectedElements.count,
                edits: ElementEdits(),
                captureEdge: edge,
                interactionDigest: interactionDigest,
                transient: after.transition.transient
            ))
        }
        return interfaceDelta
    }

    private static func projectInterfaceDelta(
        _ before: Interface,
        _ after: Interface,
        isScreenChange: Bool,
        captureEdge: AccessibilityTrace.CaptureEdge,
        interactionDigest: AccessibilityTrace.InteractionDigest,
        transient: [HeistElement]
    ) -> AccessibilityTrace.Delta {
        let beforeElements = before.projectedElements
        let afterElements = after.projectedElements

        if isScreenChange {
            return .screenChanged(AccessibilityTrace.ScreenChanged(
                elementCount: afterElements.count,
                captureEdge: captureEdge,
                newInterface: after,
                interactionDigest: interactionDigest,
                transient: transient
            ))
        }

        if AccessibilityTrace.Capture.hash(before) == AccessibilityTrace.Capture.hash(after) {
            return .noChange(AccessibilityTrace.NoChange(
                elementCount: afterElements.count,
                captureEdge: captureEdge,
                interactionDigest: interactionDigest,
                transient: transient
            ))
        }

        let edits = AccessibilityTraceElementDiff.projectElementEdits(
            beforeElements: beforeElements,
            afterElements: afterElements
        )
        let unpairedEdits = interactionDigest.elementSetChanged
            ? AccessibilityTraceElementDiff.projectElementEditsWithoutMoveSuppression(
                beforeElements: beforeElements,
                afterElements: afterElements
            )
            : nil
        return projectElementDelta(
            edits: edits,
            unpairedEdits: unpairedEdits,
            elementCount: afterElements.count,
            captureEdge: captureEdge,
            interactionDigest: interactionDigest,
            transient: transient
        )
    }

    private static func projectElementDelta(
        edits: ElementEdits,
        unpairedEdits: ElementEdits?,
        elementCount: Int,
        captureEdge: AccessibilityTrace.CaptureEdge,
        interactionDigest: AccessibilityTrace.InteractionDigest,
        transient: [HeistElement]
    ) -> AccessibilityTrace.Delta {
        if edits.isEmpty {
            if let unpairedEdits, !unpairedEdits.isEmpty {
                return .elementsChanged(AccessibilityTrace.ElementsChanged(
                    elementCount: elementCount,
                    edits: unpairedEdits,
                    captureEdge: captureEdge,
                    interactionDigest: interactionDigest,
                    transient: transient
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
            transient: transient
        ))
    }
}
