import XCTest
import AccessibilitySnapshotModel
@testable import TheScore

final class AccessibilityTraceTests: XCTestCase {

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

    func testSameScreenChangesAreStoredAsPatchInsideScreenSegment() throws {
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

        XCTAssertEqual(trace.segments.count, 1)
        XCTAssertEqual(trace.segments[0].baseline.hash, before.hash)
        XCTAssertEqual(trace.segments[0].transitions.count, 1)
        XCTAssertEqual(trace.segments[0].transitions[0].fromHash, before.hash)
        XCTAssertEqual(trace.segments[0].transitions[0].toHash, after.hash)
        XCTAssertEqual(trace.segments[0].captures.map(\.hash), trace.captures.map(\.hash))
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

        XCTAssertEqual(trace.segments.count, 1)
        XCTAssertEqual(trace.segments[0].transitions.count, 3)
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

        let transition = try XCTUnwrap(AccessibilityTrace.ObservedTransition.between(before, after))

        XCTAssertEqual(transition.patch.operations, [
            .updateElement(path: TreePath([1]), element: afterInterface.tree.pathIndexedElements[1].element),
        ])
        XCTAssertEqual(transition.materialize(after: before).interface, afterInterface)
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

        XCTAssertEqual(trace.segments.count, 2)
        XCTAssertEqual(trace.segments.map(\.baseline.hash), [before.hash, after.hash])
        XCTAssertEqual(trace.segments.flatMap(\.transitions), [])
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
        XCTAssertNil(AccessibilityTrace.ObservedTransition.between(before, after))
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

        XCTAssertEqual(trace.segments.map(\.captures.count), [1, 1])
        XCTAssertEqual(trace.segments[1].baseline.interface, after.interface)
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
        XCTAssertEqual(trace.segments.count, 2)
        XCTAssertEqual(trace.segments.map(\.baseline.hash), [before.hash, after.hash])
        XCTAssertEqual(trace.segments.flatMap(\.transitions), [])
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
        XCTAssertEqual(trace.segments.count, 1)
        XCTAssertEqual(trace.segments[0].baseline.hash, before.hash)
        XCTAssertEqual(trace.segments[0].transitions.map(\.toHash), [after.hash])
        XCTAssertEqual(trace.captures.map(\.hash), [before.hash, after.hash])
    }

    func testTraceProjectsEndpointScreenContext() throws {
        let trace = AccessibilityTrace(first: makeInterface(label: "Home")).appending(
            makeInterface(label: "Settings"),
            context: AccessibilityTrace.Context(screenId: "settings_context")
        )

        XCTAssertEqual(trace.captureEndpointScreenName, "Settings")
        XCTAssertEqual(trace.captureEndpointScreenId, "settings_context")
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

    func testOldCaptureWithoutTransitionDecodesAsEmptyTransition() throws {
        let interface = makeInterface()
        let capture = AccessibilityTrace.Capture(sequence: 1, interface: interface)
        let data = try JSONEncoder().encode(capture)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "transition")
        let oldShapeData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(AccessibilityTrace.Capture.self, from: oldShapeData)

        XCTAssertEqual(decoded.hash, capture.hash)
        XCTAssertEqual(decoded.transition, .empty)
    }

    func testIntegrityValidationCatchesCorruptedStructuralPatch() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeListInterface(["Antipasti"]))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeListInterface(["Antipasti", "Pasta"]),
            parentHash: before.hash
        )
        let transition = try XCTUnwrap(AccessibilityTrace.ObservedTransition.between(before, after))
        let corruptedPatch = AccessibilityTrace.AccessibilityPatch(
            operations: corruptFirstStructuralOperation(transition.patch.operations),
            timestamp: transition.patch.timestamp,
            annotations: transition.patch.annotations,
            context: transition.patch.context,
            transition: transition.patch.transition
        )
        let corruptedTrace = AccessibilityTrace(segments: [
            AccessibilityTrace.ScreenSegment(
                baseline: before,
                transitions: [AccessibilityTrace.ObservedTransition(
                    sequence: transition.sequence,
                    fromHash: transition.fromHash,
                    toHash: transition.toHash,
                    patch: corruptedPatch
                )]
            ),
        ])

        XCTAssertTrue(corruptedTrace.integrityIssues.contains {
            if case .transitionToHashMismatch = $0 { return true }
            return false
        })
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

    private func corruptFirstStructuralOperation(
        _ operations: [AccessibilityTrace.AccessibilityPatchOperation]
    ) -> [AccessibilityTrace.AccessibilityPatchOperation] {
        let corruptNode = makeTestInterface(elements: [
            makeElement(heistId: "tile-corrupt", label: "Corrupt"),
        ]).tree[0]
        return operations.map { operation in
            switch operation {
            case .insertSubtree(let insertion):
                return .insertSubtree(TreeInsertion(
                    location: insertion.location,
                    node: corruptNode,
                    annotations: insertion.annotations
                ))
            case .moveSubtree(let move, _):
                return .moveSubtree(move, node: corruptNode)
            case .replaceTree:
                return .replaceTree(tree: [corruptNode])
            case .updateElement, .updateContainer, .removeSubtree:
                return operation
            }
        }
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
