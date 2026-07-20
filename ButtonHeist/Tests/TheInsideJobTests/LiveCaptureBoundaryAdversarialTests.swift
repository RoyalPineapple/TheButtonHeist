#if canImport(UIKit)
import Testing
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import TheScore

@MainActor
@Suite("LiveCapture boundary adversarial invariants")
struct LiveCaptureBoundaryAdversarialTests {

    @Test func `new capture does not inherit prior live references`() throws {
        let heistId: HeistId = "save_button"
        let tree = makeTree(heistId: heistId)
        let object = NSObject()
        let captured = try InterfaceObservation.build(
            tree: tree,
            dispatchReferences: LiveCapture.DispatchReferences(
                elementRefs: [
                    heistId: LiveCapture.ElementRef(object: object, scrollView: nil)
                ]
            )
        )
        let later = try InterfaceObservation.build(tree: captured.tree)

        #expect(captured.liveCapture.object(for: heistId) === object)
        #expect(later.liveCapture.object(for: heistId) == nil)
        #expect(later.liveCapture.heistId(matching: object) == nil)
        #expect(later.tree == captured.tree)
    }

    @Test func `canonical observation rejects malformed hierarchy geometry`() {
        let element = AccessibilityElement.make(
            label: "Invalid",
            shape: .frame(AccessibilityRect(x: 0, y: 0, width: -1, height: 44))
        )
        let tree = makeTree(heistId: "invalid", element: element)

        #expect(throws: InterfaceGeometryAdmissionError.self) {
            try InterfaceObservation.build(tree: tree)
        }
    }

    private func makeTree(
        heistId: HeistId,
        element: AccessibilityElement = .make(label: "Save", traits: .button)
    ) -> InterfaceTree {
        let path = TreePath([0])
        let entry = InterfaceTree.Element(
            heistId: heistId,
            path: path,
            scrollMembership: nil,
            element: element
        )
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [path: heistId]
        )
        return InterfaceTree(
            elements: [heistId: entry],
            viewportCapture: snapshot
        )
    }
}

#endif
