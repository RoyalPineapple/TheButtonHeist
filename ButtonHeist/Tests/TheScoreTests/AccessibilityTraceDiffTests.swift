import XCTest
import ThePlans
import AccessibilitySnapshotModel
@testable import TheScore

private extension AccessibilityTrace.Delta {
    var testElementEdits: ElementEdits {
        if case .elementsChanged(let payload) = self { return payload.edits }
        return ElementEdits()
    }

    var testTransient: [HeistElement] {
        switch self {
        case .noChange(let payload):
            return payload.transient
        case .elementsChanged(let payload):
            return payload.transient
        case .screenChanged(let payload):
            return payload.transient
        }
    }

    var testCaptureEdge: AccessibilityTrace.CaptureEdge? {
        switch self {
        case .noChange(let payload):
            return payload.captureEdge
        case .elementsChanged(let payload):
            return payload.captureEdge
        case .screenChanged(let payload):
            return payload.captureEdge
        }
    }
}

final class AccessibilityTraceDiffTests: XCTestCase {

    func testElementDiffIsSingleElementHierarchyDiff() {
        let before = makeElement(label: "Total", value: "$5.00", traits: [.staticText])
        let after = makeElement(label: "Total", value: "$7.00", traits: [.staticText])
        let beforeInterface = makeTestInterface(elements: [before])
        let afterInterface = makeTestInterface(elements: [after])

        XCTAssertEqual(
            ElementEdits.between(before, after),
            ElementEdits.between(beforeInterface, afterInterface)
        )
        let delta = captureDelta(before: beforeInterface, after: afterInterface)
        XCTAssertEqual(delta.testElementEdits, ElementEdits.between(before, after))
    }

    func testNodeDiffIsTreeDiff() {
        let before = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "section", children: [
                testElement(makeElement(label: "Menu", traits: [.header])),
            ]),
        ])
        let after = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "section", children: [
                testElement(makeElement(label: "Checkout", traits: [.header])),
            ]),
        ])

        let edits = ElementEdits.between(before, after)
        let delta = captureDelta(before: before, after: after)
        XCTAssertEqual(delta.testElementEdits, edits)
    }

    func testFunctionalElementMoveDoesNotReportRemoveInsertChurn() {
        let before = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "list", children: [
                testElement(makeElement(label: "Pasta", traits: [.button])),
                testElement(makeElement(label: "Sauce", traits: [.button])),
            ]),
        ])
        let after = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "list", children: [
                testElement(makeElement(label: "Sauce", traits: [.button])),
                testElement(makeElement(label: "Pasta", traits: [.button])),
            ]),
        ])

        let elementEdits = ElementEdits.between(before, after)

        XCTAssertTrue(elementEdits.added.isEmpty)
        XCTAssertTrue(elementEdits.removed.isEmpty)
    }

    func testTreeInterfaceAndCaptureDiffsShareTheSameEdits() {
        let beforeInterface = makeTestInterface(
            nodes: [
                testContainer(makeContainer(), containerName: "main", children: [
                    testElement(makeElement(label: "Menu", traits: [.header])),
                    testElement(makeElement(label: "Total", value: "$5.00", traits: [.staticText])),
                ]),
            ],
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let afterInterface = makeTestInterface(
            nodes: [
                testContainer(makeContainer(), containerName: "main", children: [
                    testElement(makeElement(label: "Menu", traits: [.header])),
                    testElement(makeElement(label: "Total", value: "$7.00", traits: [.staticText])),
                ]),
            ],
            timestamp: Date(timeIntervalSince1970: 2)
        )
        let beforeCapture = AccessibilityTrace.Capture(sequence: 1, interface: beforeInterface)
        let afterCapture = AccessibilityTrace.Capture(sequence: 2, interface: afterInterface, parentHash: beforeCapture.hash)

        XCTAssertEqual(
            ElementEdits.between(beforeInterface.projectedElements, afterInterface.projectedElements).updated,
            ElementEdits.between(beforeInterface, afterInterface).updated
        )
        let delta = AccessibilityTrace.Delta.between(beforeCapture, afterCapture)
        XCTAssertEqual(delta.testElementEdits, ElementEdits.between(beforeInterface, afterInterface))
    }

    func testCaptureBackedNoChangeDeltaCarriesSourceEdgeAndDerivesFromTrace() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface())
        let after = AccessibilityTrace.Capture(sequence: 2, interface: makeInterface(), parentHash: before.hash)
        let trace = AccessibilityTrace(captures: [before, after])

        let delta = AccessibilityTrace.Delta.between(before, after)

        guard case .noChange = delta else {
            return XCTFail("Expected noChange, got \(delta)")
        }
        try assertDeltaDerivesFromCaptureEdge(delta, trace: trace)
    }

    func testCaptureBackedElementsChangedDeltaCarriesSourceEdgeAndDerivesFromTrace() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash
        )
        let trace = AccessibilityTrace(captures: [before, after])

        let delta = AccessibilityTrace.Delta.between(before, after)

        guard case .elementsChanged = delta else {
            return XCTFail("Expected elementsChanged, got \(delta)")
        }
        try assertDeltaDerivesFromCaptureEdge(delta, trace: trace)
    }

    func testCaptureBackedScreenChangedDeltaCarriesSourceEdgeAndDerivesFromTransition() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )
        let trace = AccessibilityTrace(captures: [before, after])

        let delta = AccessibilityTrace.Delta.between(before, after)

        guard case .screenChanged(let payload) = delta else {
            return XCTFail("Expected screenChanged, got \(delta)")
        }
        XCTAssertEqual(payload.newInterface, after.interface)
        try assertDeltaDerivesFromCaptureEdge(delta, trace: trace)
    }

    func testTransitionTransientLivesOnCaptureEdgeAndProjectsToCompactDeltaField() throws {
        let transient = makeElement(label: "Loading", traits: [.staticText])
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface())
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(transient: [transient])
        )

        let delta = AccessibilityTrace.Delta.between(before, after)

        XCTAssertEqual(after.transition.transient, [transient])
        XCTAssertEqual(delta.testTransient, [transient])
        XCTAssertEqual(delta.testCaptureEdge?.before.hash, before.hash)
        XCTAssertEqual(delta.testCaptureEdge?.after.hash, after.hash)
    }

    func testCaptureContextOnlyDiffsAsElementsChanged() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(keyboardVisible: true)
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(keyboardVisible: false)
        )

        guard case .elementsChanged(let payload) = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected elementsChanged for capture context change")
        }
        XCTAssertEqual(payload.elementCount, interface.projectedElements.count)
        XCTAssertTrue(payload.edits.isEmpty)
    }

    func testCaptureScreenContextDiffsAsScreenChanged() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(screenId: "menu")
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(screenId: "checkout")
        )

        guard case .screenChanged(let payload) = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected screenChanged for screen id context change")
        }
        XCTAssertEqual(payload.newInterface, interface)
    }

    func testCaptureChainMetadataDoesNotAffectDiff() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(sequence: 1, interface: interface, parentHash: nil)
        let after = AccessibilityTrace.Capture(sequence: 99, interface: interface, parentHash: "sha256:parent")

        XCTAssertEqual(
            AccessibilityTrace.Delta.between(before, after),
            .noChange(AccessibilityTrace.NoChange(
                elementCount: interface.projectedElements.count,
                captureEdge: AccessibilityTrace.CaptureEdge(before: before, after: after)
            ))
        )
    }

    func testElementDiffTreatsIndistinguishableElementsAsNoChangeWithoutHierarchyContext() {
        let before = makeElement(label: "Item", traits: [.staticText])
        let after = makeElement(label: "Item", traits: [.staticText])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.isEmpty)
    }

    private func makeInterface() -> Interface {
        makeInterface(label: "Menu")
    }

    private func makeInterface(label: String) -> Interface {
        makeTestInterface(elements: [
            makeElement(label: label, traits: [.header]),
            makeElement(label: "Total", value: "$5.00", traits: [.staticText]),
        ])
    }

    private func makeContainer() -> AccessibilityContainer {
        makeTestAccessibilityContainer()
    }

    private func makeElement(
        label: String,
        value: String? = nil,
        traits: [HeistTrait]
    ) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: value,
            identifier: nil,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
    }

    private func assertDeltaDerivesFromCaptureEdge(
        _ delta: AccessibilityTrace.Delta,
        trace: AccessibilityTrace,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let edge = try XCTUnwrap(delta.testCaptureEdge, "Delta did not carry capture edge", file: file, line: line)
        let before = try XCTUnwrap(trace.capture(ref: edge.before), "Trace did not contain before ref", file: file, line: line)
        let after = try XCTUnwrap(trace.capture(ref: edge.after), "Trace did not contain after ref", file: file, line: line)

        XCTAssertEqual(edge.before.hash, before.hash, file: file, line: line)
        XCTAssertEqual(edge.after.hash, after.hash, file: file, line: line)
        XCTAssertEqual(delta, AccessibilityTrace.Delta.between(before, after), file: file, line: line)
    }

    private func captureDelta(
        before beforeInterface: Interface,
        after afterInterface: Interface,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AccessibilityTrace.Delta {
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: beforeInterface
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: before.hash
        )
        let delta = AccessibilityTrace.Delta.between(before, after)
        XCTAssertNotNil(delta.testCaptureEdge, file: file, line: line)
        return delta
    }

}
