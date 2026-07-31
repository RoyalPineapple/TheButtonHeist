#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Interface Observation

/// One interface-tree state paired with current weak UIKit dispatch references.
/// Exploration may merge tree facts, but dispatch references always come from
/// the latest parser read and are never merged.
struct InterfaceObservation {

    let tree: InterfaceTree
    let liveCapture: LiveCapture

    static var empty: InterfaceObservation {
        do {
            return try InterfaceObservation.build(tree: .empty)
        } catch {
            preconditionFailure("Empty interface observation failed validation: \(error)")
        }
    }

    /// The production construction boundary for semantic state and its live dispatch evidence.
    static func build(
        tree: InterfaceTree,
        dispatchReferences: LiveCapture.DispatchReferences = .empty
    ) throws -> InterfaceObservation {
        InterfaceObservation(
            validatedTree: tree,
            liveCapture: try LiveCapture.build(
                validating: tree,
                dispatchReferences: dispatchReferences
            )
        )
    }

    private init(
        validatedTree: InterfaceTree,
        liveCapture: LiveCapture
    ) {
        tree = validatedTree
        self.liveCapture = liveCapture
    }

    var viewportOnly: InterfaceObservation {
        removingElements(withIds: tree.elementIDs.subtracting(tree.viewportElementIDs))
    }

    func replacingTreeWithCurrentCapture(_ tree: InterfaceTree) throws -> InterfaceObservation {
        try Self.build(
            tree: tree,
            dispatchReferences: liveCapture.dispatchReferences
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
