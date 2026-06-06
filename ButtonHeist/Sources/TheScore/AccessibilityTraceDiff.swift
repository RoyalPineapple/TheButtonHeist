import ThePlans
import Foundation
import AccessibilitySnapshotModel

/// Computes the compact delta between two accessibility captures. Captures stay
/// the durable truth; this derives the diff fact on demand.
enum AccessibilityTraceDiff {

    static func projectDelta(
        between before: AccessibilityTrace.Capture,
        and after: AccessibilityTrace.Capture,
        includeGeometry: Bool = true
    ) -> AccessibilityTrace.Delta {
        let edge = AccessibilityTrace.CaptureEdge(before: before, after: after)
        let screenChanged = before.context.screenId != after.context.screenId
            || after.transition.screenChangeReason != nil

        if !screenChanged, before.hash == after.hash {
            return .noChange(AccessibilityTrace.NoChange(
                elementCount: after.interface.projectedElements.count,
                captureEdge: edge,
                transient: after.transition.transient
            ))
        }

        let interfaceDelta = projectInterfaceDelta(
            before.interface,
            after.interface,
            isScreenChange: screenChanged,
            captureEdge: edge,
            transient: after.transition.transient,
            includeGeometry: includeGeometry
        )

        guard before.context != after.context else { return interfaceDelta }
        if case .noChange = interfaceDelta {
            return .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: after.interface.projectedElements.count,
                edits: ElementEdits(),
                captureEdge: edge,
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
        transient: [HeistElement],
        includeGeometry: Bool
    ) -> AccessibilityTrace.Delta {
        let afterElements = after.projectedElements

        if isScreenChange {
            return .screenChanged(AccessibilityTrace.ScreenChanged(
                elementCount: afterElements.count,
                captureEdge: captureEdge,
                newInterface: after,
                transient: transient
            ))
        }

        if AccessibilityTrace.Capture.hash(before) == AccessibilityTrace.Capture.hash(after) {
            return .noChange(AccessibilityTrace.NoChange(
                elementCount: afterElements.count,
                captureEdge: captureEdge,
                transient: transient
            ))
        }

        return projectElementDelta(
            edits: ElementEdits.between(before, after, includeGeometry: includeGeometry),
            elementCount: afterElements.count,
            captureEdge: captureEdge,
            transient: transient
        )
    }

    private static func projectElementDelta(
        edits: ElementEdits,
        elementCount: Int,
        captureEdge: AccessibilityTrace.CaptureEdge,
        transient: [HeistElement]
    ) -> AccessibilityTrace.Delta {
        if edits.isEmpty {
            return .noChange(AccessibilityTrace.NoChange(
                elementCount: elementCount,
                captureEdge: captureEdge,
                transient: transient
            ))
        }
        return .elementsChanged(AccessibilityTrace.ElementsChanged(
            elementCount: elementCount,
            edits: edits,
            captureEdge: captureEdge,
            transient: transient
        ))
    }
}
