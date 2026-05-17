#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Interface Diff

extension TheStash {

    /// Diff two element snapshots and emit a compact `AccessibilityTrace.Delta`.
    /// Pure transform — no stored state.
    @MainActor enum InterfaceDiff { // swiftlint:disable:this agent_main_actor_value_type

    // MARK: - Entry Point

    /// Compare two element snapshots and return a compact delta.
    static func computeDelta(
        before: [ScreenElement],
        after: [ScreenElement],
        beforeTree: [InterfaceNode]? = nil,
        beforeTreeHash: Int? = nil,
        afterTree: [InterfaceNode],
        isScreenChange: Bool
    ) -> AccessibilityTrace.Delta {
        let afterInterface = Interface(timestamp: Date(), tree: afterTree)
        if isScreenChange {
            return .screenChanged(AccessibilityTrace.ScreenChanged(
                elementCount: after.count,
                newInterface: afterInterface
            ))
        }

        // Fast no-change check on internal types keeps geometry-only churn out
        // of the wire diff unless the canonical tree itself changed.
        if before.count == after.count, zip(before, after).allSatisfy({ before, after in
            before.heistId == after.heistId && before.element == after.element
        }) {
            guard let beforeTreeHash, beforeTreeHash != afterTree.hashValue else {
                return .noChange(AccessibilityTrace.NoChange(elementCount: after.count))
            }
            guard let beforeTree else {
                return .screenChanged(AccessibilityTrace.ScreenChanged(
                    elementCount: after.count,
                    newInterface: afterInterface
                ))
            }
            let treeEdits = ElementEdits.between(beforeTree: beforeTree, afterTree: afterTree)
            if treeEdits.isEmpty {
                return .noChange(AccessibilityTrace.NoChange(elementCount: after.count))
            }
            return .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: after.count,
                edits: treeEdits
            ))
        }

        let beforeWire = WireConversion.toWire(before)
        let afterWire = WireConversion.toWire(after)
        let elementEdits = ElementEdits.between(beforeElements: beforeWire, afterElements: afterWire)
        guard let beforeTree else {
            return makeDelta(edits: elementEdits, elementCount: after.count)
        }

        let treeEdits = ElementEdits.between(beforeTree: beforeTree, afterTree: afterTree)
        return makeDelta(
            edits: ElementEdits(
                added: elementEdits.added,
                removed: elementEdits.removed,
                updated: elementEdits.updated,
                treeInserted: treeEdits.treeInserted,
                treeRemoved: treeEdits.treeRemoved,
                treeMoved: treeEdits.treeMoved
            ),
            elementCount: after.count
        )
    }

    /// Compare two accessibility captures and return a compact delta.
    static func computeDelta(
        before: AccessibilityTrace.Capture,
        after: AccessibilityTrace.Capture,
        isScreenChange: Bool
    ) -> AccessibilityTrace.Delta {
        AccessibilityTrace.Delta.between(before, after, isScreenChange: isScreenChange)
    }

    private static func makeDelta(edits: ElementEdits, elementCount: Int) -> AccessibilityTrace.Delta {
        if edits.isEmpty {
            return .noChange(AccessibilityTrace.NoChange(elementCount: elementCount))
        }
        return .elementsChanged(AccessibilityTrace.ElementsChanged(
            elementCount: elementCount,
            edits: edits
        ))
    }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
