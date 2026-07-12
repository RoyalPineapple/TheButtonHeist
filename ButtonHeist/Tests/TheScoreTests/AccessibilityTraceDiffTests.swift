import XCTest
import ButtonHeistTestSupport
import ThePlans
import AccessibilitySnapshotModel
@testable import TheScore

private extension Collection where Element == AccessibilityTrace.ChangeFact {
    var testElementEdits: ElementEdits {
        ElementEdits(updated: compactMap { fact -> [ElementUpdate]? in
            guard case .elementsChanged(let payload) = fact else { return nil }
            return payload.updated
        }.flatMap { $0 })
    }

    var testTransient: [HeistElement] {
        flatMap(\.metadata.transient)
    }

    var testCaptureEdge: AccessibilityTrace.CaptureEdge? {
        first?.metadata.captureEdge
    }

    var testInteractionDigest: AccessibilityTrace.InteractionDigest? {
        first?.metadata.interactionDigest
    }

    var testAppearedLabels: [String] {
        flatMap { fact -> [AccessibilityTrace.InterfaceChangeNode] in
            guard case .elementsChanged(let payload) = fact else { return [] }
            return payload.appeared
        }.compactMap(\.elementLabel)
    }

    var testDisappearedLabels: [String] {
        flatMap { fact -> [AccessibilityTrace.InterfaceChangeNode] in
            guard case .elementsChanged(let payload) = fact else { return [] }
            return payload.disappeared
        }.compactMap(\.elementLabel)
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
        let facts = captureFacts(before: beforeInterface, after: afterInterface)
        XCTAssertEqual(facts.testElementEdits, ElementEdits.between(before, after))
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

        let facts = captureFacts(before: before, after: after)
        guard let fact = facts.single, case .elementsChanged(let elements) = fact else {
            return XCTFail("Expected one elementsChanged fact")
        }
        XCTAssertEqual(elements.disappeared.compactMap(\.elementLabel), ["Menu"])
        XCTAssertEqual(elements.appeared.compactMap(\.elementLabel), ["Checkout"])
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

    func testTreeOnlyReorderCanRemainNoChangeButDigestPreservesStableElementSet() throws {
        let first = makeElement(label: "Pasta", traits: [.button])
        let second = makeElement(label: "Sauce", traits: [.button])
        let before = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "list", children: [
                testElement(first),
                testElement(second),
            ]),
        ])
        let after = makeTestInterface(nodes: [
            testContainer(makeContainer(), containerName: "list", children: [
                testElement(second),
                testElement(first),
            ]),
        ])

        let facts = captureFacts(before: before, after: after)

        XCTAssertTrue(facts.isEmpty)
        let beforeCapture = AccessibilityTrace.Capture(sequence: 1, interface: before)
        let afterCapture = AccessibilityTrace.Capture(sequence: 2, interface: after)
        let digest = AccessibilityTrace.InteractionDigest(between: beforeCapture, and: afterCapture)
        XCTAssertEqual(digest.nodeCountBefore, 3)
        XCTAssertEqual(digest.nodeCountAfter, 3)
        XCTAssertFalse(digest.nodeCountChanged)
        XCTAssertFalse(digest.elementSetChanged)
    }

    func testFooterIdentitySwapDoesNotCollapseToNoChangeWhenElementCountMatches() throws {
        let before = makeTestInterface(elements: [
            makeElement(label: "Bagel", traits: [.button]),
            makeElement(label: "Charge $0.00", identifier: "FooterButton.Charge", traits: [.button]),
        ])
        let after = makeTestInterface(elements: [
            makeElement(label: "Bagel", traits: [.button]),
            makeElement(label: "Review sale 1 item", identifier: "FooterButton.ReviewSale", traits: [.button]),
        ])

        let facts = captureFacts(before: before, after: after)

        let digest = try XCTUnwrap(facts.testInteractionDigest)
        XCTAssertEqual(digest.nodeCountBefore, 2)
        XCTAssertEqual(digest.nodeCountAfter, 2)
        XCTAssertFalse(digest.nodeCountChanged)
        XCTAssertTrue(digest.elementSetChanged)
        XCTAssertEqual(facts.testDisappearedLabels, ["Charge $0.00"])
        XCTAssertEqual(facts.testAppearedLabels, ["Review sale 1 item"])
    }

    func testTraceIdentityPairsElementAcrossLabelAndIdentifierChanges() throws {
        let beforeElement = makeElement(
            label: "Charge $0.00",
            value: "ready",
            identifier: "FooterButton.Charge",
            traits: [.button]
        )
        let afterElement = makeElement(
            label: "Review sale 1 item",
            value: "done",
            identifier: "FooterButton.ReviewSale",
            traits: [.button]
        )
        let before = makeTraceIdentityInterface([
            (element: makeElement(label: "Bagel", traits: [.button]), identity: "bagel"),
            (element: beforeElement, identity: "footer-action"),
        ])
        let after = makeTraceIdentityInterface([
            (element: makeElement(label: "Bagel", traits: [.button]), identity: "bagel"),
            (element: afterElement, identity: "footer-action"),
        ])

        let edits = ElementEdits.between(before, after)
        let facts = captureFacts(before: before, after: after)

        XCTAssertTrue(edits.added.isEmpty)
        XCTAssertTrue(edits.removed.isEmpty)
        let update = try XCTUnwrap(edits.updated.single)
        XCTAssertEqual(update.before.label, "Charge $0.00")
        XCTAssertEqual(update.after.label, "Review sale 1 item")
        XCTAssertEqual(update.changes.map(\.property), [.label, .identifier, .value])
        XCTAssertEqual(facts.testElementEdits, edits)
        XCTAssertFalse(try XCTUnwrap(facts.testInteractionDigest).elementSetChanged)
    }

    func testTraceIdentityReportsLabelOnlyChangeAsElementUpdate() throws {
        let beforeElement = makeElement(label: "Total", traits: [.staticText])
        let afterElement = makeElement(label: "Total $12.00", traits: [.staticText])
        let before = makeTraceIdentityInterface([
            (element: beforeElement, identity: "total-label"),
        ])
        let after = makeTraceIdentityInterface([
            (element: afterElement, identity: "total-label"),
        ])

        let edits = ElementEdits.between(before, after)
        let facts = captureFacts(before: before, after: after)

        XCTAssertTrue(edits.added.isEmpty)
        XCTAssertTrue(edits.removed.isEmpty)
        let update = try XCTUnwrap(edits.updated.single)
        XCTAssertEqual(update.changes.map(\.property), [.label])
        XCTAssertEqual(update.changes.first?.oldValue, .text("Total"))
        XCTAssertEqual(update.changes.first?.newValue, .text("Total $12.00"))
        XCTAssertEqual(facts.map(\.kind), [.elementsChanged])
    }

    func testDifferentTraceIdentitiesDoNotFallBackToContentPairing() {
        let beforeElement = makeElement(label: "Continue", value: "ready", traits: [.button])
        let afterElement = makeElement(label: "Continue", value: "done", traits: [.button])
        let before = makeTraceIdentityInterface([
            (element: beforeElement, identity: "before-action"),
        ])
        let after = makeTraceIdentityInterface([
            (element: afterElement, identity: "after-action"),
        ])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.updated.isEmpty)
        XCTAssertEqual(edits.removed, [beforeElement])
        XCTAssertEqual(edits.added, [afterElement])
    }

    func testTraceIdentityPresenceMismatchDoesNotPair() {
        let beforeElement = makeElement(label: "Continue", value: "ready", traits: [.button])
        let afterElement = makeElement(label: "Continue", value: "done", traits: [.button])
        let before = makeTraceIdentityInterface([
            (element: beforeElement, identity: "action"),
        ])
        let after = makeTestInterface(elements: [afterElement])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.updated.isEmpty)
        XCTAssertEqual(edits.removed, [beforeElement])
        XCTAssertEqual(edits.added, [afterElement])
    }

    func testTraceIdentityDoesNotEncodeInPublicInterfaceJSON() throws {
        let interface = makeTraceIdentityInterface([
            (element: makeElement(label: "Continue", traits: [.button]), identity: "private-action-id"),
        ])

        let data = try JSONEncoder().encode(interface)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(Interface.self, from: data)

        XCTAssertFalse(json.contains("traceIdentity"))
        XCTAssertFalse(json.contains("private-action-id"))
        XCTAssertEqual(decoded, interface)
        XCTAssertNil(decoded.projectedElementRecords.single?.traceIdentity)
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

    func testCaptureBackedScreenChangedFactsCarrySourceEdgeAndDeriveFromTransition() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(fallbackReason: .primaryHeaderChanged)
        )
        let trace = AccessibilityTrace(captures: [before, after])

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(facts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
        try assertFactsDeriveFromCaptureEdge(facts, trace: trace)
    }

    func testScreenChangedNotificationWinsWhenScreenIdentityIsUnchanged() throws {
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
        guard case .screenChanged(let payload) = facts[1] else {
            return XCTFail("Expected screenChanged from the scoped screenChanged notification")
        }
        XCTAssertEqual(payload.metadata.accessibilityNotifications, [notification])
        XCTAssertEqual(
            try JSONDecoder().decode([AccessibilityTrace.ChangeFact].self, from: JSONEncoder().encode(facts)),
            facts
        )
    }

    func testObservationGenerationBoundaryCannotProduceElementUpdates() {
        let beforeInterface = makeTestInterface(elements: [
            makeElement(label: "Quantity", value: "1", traits: [.adjustable]),
        ])
        let afterInterface = makeTestInterface(elements: [
            makeElement(label: "Quantity", value: "2", traits: [.adjustable]),
        ])
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: beforeInterface,
            context: AccessibilityTrace.Context(screenId: "checkout", observationGeneration: 7)
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(screenId: "checkout", observationGeneration: 8)
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(facts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
        XCTAssertTrue(facts.testElementEdits.updated.isEmpty)
        XCTAssertEqual(facts.testDisappearedLabels, ["Quantity"])
        XCTAssertEqual(facts.testAppearedLabels, ["Quantity"])
    }

    func testLayoutChangedNotificationProducesNotificationOnlyElementFact() throws {
        let notification = notification(kind: .layoutChanged, sequence: 1)
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
        let notification = notification(kind: .valueChanged, sequence: 1)
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

    func testScreenAppearanceFallbackPrecedesValueChangedNotification() {
        let notification = notification(kind: .valueChanged, sequence: 1)
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Volume"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Volume"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(
                fallbackReason: .primaryHeaderChanged,
                accessibilityNotifications: [notification]
            )
        )

        XCTAssertEqual(
            AccessibilityTrace.ChangeFact.between(before, after).map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    func testAnnouncementProducesElementChangeEvidenceForUIKitValueControls() {
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

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        guard let fact = facts.single, case .elementsChanged(let payload) = fact else {
            return XCTFail("Expected announcement-backed elementsChanged fact")
        }
        XCTAssertEqual(payload.metadata.accessibilityNotifications, [notification])
    }

    func testUIKitValueSignalsAllConfirmChangesByRereadingAccessibilityValue() throws {
        for kind in [
            AccessibilityNotificationKind.valueChanged,
            .layoutChanged,
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
            XCTAssertEqual(facts.first?.metadata.accessibilityNotifications, [evidence])
        }
    }

    func testTransitionTransientLivesOnCaptureEdgeAndProjectsToFactMetadata() throws {
        let transient = makeElement(label: "Loading", traits: [.staticText])
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(transient: [transient])
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(after.transition.transient, [transient])
        XCTAssertEqual(facts.testTransient, [transient])
        XCTAssertEqual(facts.testCaptureEdge?.before.hash, before.hash)
        XCTAssertEqual(facts.testCaptureEdge?.after.hash, after.hash)
    }

    func testTransitionTransientProducesFactWhenSettledSnapshotsAreIdentical() {
        let transient = makeElement(label: "Loading", traits: [.staticText])
        let interface = makeInterface(label: "Menu")
        let before = AccessibilityTrace.Capture(sequence: 1, interface: interface)
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(transient: [transient])
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        guard let fact = facts.single, case .elementsChanged(let payload) = fact else {
            return XCTFail("Expected transient-backed elementsChanged fact")
        }
        XCTAssertEqual(payload.metadata.transient, [transient])
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

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        guard let fact = facts.single, case .elementsChanged(let payload) = fact else {
            return XCTFail("Expected elementsChanged for capture context change")
        }
        XCTAssertFalse(payload.hasLifecycleOrUpdateFacts)
        XCTAssertTrue(payload.metadata.interactionDigest?.firstResponderChanged == true)
    }

    func testGeometryOnlyMovementKeepsSemanticCaptureStableUnlessGeometryIncluded() throws {
        let beforeInterface = makeTestInterface(elements: [
            makeElement(
                label: "Checkout",
                traits: [.button],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                activationPointX: 50,
                activationPointY: 22
            ),
        ])
        let afterInterface = makeTestInterface(elements: [
            makeElement(
                label: "Checkout",
                traits: [.button],
                frameX: 10,
                frameY: 20,
                frameWidth: 100,
                frameHeight: 44,
                activationPointX: 60,
                activationPointY: 42
            ),
        ])
        let before = AccessibilityTrace.Capture(sequence: 1, interface: beforeInterface)
        let after = AccessibilityTrace.Capture(sequence: 2, interface: afterInterface, parentHash: before.hash)

        XCTAssertEqual(before.hash, after.hash)
        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        guard let fact = facts.single, case .elementsChanged(let payload) = fact else {
            return XCTFail("Expected canonical elementsChanged fact")
        }
        let properties = try XCTUnwrap(payload.updated.single?.changes.map(\.property))
        XCTAssertEqual(properties, [.frame, .activationPoint])
    }

    func testGeometryOnlyMovementFeedsCanonicalPredicates() {
        let beforeInterface = makeTestInterface(elements: [
            makeElement(
                label: "Checkout",
                traits: [.button],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 44,
                activationPointX: 50,
                activationPointY: 22
            ),
        ])
        let afterInterface = makeTestInterface(elements: [
            makeElement(
                label: "Checkout",
                traits: [.button],
                frameX: 10,
                frameY: 20,
                frameWidth: 100,
                frameHeight: 44,
                activationPointX: 60,
                activationPointY: 42
            ),
        ])
        let trace = AccessibilityTrace(first: beforeInterface).appending(afterInterface)
        guard let evidence = PredicateEvaluationEvidence(trace: trace, isComplete: true) else {
            return XCTFail("Expected predicate evidence")
        }
        let framePredicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(
                .label("Checkout"),
                .frame(after: ElementFrameMatch(x: 10, y: 20, width: 100, height: 44))
            ),
        ]))
        let semanticPredicate = AccessibilityPredicate<RootContext>.changed(.elements([
            .updated(.label("Checkout"), .value(after: "Moved")),
        ]))

        XCTAssertTrue(framePredicate.evaluate(in: evidence).met)
        XCTAssertFalse(semanticPredicate.evaluate(in: evidence).met)
    }

    func testActivationPointEvidencePreservesDefaultExplicitAndUnavailable() {
        let defaultElement = makeAccessibilityElement(
            activationPoint: AccessibilityPoint(x: 0, y: 0),
            usesDefaultActivationPoint: true
        )
        let explicitElement = makeAccessibilityElement(
            activationPoint: AccessibilityPoint(x: 12, y: 34),
            usesDefaultActivationPoint: false
        )
        let unavailableElement = makeAccessibilityElement(
            activationPoint: AccessibilityPoint(x: .nan, y: .infinity),
            usesDefaultActivationPoint: false
        )

        let defaultProjection = HeistElement(accessibilityElement: defaultElement)
        let explicitProjection = HeistElement(accessibilityElement: explicitElement)
        let unavailableProjection = HeistElement(accessibilityElement: unavailableElement)

        XCTAssertEqual(
            defaultProjection.activationPointEvidence,
            .defaultCenter(ScreenPoint(x: 50, y: 22))
        )
        XCTAssertEqual(
            explicitProjection.activationPointEvidence,
            .explicit(ScreenPoint(x: 12, y: 34))
        )
        XCTAssertEqual(unavailableProjection.activationPointEvidence.source, .unavailable)
        XCTAssertNil(unavailableProjection.activationPointEvidence.point)
        XCTAssertNil(ActivationPointProperty.value(in: unavailableProjection))
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

        XCTAssertEqual(
            AccessibilityTrace.ChangeFact.between(before, after).map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    func testInteractionDigestReportsScreenAndFirstResponderChanges() throws {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(
                firstResponder: .predicate(ElementPredicateTemplate(label: "Email")),
                screenId: "login"
            )
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(
                firstResponder: .predicate(ElementPredicateTemplate(label: "Password")),
                screenId: "signup"
            )
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        let digest = try XCTUnwrap(facts.testInteractionDigest)

        XCTAssertTrue(digest.screenIdChanged)
        XCTAssertEqual(digest.screenIdBefore, "login")
        XCTAssertEqual(digest.screenIdAfter, "signup")
        XCTAssertTrue(digest.firstResponderChanged)
        XCTAssertFalse(digest.elementSetChanged)
    }

    func testInteractionDigestTreatsKeyboardVisibilityChangeAsFirstResponderChange() throws {
        let interface = makeInterface()
        let firstResponder = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Search"))
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: interface,
            context: AccessibilityTrace.Context(
                firstResponder: firstResponder,
                keyboardVisible: false,
                screenId: "library"
            )
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(
                firstResponder: firstResponder,
                keyboardVisible: true,
                screenId: "library"
            )
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        let digest = try XCTUnwrap(facts.testInteractionDigest)

        XCTAssertTrue(digest.firstResponderChanged)
        XCTAssertFalse(digest.screenIdChanged)
        XCTAssertFalse(digest.elementSetChanged)
    }

    func testCaptureChainMetadataDoesNotAffectDiff() {
        let interface = makeInterface()
        let before = AccessibilityTrace.Capture(sequence: 1, interface: interface, parentHash: nil)
        let after = AccessibilityTrace.Capture(sequence: 99, interface: interface, parentHash: "sha256:parent")

        XCTAssertTrue(AccessibilityTrace.ChangeFact.between(before, after).isEmpty)
    }

    func testElementDiffTreatsIndistinguishableElementsAsNoChangeWithoutHierarchyContext() {
        let before = makeElement(label: "Item", traits: [.staticText])
        let after = makeElement(label: "Item", traits: [.staticText])

        let edits = ElementEdits.between(before, after)

        XCTAssertTrue(edits.isEmpty)
    }

    func testDiffPairingKeyUsesTypedIdentityTraitSet() {
        let orderedTraits = makeElement(label: "Favorite", traits: [.button, .header])
        let reorderedTraits = makeElement(label: "Favorite", traits: [.header, .button])
        let transientStateTrait = makeElement(label: "Favorite", traits: [.selected, .header, .button])
        let differentIdentityTrait = makeElement(label: "Favorite", traits: [.selected, .staticText])
        let identified = makeElement(label: "Favorite", identifier: "favorite.button", traits: [.button])

        XCTAssertEqual(orderedTraits.diffPairingKey, reorderedTraits.diffPairingKey)
        XCTAssertEqual(orderedTraits.diffPairingKey, transientStateTrait.diffPairingKey)
        XCTAssertEqual(orderedTraits.diffPairingKey.identityTraits, Set<HeistTrait>([.button, .header]))
        XCTAssertNotEqual(orderedTraits.diffPairingKey, differentIdentityTrait.diffPairingKey)
        XCTAssertEqual(identified.diffPairingKey.text, "favorite.button")
    }

    func testTypedDiffEqualityUsesDomainValues() throws {
        XCTAssertNil(projectElementStateChange(
            old: makeElement(label: "Favorite", traits: [.button, .selected]),
            new: makeElement(label: "Favorite", traits: [.selected, .button])
        ))

        XCTAssertNil(projectElementStateChange(
            old: makeElement(label: "Row", traits: [.button], actions: [.activate, .custom("Share")]),
            new: makeElement(label: "Row", traits: [.button], actions: [.custom("Share"), .activate, .activate])
        ))
        XCTAssertEqual(
            ElementPropertyValue.actions([.custom("Share"), .activate]),
            ElementPropertyValue.actions([.activate, .custom("Share"), .activate])
        )

        XCTAssertNil(projectElementStateChange(
            old: makeElement(label: "Document", traits: [.staticText], customContent: nil),
            new: makeElement(label: "Document", traits: [.staticText], customContent: [])
        ))

        XCTAssertNil(projectElementStateChange(
            old: makeElement(label: "Document", traits: [.staticText], rotors: nil),
            new: makeElement(label: "Document", traits: [.staticText], rotors: [])
        ))
    }

    func testTypedDiffRendersTraitsActionsRotorsAndCustomContent() throws {
        let traits = try XCTUnwrap(singleChange(
            property: .traits,
            old: makeElement(label: "Favorite", traits: [.button]),
            new: makeElement(label: "Favorite", traits: [.button, .selected])
        ))
        XCTAssertEqual(traits.oldValue, .traits([.button]))
        XCTAssertEqual(traits.newValue, .traits([.button, .selected]))
        XCTAssertEqual(traits.oldDisplayText, "button")
        XCTAssertEqual(traits.newDisplayText, "button, selected")

        let actions = try XCTUnwrap(singleChange(
            property: .actions,
            old: makeElement(label: "Row", traits: [.button], actions: [.activate]),
            new: makeElement(label: "Row", traits: [.button], actions: [.activate, .custom("Share")])
        ))
        XCTAssertEqual(actions.oldValue, .actions([.activate]))
        XCTAssertEqual(actions.newValue, .actions([.activate, .custom("Share")]))
        XCTAssertEqual(actions.oldDisplayText, "activate")
        XCTAssertEqual(actions.newDisplayText, "activate, Share")

        let rotors = try XCTUnwrap(singleChange(
            property: .rotors,
            old: makeElement(label: "Editor", traits: [.textArea], rotors: [HeistRotor(name: "Headings")]),
            new: makeElement(
                label: "Editor",
                traits: [.textArea],
                rotors: [HeistRotor(name: "Headings"), HeistRotor(name: "Errors")]
            )
        ))
        XCTAssertEqual(rotors.oldValue, .rotors([HeistRotor(name: "Headings")]))
        XCTAssertEqual(rotors.newValue, .rotors([HeistRotor(name: "Headings"), HeistRotor(name: "Errors")]))
        XCTAssertEqual(rotors.oldDisplayText, "Headings")
        XCTAssertEqual(rotors.newDisplayText, "Headings, Errors")

        let customContent = try XCTUnwrap(singleChange(
            property: .customContent,
            old: makeElement(
                label: "File",
                traits: [.staticText],
                customContent: [HeistCustomContent(label: "Size", value: "2.4 MB", isImportant: false)]
            ),
            new: makeElement(
                label: "File",
                traits: [.staticText],
                customContent: [
                    HeistCustomContent(label: "Size", value: "3.1 MB", isImportant: false),
                    HeistCustomContent(label: "State", value: "Featured", isImportant: true),
                ]
            )
        ))
        XCTAssertEqual(customContent.oldDisplayText, "Size: 2.4 MB")
        XCTAssertEqual(customContent.newDisplayText, "Size: 3.1 MB; State: Featured")
    }

    func testTypedDiffRendersFrameAndActivationPoint() throws {
        let frame = try XCTUnwrap(singleChange(
            property: .frame,
            old: makeElement(
                label: "Box",
                traits: [.staticText],
                frameX: 0,
                frameY: 0,
                frameWidth: 100,
                frameHeight: 50
            ),
            new: makeElement(
                label: "Box",
                traits: [.staticText],
                frameX: 10,
                frameY: 20,
                frameWidth: 100,
                frameHeight: 50
            )
        ))
        XCTAssertEqual(frame.oldValue, .frame(ElementPropertyFrame(x: 0, y: 0, width: 100, height: 50)))
        XCTAssertEqual(frame.newValue, .frame(ElementPropertyFrame(x: 10, y: 20, width: 100, height: 50)))
        XCTAssertEqual(frame.oldDisplayText, "0,0,100,50")
        XCTAssertEqual(frame.newDisplayText, "10,20,100,50")

        let activationPoint = try XCTUnwrap(singleChange(
            property: .activationPoint,
            old: makeElement(
                label: "Button",
                traits: [.button],
                activationPointX: 50,
                activationPointY: 25
            ),
            new: makeElement(
                label: "Button",
                traits: [.button],
                activationPointX: 75,
                activationPointY: 40
            )
        ))
        XCTAssertEqual(activationPoint.oldValue, .activationPoint(ElementPropertyPoint(x: 50, y: 25)))
        XCTAssertEqual(activationPoint.newValue, .activationPoint(ElementPropertyPoint(x: 75, y: 40)))
        XCTAssertEqual(activationPoint.oldDisplayText, "50,25")
        XCTAssertEqual(activationPoint.newDisplayText, "75,40")
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

    private func makeTraceIdentityInterface(
        _ elements: [(element: HeistElement, identity: String)],
        timestamp: Date = Date(timeIntervalSince1970: 0)
    ) -> Interface {
        let tree = elements.enumerated().map { index, entry in
            AccessibilityHierarchy.element(makeTestAccessibilityElement(entry.element), traversalIndex: index)
        }
        let annotations = elements.enumerated().map { index, entry in
            InterfaceElementAnnotation(
                path: TreePath([index]),
                actions: entry.element.actions
            )
        }
        let traceIdentities = Dictionary(uniqueKeysWithValues: elements.enumerated().map { index, entry in
            (TreePath([index]), TraceElementIdentity(entry.identity))
        })
        return Interface(
            timestamp: timestamp,
            tree: tree,
            annotations: InterfaceAnnotations(elements: annotations),
            traceIdentities: InterfaceTraceIdentities(traceIdentities)
        )
    }

    private func makeContainer() -> AccessibilityContainer {
        makeTestAccessibilityContainer()
    }

    private func makeElement(
        label: String,
        value: String? = nil,
        identifier: String? = nil,
        hint: String? = nil,
        traits: [HeistTrait],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 100,
        frameHeight: Double = 44,
        activationPointX: Double? = nil,
        activationPointY: Double? = nil,
        customContent: [HeistCustomContent]? = nil,
        rotors: [HeistRotor]? = nil,
        actions: [ElementAction] = []
    ) -> HeistElement {
        HeistElement(
            description: label,
            label: label,
            value: value,
            identifier: identifier,
            hint: hint,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointX: activationPointX,
            activationPointY: activationPointY,
            customContent: customContent,
            rotors: rotors,
            actions: actions
        )
    }

    private func makeAccessibilityElement(
        activationPoint: AccessibilityPoint,
        usesDefaultActivationPoint: Bool
    ) -> AccessibilityElement {
        AccessibilityElement(
            description: "Checkout",
            label: "Checkout",
            value: nil,
            traits: AccessibilityTraits.fromNames([HeistTrait.button.rawValue]),
            identifier: nil,
            hint: nil,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(x: 0, y: 0, width: 100, height: 44)),
            activationPoint: activationPoint,
            usesDefaultActivationPoint: usesDefaultActivationPoint,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: true
        )
    }

    private func singleChange(
        property: ElementProperty,
        old: HeistElement,
        new: HeistElement
    ) -> PropertyChange? {
        projectElementStateChange(old: old, new: new)?
            .changes
            .first { $0.property == property }
    }

    private func assertFactsDeriveFromCaptureEdge(
        _ facts: [AccessibilityTrace.ChangeFact],
        trace: AccessibilityTrace,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let edge = try XCTUnwrap(facts.testCaptureEdge, "Facts did not carry capture edge", file: file, line: line)
        let before = try XCTUnwrap(
            trace.capture(ref: edge.before),
            "Trace did not contain before ref",
            file: file,
            line: line
        )
        let after = try XCTUnwrap(
            trace.capture(ref: edge.after),
            "Trace did not contain after ref",
            file: file,
            line: line
        )

        XCTAssertEqual(edge.before.hash, before.hash, file: file, line: line)
        XCTAssertEqual(edge.after.hash, after.hash, file: file, line: line)
        XCTAssertEqual(facts, AccessibilityTrace.ChangeFact.between(before, after), file: file, line: line)
    }

    private func captureFacts(
        before beforeInterface: Interface,
        after afterInterface: Interface,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [AccessibilityTrace.ChangeFact] {
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: beforeInterface
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterInterface,
            parentHash: before.hash
        )
        let facts = AccessibilityTrace.ChangeFact.between(before, after)
        if !facts.isEmpty {
            XCTAssertNotNil(facts.testCaptureEdge, file: file, line: line)
        }
        return facts
    }

    private func notification(
        kind: AccessibilityNotificationKind,
        sequence: UInt64
    ) -> AccessibilityNotificationEvidence {
        AccessibilityNotificationEvidence(
            sequence: sequence,
            kind: kind,
            timestamp: Date(timeIntervalSince1970: TimeInterval(sequence)),
            notificationData: .none,
            associatedElement: .none
        )
    }

}

private extension Array {
    var single: Element? {
        count == 1 ? self[0] : nil
    }
}

private extension AccessibilityTrace.InterfaceChangeNode {
    var elementLabel: String? {
        guard case .element(let element, _) = node else { return nil }
        return element.label
    }
}
