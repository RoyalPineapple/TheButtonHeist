#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Interface Observation

/// One interface-tree state paired with the live UIKit evidence for its viewport.
/// Exploration may merge tree facts, but live evidence always comes from the
/// latest parser read and is never merged.
struct InterfaceObservation: Equatable {

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
            return try InterfaceObservation.build(
                tree: tree.viewportOnly,
                dispatchReferences: liveCapture.dispatchReferences
            )
        } catch {
            preconditionFailure("Viewport-only interface observation failed validation: \(error)")
        }
    }

    var orderedElements: [InterfaceTree.Element] {
        tree.orderedElements
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
