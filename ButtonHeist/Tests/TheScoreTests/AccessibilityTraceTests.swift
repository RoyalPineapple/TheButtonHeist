import XCTest
import ThePlans
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
            context: AccessibilityTrace.Context(keyboardVisible: false)
        )
        let focused = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(keyboardVisible: true)
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
                transient: [makeElement(label: "Loading", traits: [.staticText])]
            )
        )

        XCTAssertEqual(stable.hash, withTransition.hash)
        XCTAssertNotEqual(stable.transition, withTransition.transition)
    }

    func testCaptureHashHandlesNonFiniteParserGeometry() throws {
        let element = HeistElement(
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
        let transient = makeElement(label: "Loading", traits: [.staticText])

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

    func testInterfaceProjectsDuplicateTraversalIndexesByPath() throws {
        let first = makeElement(label: "First", actions: [.activate])
        let second = makeElement(label: "Second", actions: [.increment])
        let interface = Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [
                .element(makeTestAccessibilityElement(first), traversalIndex: 0),
                .element(makeTestAccessibilityElement(second), traversalIndex: 0),
            ],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(
                    path: TreePath([0]),
                    actions: first.actions
                ),
                InterfaceElementAnnotation(
                    path: TreePath([1]),
                    actions: second.actions
                ),
            ])
        )

        XCTAssertEqual(interface.projectedElements.map(\.label), ["First", "Second"])
        XCTAssertEqual(interface.projectedElements.map(\.actions), [[.activate], [.increment]])
    }

    func testScreenChangeReasonProjectsScreenChangedDelta() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )

        guard case .screenChanged = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected screenChanged delta")
        }
    }

    func testScreenChangeReasonOverridesStructuralChange() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeListInterface(["Antipasti"]))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeListInterface(["Antipasti", "Pasta"]),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
        )

        guard case .screenChanged = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected screenChanged delta")
        }
    }

    func testScreenIdChangeProjectsScreenChangedDelta() throws {
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

        guard case .screenChanged = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected screenChanged delta")
        }
    }

    func testSameScreenContextChangeProjectsElementChangedDelta() throws {
        let interface = makeInterface(label: "Menu")
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

        guard case .elementsChanged = AccessibilityTrace.Delta.between(before, after) else {
            return XCTFail("Expected elementsChanged delta")
        }
    }

    func testTraceProjectsEndpointScreenContext() throws {
        let trace = AccessibilityTrace(first: makeInterface(label: "Home")).appending(
            makeInterface(label: "Settings"),
            context: AccessibilityTrace.Context(screenId: "settings_context")
        )

        XCTAssertEqual(trace.endpointScreenName, "Settings")
        XCTAssertEqual(trace.endpointScreenId, "settings_context")
    }

    func testAccumulatedDeltaPreservesIntermediateElementUpdates() throws {
        let baseline = makeInterface(label: "Counter", saveValue: "0")
        let halfway = makeInterface(label: "Counter", saveValue: "50")
        let final = makeInterface(label: "Counter", saveValue: "100")
        let trace = AccessibilityTrace(first: baseline)
            .appending(halfway)
            .appending(final)

        let accumulated = try XCTUnwrap(trace.accumulatedDelta)
        let updates = try XCTUnwrap(accumulated.elementsChanged?.edits.updated)
        let valueChanges = updates.flatMap(\.changes).filter { $0.property == .value }

        XCTAssertTrue(valueChanges.contains(PropertyChange(property: .value, old: "0", new: "50")))
        XCTAssertTrue(valueChanges.contains(PropertyChange(property: .value, old: "50", new: "100")))

        let predicate = AccessibilityPredicate.change(.elements(.updatedElement(ElementUpdatePredicate(
            element: .label("Save"),
            change: .value(before: "0", after: "50")
        ))))
        let result = predicate.evaluate(
            currentElements: final.projectedElements,
            accumulatedDelta: accumulated
        )

        XCTAssertTrue(result.met, result.actual ?? "predicate did not match")
    }

    func testAccumulatedDeltaAllowsElementAndScreenAssertionsInOneWaitWindow() throws {
        let baseline = makeInterface(label: "Menu", saveValue: "0")
        let updated = makeInterface(label: "Menu", saveValue: "50")
        let final = makeInterface(label: "Settings", saveValue: "50")
        let trace = AccessibilityTrace(first: baseline)
            .appending(updated)
            .appending(
                final,
                transition: AccessibilityTrace.Transition(screenChangeReason: "primaryHeaderChanged")
            )

        let accumulated = try XCTUnwrap(trace.accumulatedDelta)
        XCTAssertNotNil(accumulated.elementsChanged)
        XCTAssertNotNil(accumulated.screenChanged)

        let predicate = AccessibilityPredicate.change(
            .elements(.updatedElement(ElementUpdatePredicate(
                element: .label("Save"),
                change: .value(before: "0", after: "50")
            ))),
            .screen(.exists(ElementPredicate(label: "Settings")))
        )
        let result = predicate.evaluate(
            currentElements: final.projectedElements,
            accumulatedDelta: accumulated
        )

        XCTAssertTrue(result.met, result.actual ?? "predicate did not match")
    }

    func testTraceConstructionNormalizesToSingleLinkedList() throws {
        let first = AccessibilityTrace.Capture(
            sequence: 99,
            interface: makeInterface(label: "Home"),
            parentHash: "sha256:bad",
            context: AccessibilityTrace.Context(keyboardVisible: true)
        )
        let second = AccessibilityTrace.Capture(sequence: 42, interface: makeInterface(label: "Settings"), parentHash: "sha256:fork")

        let trace = AccessibilityTrace(captures: [first, second])

        XCTAssertEqual(trace.captures.map(\.sequence), [1, 2])
        XCTAssertNil(trace.captures[0].parentHash)
        XCTAssertEqual(trace.captures[1].parentHash, trace.captures[0].hash)
        XCTAssertEqual(trace.captures[0].context.keyboardVisible, true)
        XCTAssertTrue(trace.isLinearChain)
    }

    private func makeInterface(
        label: String = "Settings",
        saveValue: String? = nil,
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) -> Interface {
        makeTestInterface(
            elements: [
                makeElement(label: label, traits: [.header]),
                makeElement(label: "Save", value: saveValue),
            ],
            timestamp: timestamp
        )
    }

    private func makeListInterface(_ labels: [String]) -> Interface {
        makeTestInterface(nodes: [
            testContainer(makeTestAccessibilityContainer(), containerName: "category-grid", children: labels.map { label in
                testElement(makeElement(
                    label: label,
                    traits: [.button]
                ))
            }),
        ])
    }

    private func makeDuplicateTraversalIndexInterface(secondLabel: String) -> Interface {
        let first = makeElement(label: "First")
        let second = makeElement(label: secondLabel)
        return Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: [
                .element(makeTestAccessibilityElement(first), traversalIndex: 0),
                .element(makeTestAccessibilityElement(second), traversalIndex: 0),
            ],
            annotations: InterfaceAnnotations(elements: [
                InterfaceElementAnnotation(
                    path: TreePath([0]),
                    actions: first.actions
                ),
                InterfaceElementAnnotation(
                    path: TreePath([1]),
                    actions: second.actions
                ),
            ])
        )
    }

    private func makeElement(
        label: String,
        value: String? = nil,
        traits: [HeistTrait] = [.button],
        actions: [ElementAction] = [.activate]
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
            actions: actions
        )
    }

}
