import XCTest
import ButtonHeistTestSupport
import ThePlans
import AccessibilitySnapshotModel
@testable import TheScore

final class AccessibilityTraceChangeFactTests: AccessibilityTraceDiffTestCase {
    func testTreeInterfaceAndCaptureDiffsShareTheSameEdits() throws {
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
        let afterCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: beforeCapture.hash
        )

        XCTAssertEqual(
            ElementEdits.between(beforeInterface.projectedElements, afterInterface.projectedElements).updated,
            ElementEdits.between(beforeInterface, afterInterface).updated
        )
        let facts = AccessibilityTrace.ChangeFact.between(beforeCapture, afterCapture)
        XCTAssertEqual(facts.testElementEdits, ElementEdits.between(beforeInterface, afterInterface))
    }

    func testCaptureBackedNoChangeIsACompleteFactFreeTrace() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface())
        let after = AccessibilityTrace.Capture(sequence: 2, interface: makeInterface(), parentHash: before.hash)
        let trace = AccessibilityTrace(captures: [before, after])

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertTrue(facts.isEmpty)
        XCTAssertEqual(trace.changeFacts, facts)
    }

    func testCaptureBackedElementsChangedFactCarriesSourceEdgeAndDerivesFromTrace() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash
        )
        let trace = AccessibilityTrace(captures: [before, after])

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(facts.map(\.kind), [.elementsChanged])
        try assertFactsDeriveFromCaptureEdge(facts, trace: trace)
    }

    func testCaptureBackedFallbackScreenFactsCarrySourceEdgeAndDeriveFromTransition() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(fallbackReason: .primaryHeaderChanged)
        )
        let trace = AccessibilityTrace(captures: [before, after])

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(after.transition.fallbackReason, .primaryHeaderChanged)
        XCTAssertEqual(facts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
        try assertFactsDeriveFromCaptureEdge(facts, trace: trace)
    }

    func testFallbackScreenClassificationOutranksIncidentalElementNotification() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(
                fallbackReason: .primaryHeaderChanged,
                accessibilityNotifications: [notification(kind: .elementChanged(.layout), sequence: 1)]
            )
        )

        XCTAssertEqual(
            AccessibilityTrace.ChangeFact.between(before, after).map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    func testScreenChangedNotificationWinsWhenSettledSnapshotIsUnchanged() throws {
        let notification = notification(kind: .screenChanged, sequence: 1)
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Menu"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(
                accessibilityNotifications: [notification]
            )
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        XCTAssertNil(after.transition.fallbackReason)
        XCTAssertEqual(facts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
        guard case .screenChanged(let payload) = facts[1] else {
            return XCTFail("Expected screenChanged from the scoped screenChanged notification")
        }
        XCTAssertEqual(payload.metadata.accessibilityNotifications, [notification])
        XCTAssertEqual(
            try JSONDecoder().decode([AccessibilityTrace.ChangeFact].self, from: JSONEncoder().encode(facts)),
            facts
        )
    }

    /// An `observationGeneration` bump is a boundary signal in its own right —
    /// no fallback reason, no notification, just a new generation. This is the
    /// only coverage of that signal.
    func testObservationGenerationBumpClassifiesAsScreenChange() throws {
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: makeInterface(label: "Menu"),
            context: AccessibilityTrace.Context(observationGeneration: 4)
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            context: AccessibilityTrace.Context(observationGeneration: 5)
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(facts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
        guard case .elementsChanged(let departure) = facts[0],
              case .elementsChanged(let arrival) = facts[2]
        else {
            return XCTFail("Expected the boundary to be bracketed by departure and arrival")
        }
        // No element identity survives a replacement, so the whole old graph
        // departed and the whole new graph arrived.
        XCTAssertEqual(departure.disappeared.map(\.path), before.interface.graph.nodesInPathOrder.map(\.path))
        XCTAssertEqual(departure.appeared, [])
        XCTAssertEqual(arrival.appeared.map(\.path), after.interface.graph.nodesInPathOrder.map(\.path))
        XCTAssertEqual(arrival.disappeared, [])
    }

    func testLayoutChangedNotificationProducesNotificationOnlyElementFact() throws {
        let notification = notification(kind: .elementChanged(.layout), sequence: 1)
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Menu"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(
                accessibilityNotifications: [notification]
            )
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        guard let fact = facts.single, case .elementsChanged(let payload) = fact else {
            return XCTFail("Expected notification-only elementsChanged fact")
        }
        XCTAssertEqual(after.transition.accessibilityNotifications, [notification])
        XCTAssertTrue(payload.isNotificationOnly)
        XCTAssertEqual(payload.metadata.accessibilityNotifications, [notification])
        XCTAssertEqual(
            try JSONDecoder().decode([AccessibilityTrace.ChangeFact].self, from: JSONEncoder().encode(facts)),
            facts
        )
    }

    func testValueChangedNotificationProducesNotificationOnlyElementFactWithoutValueDiff() throws {
        let notification = notification(kind: .elementChanged(.value), sequence: 1)
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Volume"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Volume"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [notification])
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        guard let fact = facts.single, case .elementsChanged(let payload) = fact else {
            return XCTFail("Expected notification-only elementsChanged fact")
        }
        XCTAssertEqual(after.transition.accessibilityNotifications, [notification])
        XCTAssertTrue(payload.isNotificationOnly)
    }

    func testAnnouncementDoesNotMasqueradeAsElementChangeEvidence() throws {
        let notification = notification(kind: .announcement, sequence: 1)
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Menu"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(
                accessibilityNotifications: [notification]
            )
        )

        XCTAssertTrue(AccessibilityTrace.ChangeFact.between(before, after).isEmpty)
    }

    func testUIKitValueSignalsAllConfirmChangesByRereadingAccessibilityValue() throws {
        for kind in [
            AccessibilityNotificationKind.elementChanged(.value),
            .elementChanged(.layout),
            .announcement,
        ] {
            let evidence = notification(kind: kind, sequence: 1)
            let before = AccessibilityTrace.Capture(
                sequence: 1,
                interface: makeTestInterface(elements: [
                    makeElement(label: "Volume", value: "50%", traits: [.adjustable]),
                ])
            )
            let after = AccessibilityTrace.Capture(
                sequence: 2,
                interface: makeTestInterface(elements: [
                    makeElement(label: "Volume", value: "75%", traits: [.adjustable]),
                ]),
                parentHash: before.hash,
                transition: AccessibilityTrace.Transition(accessibilityNotifications: [evidence])
            )

            let facts = AccessibilityTrace.ChangeFact.between(before, after)
            let update = try XCTUnwrap(facts.testElementEdits.updated.single)

            XCTAssertEqual(update.before.value, "50%", "notification: \(kind)")
            XCTAssertEqual(update.after.value, "75%", "notification: \(kind)")
            let expectedNotifications: [AccessibilityNotificationEvidence]
            if case .elementChanged = kind {
                expectedNotifications = [evidence]
            } else {
                expectedNotifications = []
            }
            XCTAssertEqual(facts.first?.metadata.accessibilityNotifications, expectedNotifications)
        }
    }

    func testCaptureContextOnlyDiffsAsElementsChanged() throws {
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

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        guard let fact = facts.single, case .elementsChanged(let payload) = fact else {
            return XCTFail("Expected elementsChanged for capture context change")
        }
        XCTAssertFalse(payload.hasLifecycleOrUpdateFacts)
        XCTAssertTrue(payload.metadata.interactionDigest?.firstResponderChanged == true)
    }
}
