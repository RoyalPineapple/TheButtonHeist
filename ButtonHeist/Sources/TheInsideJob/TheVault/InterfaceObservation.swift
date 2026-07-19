#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Interface Observation

struct InterfaceCaptureID: Equatable, Hashable, Sendable {
    fileprivate let id = UUID()
}

/// One interface-tree state paired with the live UIKit evidence for its viewport.
/// Exploration may merge tree facts, but live evidence always comes from the
/// latest parser read and is never merged.
struct InterfaceObservation {

    let tree: InterfaceTree
    let liveCapture: LiveCapture
    let captureID: InterfaceCaptureID

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
        try build(
            tree: tree,
            dispatchReferences: dispatchReferences,
            captureID: InterfaceCaptureID()
        )
    }

    static func build(
        tree: InterfaceTree,
        dispatchReferences: LiveCapture.DispatchReferences,
        captureID: InterfaceCaptureID
    ) throws -> InterfaceObservation {
        InterfaceObservation(
            validatedTree: tree,
            liveCapture: try LiveCapture.build(
                validating: tree,
                dispatchReferences: dispatchReferences
            ),
            captureID: captureID
        )
    }

    private init(
        validatedTree: InterfaceTree,
        liveCapture: LiveCapture,
        captureID: InterfaceCaptureID
    ) {
        tree = validatedTree
        self.liveCapture = liveCapture
        self.captureID = captureID
    }

    var viewportOnly: InterfaceObservation {
        removingElements(withIds: tree.elementIDs.subtracting(tree.viewportElementIDs))
    }

    func replacingTreeWithCurrentCapture(_ tree: InterfaceTree) throws -> InterfaceObservation {
        try Self.build(
            tree: tree,
            dispatchReferences: liveCapture.dispatchReferences,
            captureID: captureID
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
