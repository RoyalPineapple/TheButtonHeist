#if canImport(UIKit)
import Testing
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import TheScore

@MainActor
@Suite("LiveCapture boundary adversarial invariants")
struct LiveCaptureBoundaryAdversarialTests {

    @Test func `deallocated reference cannot equal later missing evidence`() throws {
        let heistId: HeistId = "save_button"
        let tree = makeTree(heistId: heistId)
        var object: NSObject? = NSObject()
        weak var releasedObject: NSObject? = object
        let objectIdentifier = try #require(object.map(ObjectIdentifier.init))
        let captured = try InterfaceObservation.build(
            tree: tree,
            dispatchReferences: LiveCapture.DispatchReferences(
                elementRefs: [
                    heistId: LiveCapture.ElementRef(object: object, scrollView: nil)
                ]
            )
        ).liveCapture
        let later = try InterfaceObservation.build(
            tree: tree,
            dispatchReferences: LiveCapture.DispatchReferences(
                elementRefs: [
                    heistId: LiveCapture.ElementRef(object: nil, scrollView: nil)
                ]
            )
        ).liveCapture

        #expect(captured.snapshot == later.snapshot)
        #expect(captured != later)
        object = nil

        #expect(releasedObject == nil)
        #expect(captured.object(for: heistId) == nil)
        #expect(captured.heistId(matchingObjectIdentifier: objectIdentifier) == nil)
        #expect(captured != later)
    }

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

    @Test func `weak dispatch reference equality is stable after deallocation`() {
        var firstObject: NSObject? = NSObject()
        var secondObject: NSObject? = NSObject()
        var firstScrollView: UIScrollView? = UIScrollView()
        var secondScrollView: UIScrollView? = UIScrollView()
        let firstElementRef = LiveCapture.ElementRef(
            object: firstObject,
            scrollView: firstScrollView
        )
        let secondElementRef = LiveCapture.ElementRef(
            object: secondObject,
            scrollView: secondScrollView
        )
        let firstContainerRef = LiveCapture.ContainerRef(object: firstObject)
        let secondContainerRef = LiveCapture.ContainerRef(object: secondObject)
        let firstScrollableRef = LiveCapture.ScrollableViewRef(view: firstScrollView)
        let secondScrollableRef = LiveCapture.ScrollableViewRef(view: secondScrollView)

        #expect(firstElementRef != secondElementRef)
        #expect(firstContainerRef != secondContainerRef)
        #expect(firstScrollableRef != secondScrollableRef)
        firstObject = nil
        secondObject = nil
        firstScrollView = nil
        secondScrollView = nil

        #expect(firstElementRef != secondElementRef)
        #expect(firstContainerRef != secondContainerRef)
        #expect(firstScrollableRef != secondScrollableRef)
    }

    private func makeTree(heistId: HeistId) -> InterfaceTree {
        let element = AccessibilityElement.make(label: "Save", traits: .button)
        let path = TreePath([0])
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [path: heistId]
        )
        return InterfaceTree(
            elements: [
                heistId: InterfaceTree.Element(
                    heistId: heistId,
                    path: path,
                    scrollMembership: nil,
                    element: element
                )
            ],
            viewportCapture: snapshot
        )
    }
}

#endif
