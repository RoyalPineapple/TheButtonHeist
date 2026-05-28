import Foundation
import AccessibilitySnapshotModel

enum AccessibilityTraceDiffProjection {

    static func projectDelta(
        between before: AccessibilityTrace.Capture,
        and after: AccessibilityTrace.Capture
    ) -> AccessibilityTrace.Delta {
        let edge = AccessibilityTrace.CaptureEdge(before: before, after: after)
        let screenChanged = before.context.screenId != after.context.screenId
            || after.transition.screenChangeReason != nil

        if !screenChanged, before.hash == after.hash {
            return .noChange(AccessibilityTrace.NoChange(
                elementCount: after.interface.elements.count,
                captureEdge: edge,
                transient: after.transition.transient
            ))
        }

        let interfaceDelta = projectInterfaceDelta(
            before.interface,
            after.interface,
            isScreenChange: screenChanged
        )
        .withCaptureEdge(edge)
        .withTransient(after.transition.transient)

        guard before.context != after.context else { return interfaceDelta }
        if case .noChange = interfaceDelta {
            return .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: after.interface.elements.count,
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
        isScreenChange: Bool
    ) -> AccessibilityTrace.Delta {
        let afterElements = after.elements

        if isScreenChange {
            return .screenChanged(AccessibilityTrace.ScreenChanged(
                elementCount: afterElements.count,
                newInterface: after
            ))
        }

        if AccessibilityTrace.Capture.hash(before) == AccessibilityTrace.Capture.hash(after) {
            return .noChange(AccessibilityTrace.NoChange(elementCount: afterElements.count))
        }

        return projectElementDelta(
            edits: ElementEdits.between(before, after),
            elementCount: afterElements.count
        )
    }

    private static func projectElementDelta(
        edits: ElementEdits,
        elementCount: Int
    ) -> AccessibilityTrace.Delta {
        if edits.isEmpty {
            return .noChange(AccessibilityTrace.NoChange(elementCount: elementCount))
        }
        return .elementsChanged(AccessibilityTrace.ElementsChanged(elementCount: elementCount, edits: edits))
    }
}
