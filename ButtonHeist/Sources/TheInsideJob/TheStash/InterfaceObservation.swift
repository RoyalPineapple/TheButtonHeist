#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Interface Observation

struct InterfaceCaptureToken: Equatable, Hashable, Sendable {
    fileprivate let id = UUID()
}

/// One interface-tree state paired with the live UIKit evidence for its viewport.
/// Exploration may merge tree facts, but live evidence always comes from the
/// latest parser read and is never merged.
struct InterfaceObservation {

    let tree: InterfaceTree
    let liveCapture: LiveCapture
    let captureToken: InterfaceCaptureToken

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
            captureToken: InterfaceCaptureToken()
        )
    }

    private static func build(
        tree: InterfaceTree,
        dispatchReferences: LiveCapture.DispatchReferences,
        captureToken: InterfaceCaptureToken
    ) throws -> InterfaceObservation {
        InterfaceObservation(
            validatedTree: tree,
            liveCapture: try LiveCapture.build(
                validating: tree,
                dispatchReferences: dispatchReferences
            ),
            captureToken: captureToken
        )
    }

    private init(
        validatedTree: InterfaceTree,
        liveCapture: LiveCapture,
        captureToken: InterfaceCaptureToken
    ) {
        tree = validatedTree
        self.liveCapture = liveCapture
        self.captureToken = captureToken
    }

    // MARK: - Derived Properties

    var summaryElement: AccessibilityElement? {
        tree.summaryElement
    }

    var name: String? {
        tree.name
    }

    var id: String? {
        tree.id
    }

    var elementIDs: Set<HeistId> {
        tree.elementIDs
    }

    var elementCount: Int {
        tree.elementCount
    }

    var viewportElementIDs: Set<HeistId> {
        tree.viewportElementIDs
    }

    var interfaceHash: String {
        tree.interfaceHash
    }

    func findElement(heistId: HeistId) -> InterfaceTree.Element? {
        tree.findElement(heistId: heistId)
    }

    var orderedContainers: [InterfaceTree.Container] {
        tree.orderedContainers
    }

    var viewportOnly: InterfaceObservation {
        do {
            return try Self.build(
                tree: tree.viewportOnly,
                dispatchReferences: liveCapture.dispatchReferences,
                captureToken: captureToken
            )
        } catch {
            preconditionFailure("Viewport-only interface observation failed validation: \(error)")
        }
    }

    func replacingTreeWithCurrentCapture(_ tree: InterfaceTree) throws -> InterfaceObservation {
        try Self.build(
            tree: tree,
            dispatchReferences: liveCapture.dispatchReferences,
            captureToken: captureToken
        )
    }

    var orderedElements: [InterfaceTree.Element] {
        tree.orderedElements
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
