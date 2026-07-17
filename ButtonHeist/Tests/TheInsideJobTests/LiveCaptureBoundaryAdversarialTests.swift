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

    private func makeTree(heistId: HeistId) -> InterfaceTree {
        let element = AccessibilityElement.make(label: "Save", traits: .button)
        let path = TreePath([0])
        let entry = InterfaceTree.Element(
            heistId: heistId,
            path: path,
            scrollMembership: nil,
            element: element
        )
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)],
            elementsByPath: [path: entry]
        )
        return InterfaceTree(
            elements: [heistId: entry],
            viewportCapture: snapshot
        )
    }
}

#endif
