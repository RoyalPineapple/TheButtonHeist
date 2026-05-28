import Foundation
import AccessibilitySnapshotModel

// MARK: - Accessibility Trace Diff Facades

public extension AccessibilityTrace.Delta {

    /// Compare two full accessibility captures and emit the compact delta projection.
    ///
    /// Captures remain trace truth. This facade preserves the public entry point
    /// while delegating all derived diff behavior to projection-specific owners.
    static func between(
        _ before: AccessibilityTrace.Capture,
        _ after: AccessibilityTrace.Capture
    ) -> AccessibilityTrace.Delta {
        AccessibilityTraceDiffProjection.projectDelta(between: before, and: after)
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
        let elementEdits = AccessibilityTraceElementDiff.projectElementEdits(
            beforeElements: before.elements,
            afterElements: after.elements
        )
        let treeEdits = betweenTrees(before: before, after: after)
        return ElementEdits(
            added: elementEdits.added,
            removed: elementEdits.removed,
            updated: elementEdits.updated,
            treeInserted: treeEdits.treeInserted,
            treeRemoved: treeEdits.treeRemoved,
            treeMoved: treeEdits.treeMoved
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

    static func betweenTrees(before: Interface, after: Interface) -> ElementEdits {
        AccessibilityTraceTreeDiff.projectTreeEdits(before: before, after: after)
    }
}
