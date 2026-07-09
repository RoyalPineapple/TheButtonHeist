import ThePlans
import Foundation
import AccessibilitySnapshotModel

// MARK: - Accessibility Trace Diff Facades

public extension AccessibilityTrace.Delta {

    /// Compare two full accessibility captures and emit the compact delta.
    ///
    /// Captures remain trace truth. This facade preserves the public entry point
    /// while delegating the derived diff to `AccessibilityTraceDiff`.
    static func between(
        _ before: AccessibilityTrace.Capture,
        _ after: AccessibilityTrace.Capture,
        projection: AccessibilityTrace.DeltaProjection = .semantic
    ) -> AccessibilityTrace.Delta {
        AccessibilityTraceDiff.projectDelta(between: before, and: after, projection: projection)
    }
}

public extension ElementEdits {

    /// Compare two single-element hierarchies.
    static func between(_ before: HeistElement, _ after: HeistElement) -> ElementEdits {
        AccessibilityTraceElementDiff.projectElementEdits(beforeElements: [before], afterElements: [after])
    }

    /// Compare two flat root element lists.
    static func between(_ before: [HeistElement], _ after: [HeistElement]) -> ElementEdits {
        AccessibilityTraceElementDiff.projectElementEdits(beforeElements: before, afterElements: after)
    }

    /// Compare two full interfaces.
    static func between(_ before: Interface, _ after: Interface) -> ElementEdits {
        AccessibilityTraceElementDiff.projectElementEdits(
            beforeRecords: before.projectedElementRecords.map(ElementDiffRecord.init),
            afterRecords: after.projectedElementRecords.map(ElementDiffRecord.init)
        )
    }

    static func between(
        beforeElements: [HeistElement],
        afterElements: [HeistElement]
    ) -> ElementEdits {
        AccessibilityTraceElementDiff.projectElementEdits(
            beforeElements: beforeElements,
            afterElements: afterElements
        )
    }

}
