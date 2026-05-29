import XCTest
import AccessibilitySnapshotModel
@testable import TheScore

private struct CaptureWithoutContextFixture: Encodable {
    let capture: AccessibilityTrace.Capture

    private enum CodingKeys: String, CodingKey {
        case sequence
        case hash
        case parentHash
        case interface
        case transition
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capture.sequence, forKey: .sequence)
        try container.encode(capture.hash, forKey: .hash)
        try container.encodeIfPresent(capture.parentHash, forKey: .parentHash)
        try container.encode(capture.interface, forKey: .interface)
        if !capture.transition.isEmpty {
            try container.encode(capture.transition, forKey: .transition)
        }
    }
}

final class AccessibilityTraceTests: XCTestCase {

    func testDecodeRejectsUnknownTraceFields() {
        let json = #"{"captures":[],"unexpectedField":[]}"#

        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityTrace.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, #"Unknown AccessibilityTrace field "unexpectedField""#)
        }
    }

    func testCaptureDecodeRejectsMissingContext() throws {
        let capture = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface())
        let data = try JSONEncoder().encode(CaptureWithoutContextFixture(capture: capture))

        XCTAssertThrowsError(try JSONDecoder().decode(AccessibilityTrace.Capture.self, from: data)) { error in
            XCTAssertTrue(
                "\(error)".contains("No value associated with key"),
                "Expected missing context rejection, got \(error)"
            )
        }
    }

    func testCaptureCarriesFullInterfaceAndStableHash() throws {
        let interface = makeInterface(timestamp: Date(timeIntervalSince1970: 1))
        let sameContent = makeInterface(timestamp: Date(timeIntervalSince1970: 2))

        let capture = AccessibilityTrace.Capture(sequence: 3, interface: interface, parentHash: "sha256:parent")
        let sameHash = AccessibilityTrace.Capture.hash(sameContent)

        XCTAssertEqual(capture.hash, sameHash)
        XCTAssertEqual(capture.parentHash, "sha256:parent")
        XCTAssertEqual(capture.interface.tree, interface.tree)
        XCTAssertEqual(capture.summary, "Settings — 1 button (2 elements)")
    }

    func testCaptureHashIncludesSemanticContext() throws {
        let interface = makeInterface()
        let unfocused = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(focusedElementId: nil, keyboardVisible: false)
        )
        let focused = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(focusedElementId: "save", keyboardVisible: true)
        )

        XCTAssertNotEqual(unfocused.hash, focused.hash)
    }

    func testCaptureHashExcludesTransitionMetadata() throws {
        let interface = makeInterface()
        let stable = AccessibilityTrace.Capture(sequence: 1, interface: interface)
        let withTransition = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            transition: AccessibilityTrace.Transition(
                screenChangeReason: "primaryHeaderChanged",
                transient: [makeElement(heistId: "spinner", label: "Loading", traits: [.staticText])]
            )
        )

        XCTAssertEqual(stable.hash, withTransition.hash)
        XCTAssertNotEqual(stable.transition, withTransition.transition)
    }

    func testCaptureHashHandlesNonFiniteParserGeometry() throws {
        let element = HeistElement(
            heistId: "picker-row",
            description: "Picker Row",
            label: "Picker Row",
            value: nil,
            identifier: nil,
            traits: [.button],
            frameX: .nan,
            frameY: .infinity,
            frameWidth: -.infinity,
            frameHeight: 44,
            activationPointX: .nan,
            activationPointY: .infinity,
            actions: [.activate]
        )
        let interface = makeTestInterface(elements: [element])

        let capture = AccessibilityTrace.Capture(sequence: 1, interface: interface)

        XCTAssertTrue(capture.hash.hasPrefix("sha256:"))
        XCTAssertEqual(capture.hash, AccessibilityTrace.Capture(sequence: 2, interface: interface).hash)
    }

    func testTraceCanLookupCaptureByHash() throws {
        let first = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Home"))
        let second = AccessibilityTrace.Capture(sequence: 2, interface: makeInterface(label: "Settings"), parentHash: first.hash)
        let trace = AccessibilityTrace(captures: [first, second])

        XCTAssertEqual(trace.capture(hash: second.hash)?.hash, second.hash)
        XCTAssertEqual(trace.capture(ref: AccessibilityTrace.CaptureRef(capture: second))?.hash, second.hash)
        XCTAssertEqual(trace.receipts.map(\.hash), [first.hash, second.hash])
        XCTAssertEqual(trace.receipts[1].parentHash, first.hash)
        XCTAssertTrue(trace.isLinearChain)
    }

    func testAppendingCreatesSingleLinkedList() throws {
        let first = makeInterface(label: "Home")
        let second = makeInterface(label: "Settings")

        let trace = AccessibilityTrace(first: first).appending(second)

        XCTAssertEqual(trace.captures.map(\.sequence), [1, 2])
        XCTAssertNil(trace.captures[0].parentHash)
        XCTAssertEqual(trace.captures[1].parentHash, trace.captures[0].hash)
        XCTAssertTrue(trace.isLinearChain)
    }

    func testAppendingCarriesTransitionOnCaptureEdge() throws {
        let first = makeInterface(label: "Home")
        let second = makeInterface(label: "Settings")
        let transient = makeElement(heistId: "spinner", label: "Loading", traits: [.staticText])

        let trace = AccessibilityTrace(first: first).appending(
            second,
            transition: AccessibilityTrace.Transition(
                screenChangeReason: "primaryHeaderChanged",
                transient: [transient]
            )
        )

        XCTAssertEqual(trace.captures[1].transition.screenChangeReason, "primaryHeaderChanged")
        XCTAssertEqual(trace.captures[1].transition.transient, [transient])
        XCTAssertEqual(trace.captures[1].parentHash, trace.captures[0].hash)
    }

    func testSameScreenChangesProjectAsPatchInsideScreenSegment() throws {
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: makeInterface(label: "Menu", saveValue: "1")
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Menu", saveValue: "2"),
            parentHash: before.hash
        )

        let trace = AccessibilityTrace(captures: [before, after])

        XCTAssertEqual(trace.screenSegmentsProjection.count, 1)
        XCTAssertEqual(trace.screenSegmentsProjection[0].baseline.hash, before.hash)
        XCTAssertEqual(trace.screenSegmentsProjection[0].transitions.count, 1)
        XCTAssertEqual(trace.screenSegmentsProjection[0].transitions[0].fromHash, before.hash)
        XCTAssertEqual(trace.screenSegmentsProjection[0].transitions[0].toHash, after.hash)
        XCTAssertEqual(trace.captures.map(\.interface), [before.interface, after.interface])
        XCTAssertTrue(trace.hasValidIntegrity)
    }

    func testSameScreenStructuralEditsStayInOneSegmentAndMaterialize() throws {
        let baselineInterface = makeListInterface(["Antipasti"])
        let insertedInterface = makeListInterface(["Antipasti", "Pasta"])
        let movedInterface = makeListInterface(["Pasta", "Antipasti"])
        let removedInterface = makeListInterface(["Pasta"])
        let baseline = AccessibilityTrace.Capture(sequence: 1, interface: baselineInterface)
        let inserted = AccessibilityTrace.Capture(
            sequence: 2,
            interface: insertedInterface,
            parentHash: baseline.hash
        )
        let moved = AccessibilityTrace.Capture(sequence: 3, interface: movedInterface, parentHash: inserted.hash)
        let removed = AccessibilityTrace.Capture(sequence: 4, interface: removedInterface, parentHash: moved.hash)

        let trace = AccessibilityTrace(captures: [baseline, inserted, moved, removed])

        XCTAssertEqual(trace.screenSegmentsProjection.count, 1)
        XCTAssertEqual(trace.screenSegmentsProjection[0].transitions.count, 3)
        XCTAssertEqual(
            trace.captures.map(\.interface),
            [baselineInterface, insertedInterface, movedInterface, removedInterface]
        )
        XCTAssertTrue(trace.hasValidIntegrity)
    }

    func testInterfaceProjectsDuplicateTraversalIndexesByPath() throws {
        let first = makeElement(heistId: "first", label: "First", actions: [.activate])
        let second = makeElement(heistId: "second", label: "Second", actions: [.increment])
        let interface = Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [
                .element(makeTestAccessibilityElement(first), traversalIndex: 0),
                .element(makeTestAccessibilityElement(second), traversalIndex: 0),
            ],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(
                    path: TreePath([0]),
                    heistId: first.heistId,
                    actions: first.actions
                ),
                InterfaceElementAnnotation(
                    path: TreePath([1]),
                    heistId: second.heistId,
                    actions: second.actions
                ),
            ])
        )

        XCTAssertEqual(interface.elements.map(\.heistId), ["first", "second"])
        XCTAssertEqual(interface.elements.map(\.actions), [[.activate], [.increment]])
    }

    func testTracePatchUpdatesOnlyChangedPathWhenTraversalIndexesRepeatAcrossRoots() throws {
        let beforeInterface = makeDuplicateTraversalIndexInterface(secondLabel: "Before")
        let afterInterface = makeDuplicateTraversalIndexInterface(secondLabel: "After")
        let before = AccessibilityTrace.Capture(sequence: 1, interface: beforeInterface)
        let after = AccessibilityTrace.Capture(sequence: 2, interface: afterInterface, parentHash: before.hash)

        let transition = try XCTUnwrap(AccessibilityTrace.ObservedTransitionProjection.between(before, after))

        XCTAssertEqual(transition.patch.operations, [
            .updateElement(path: TreePath([1]), element: afterInterface.tree.pathIndexedElements[1].element),
        ])
        XCTAssertEqual(transition.patch.apply(to: before, sequence: after.sequence).interface, afterInterface)
    }

    func testScreenChangesStartNewBaselineSegment() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )

        let trace = AccessibilityTrace(captures: [before, after])

        XCTAssertEqual(trace.screenSegmentsProjection.count, 2)
        XCTAssertEqual(trace.screenSegmentsProjection.map(\.baseline.hash), [before.hash, after.hash])
        XCTAssertEqual(trace.screenSegmentsProjection.flatMap(\.transitions), [])
        XCTAssertEqual(trace.captures.map(\.hash), [before.hash, after.hash])
    }

    func testObservedTransitionDoesNotRepresentScreenChange() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )

        XCTAssertEqual(AccessibilityTrace.Delta.between(before, after).kind, .screenChanged)
        XCTAssertNil(AccessibilityTrace.ObservedTransitionProjection.between(before, after))
    }

    func testScreenChangeReasonStartsNewSegmentEvenForStructuralChange() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeListInterface(["Antipasti"]))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeListInterface(["Antipasti", "Pasta"]),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )

        let trace = AccessibilityTrace(captures: [before, after])

        XCTAssertEqual(trace.screenSegmentsProjection.map(\.baseline.hash), [before.hash, after.hash])
        XCTAssertEqual(trace.screenSegmentsProjection.flatMap(\.transitions), [])
        XCTAssertEqual(trace.screenSegmentsProjection[1].baseline.interface, after.interface)
        XCTAssertTrue(trace.hasValidIntegrity)
    }

    func testScreenIdChangeStartsNewBaselineSegmentUsingDeltaSemantics() throws {
        let interface = makeInterface(label: "Menu")
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

        let trace = AccessibilityTrace(captures: [before, after])

        XCTAssertEqual(AccessibilityTrace.Delta.between(before, after).kind, .screenChanged)
        XCTAssertEqual(trace.screenSegmentsProjection.count, 2)
        XCTAssertEqual(trace.screenSegmentsProjection.map(\.baseline.hash), [before.hash, after.hash])
        XCTAssertEqual(trace.screenSegmentsProjection.flatMap(\.transitions), [])
    }

    func testSameScreenContextChangeStaysPatchUsingDeltaSemantics() throws {
        let interface = makeInterface(label: "Menu")
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

        let trace = AccessibilityTrace(captures: [before, after])

        XCTAssertEqual(AccessibilityTrace.Delta.between(before, after).kind, .elementsChanged)
        XCTAssertEqual(trace.screenSegmentsProjection.count, 1)
        XCTAssertEqual(trace.screenSegmentsProjection[0].baseline.hash, before.hash)
        XCTAssertEqual(trace.screenSegmentsProjection[0].transitions.map(\.toHash), [after.hash])
        XCTAssertEqual(trace.captures.map(\.hash), [before.hash, after.hash])
    }

    func testTraceProjectsEndpointScreenContext() throws {
        let trace = AccessibilityTrace(first: makeInterface(label: "Home")).appending(
            makeInterface(label: "Settings"),
            context: AccessibilityTrace.Context(screenId: "settings_context")
        )

        XCTAssertEqual(trace.endpointScreenNameProjection, "Settings")
        XCTAssertEqual(trace.endpointScreenIdProjection, "settings_context")
    }

    func testTraceConstructionNormalizesToSingleLinkedList() throws {
        let first = AccessibilityTrace.Capture(
            sequence: 99,
            interface: makeInterface(label: "Home"),
            parentHash: "sha256:bad",
            context: AccessibilityTrace.Context(focusedElementId: "title")
        )
        let second = AccessibilityTrace.Capture(sequence: 42, interface: makeInterface(label: "Settings"), parentHash: "sha256:fork")

        let trace = AccessibilityTrace(captures: [first, second])

        XCTAssertEqual(trace.captures.map(\.sequence), [1, 2])
        XCTAssertNil(trace.captures[0].parentHash)
        XCTAssertEqual(trace.captures[1].parentHash, trace.captures[0].hash)
        XCTAssertEqual(trace.captures[0].context.focusedElementId, "title")
        XCTAssertTrue(trace.isLinearChain)
    }

    private func makeInterface(
        label: String = "Settings",
        saveValue: String? = nil,
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) -> Interface {
        makeTestInterface(
            elements: [
                makeElement(heistId: "title", label: label, traits: [.header]),
                makeElement(heistId: "save", label: "Save", value: saveValue),
            ],
            timestamp: timestamp
        )
    }

    private func makeListInterface(_ labels: [String]) -> Interface {
        makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(), stableId: "category-grid", children: labels.map { label in
                testElement(makeElement(
                    heistId: "tile-\(label.lowercased())",
                    label: label,
                    traits: [.button]
                ))
            }),
        ])
    }

    private func makeDuplicateTraversalIndexInterface(secondLabel: String) -> Interface {
        let first = makeElement(heistId: "first", label: "First")
        let second = makeElement(heistId: "second", label: secondLabel)
        return Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [
                .element(makeTestAccessibilityElement(first), traversalIndex: 0),
                .element(makeTestAccessibilityElement(second), traversalIndex: 0),
            ],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(
                    path: TreePath([0]),
                    heistId: first.heistId,
                    actions: first.actions
                ),
                InterfaceElementAnnotation(
                    path: TreePath([1]),
                    heistId: second.heistId,
                    actions: second.actions
                ),
            ])
        )
    }

    private func makeElement(
        heistId: HeistId,
        label: String,
        value: String? = nil,
        traits: [HeistTrait] = [.button],
        actions: [ElementAction] = [.activate]
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
            actions: actions
        )
    }

}
