import XCTest
@testable import TheScore

final class AccessibilityTraceDiffTests: XCTestCase {

    func testElementDiffIsSingleElementHierarchyDiff() {
        let before = makeElement(heistId: "total", label: "Total", value: "$5.00", traits: [.staticText])
        let after = makeElement(heistId: "total", label: "Total", value: "$7.00", traits: [.staticText])

        XCTAssertEqual(
            ElementEdits.between(before, after),
            ElementEdits.between([InterfaceNode.element(before)], [InterfaceNode.element(after)])
        )
        XCTAssertEqual(
            AccessibilityTrace.Delta.between(before, after),
            AccessibilityTrace.Delta.between([InterfaceNode.element(before)], [InterfaceNode.element(after)])
        )
    }

    func testNodeDiffIsTreeDiff() {
        let before = InterfaceNode.container(makeContainer(stableId: "section"), children: [
            .element(makeElement(heistId: "title", label: "Menu", traits: [.header])),
        ])
        let after = InterfaceNode.container(makeContainer(stableId: "section"), children: [
            .element(makeElement(heistId: "title", label: "Checkout", traits: [.header])),
        ])

        XCTAssertEqual(ElementEdits.between(before, after), ElementEdits.between([before], [after]))
        XCTAssertEqual(AccessibilityTrace.Delta.between(before, after), AccessibilityTrace.Delta.between([before], [after]))
    }

    func testTreeInterfaceAndCaptureDiffsShareTheSameEdits() {
        let beforeTree: [InterfaceNode] = [
            .container(makeContainer(stableId: "main"), children: [
                .element(makeElement(heistId: "title", label: "Menu", traits: [.header])),
                .element(makeElement(heistId: "total", label: "Total", value: "$5.00", traits: [.staticText])),
            ]),
        ]
        let afterTree: [InterfaceNode] = [
            .container(makeContainer(stableId: "main"), children: [
                .element(makeElement(heistId: "title", label: "Menu", traits: [.header])),
                .element(makeElement(heistId: "total", label: "Total", value: "$7.00", traits: [.staticText])),
            ]),
        ]
        let beforeInterface = Interface(timestamp: Date(timeIntervalSince1970: 1), tree: beforeTree)
        let afterInterface = Interface(timestamp: Date(timeIntervalSince1970: 2), tree: afterTree)
        let beforeCapture = AccessibilityTrace.Capture(sequence: 1, interface: beforeInterface)
        let afterCapture = AccessibilityTrace.Capture(sequence: 2, interface: afterInterface, parentHash: beforeCapture.hash)

        XCTAssertEqual(ElementEdits.between(beforeTree, afterTree), ElementEdits.between(beforeInterface, afterInterface))
        XCTAssertEqual(
            AccessibilityTrace.Delta.between(beforeTree, afterTree),
            AccessibilityTrace.Delta.between(beforeInterface, afterInterface)
        )
        XCTAssertEqualIgnoringCaptureEdge(
            AccessibilityTrace.Delta.between(beforeInterface, afterInterface),
            AccessibilityTrace.Delta.between(beforeCapture, afterCapture)
        )
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

    func testTraceEndpointDeltaDerivesFromCaptureEndpoints() {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let middle = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Loading"),
            parentHash: before.hash
        )
        let after = AccessibilityTrace.Capture(
            sequence: 3,
            interface: makeInterface(label: "Checkout"),
            parentHash: middle.hash
        )
        let trace = AccessibilityTrace(captures: [before, middle, after])

        XCTAssertEqual(
            trace.captureEndpointDelta,
            AccessibilityTrace.Delta.between(trace.captures[0], trace.captures[2])
        )
    }

    func testTraceReceiptDeltaOmitsPlainNoChangeButKeepsTransientNoChange() {
        let transient = makeElement(heistId: "spinner", label: "Loading", traits: [.staticText])
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface())
        let unchanged = AccessibilityTrace(captures: [
            before,
            AccessibilityTrace.Capture(sequence: 2, interface: makeInterface(), parentHash: before.hash),
        ])
        let transientTrace = AccessibilityTrace(captures: [
            before,
            AccessibilityTrace.Capture(
                sequence: 2,
                interface: makeInterface(),
                parentHash: before.hash,
                transition: AccessibilityTrace.Transition(transient: [transient])
            ),
        ])

        XCTAssertNil(unchanged.captureReceiptDelta)
        XCTAssertEqual(transientTrace.captureReceiptDelta?.transient, [transient])
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

    func testTransitionTransientLivesOnCaptureEdgeAndProjectsToLegacyDeltaField() throws {
        let transient = makeElement(heistId: "spinner", label: "Loading", traits: [.staticText])
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface())
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(transient: [transient])
        )

        let delta = AccessibilityTrace.Delta.between(before, after)

        XCTAssertEqual(after.transition.transient, [transient])
        XCTAssertEqual(delta.transient, [transient])
        XCTAssertEqual(delta.captureEdge?.before.hash, before.hash)
        XCTAssertEqual(delta.captureEdge?.after.hash, after.hash)
    }

    func testCaptureContextOnlyDiffsAsElementsChanged() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(focusedElementId: "search", keyboardVisible: true)
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(focusedElementId: "total", keyboardVisible: false)
        )

        guard case .elementsChanged(let payload) = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected elementsChanged for capture context change")
        }
        XCTAssertEqual(payload.elementCount, interface.elements.count)
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
                elementCount: interface.elements.count,
                captureEdge: AccessibilityTrace.CaptureEdge(before: before, after: after)
            ))
        )
    }

    func testOldDeltaOnlyPayloadDecodesWithoutCaptureEdge() throws {
        let jsonString = """
        {"kind": "noChange", "elementCount": 2}
        """

        let decoded = try JSONDecoder().decode(AccessibilityTrace.Delta.self, from: Data(jsonString.utf8))

        XCTAssertNil(decoded.captureEdge)
        XCTAssertEqual(decoded.kindRawValue, "noChange")
        XCTAssertEqual(decoded.elementCount, 2)
    }

    func testElementDiffTreatsIndistinguishableElementsAsNoChangeWithoutHierarchyContext() {
        let before = makeElement(heistId: "first", label: "Item", traits: [.staticText])
        let after = makeElement(heistId: "second", label: "Item", traits: [.staticText])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.isEmpty)
    }

    private func makeInterface() -> Interface {
        makeInterface(label: "Menu")
    }

    private func makeInterface(label: String) -> Interface {
        Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [
            .element(makeElement(heistId: "title", label: label, traits: [.header])),
            .element(makeElement(heistId: "total", label: "Total", value: "$5.00", traits: [.staticText])),
        ])
    }

    private func makeContainer(stableId: String) -> ContainerInfo {
        ContainerInfo(
            type: .semanticGroup(label: nil, value: nil, identifier: nil),
            stableId: stableId,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 100
        )
    }

    private func makeElement(
        heistId: String,
        label: String,
        value: String? = nil,
        traits: [HeistTrait]
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
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
        let edge = try XCTUnwrap(delta.captureEdge, "Delta did not carry capture edge", file: file, line: line)
        let before = try XCTUnwrap(trace.capture(ref: edge.before), "Trace did not contain before ref", file: file, line: line)
        let after = try XCTUnwrap(trace.capture(ref: edge.after), "Trace did not contain after ref", file: file, line: line)

        XCTAssertEqual(edge.before.hash, before.hash, file: file, line: line)
        XCTAssertEqual(edge.after.hash, after.hash, file: file, line: line)
        XCTAssertEqual(delta, AccessibilityTrace.Delta.between(before, after), file: file, line: line)
    }

    private func XCTAssertEqualIgnoringCaptureEdge(
        _ lhs: AccessibilityTrace.Delta,
        _ rhs: AccessibilityTrace.Delta,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(stripCaptureEdge(lhs), stripCaptureEdge(rhs), file: file, line: line)
    }

    private func stripCaptureEdge(_ delta: AccessibilityTrace.Delta) -> AccessibilityTrace.Delta {
        switch delta {
        case .noChange(let payload):
            return .noChange(AccessibilityTrace.NoChange(
                elementCount: payload.elementCount,
                transient: payload.transient
            ))
        case .elementsChanged(let payload):
            return .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: payload.elementCount,
                edits: payload.edits,
                transient: payload.transient
            ))
        case .screenChanged(let payload):
            return .screenChanged(AccessibilityTrace.ScreenChanged(
                elementCount: payload.elementCount,
                newInterface: payload.newInterface,
                postEdits: payload.postEdits,
                transient: payload.transient
            ))
        }
    }
}
