import XCTest
import ButtonHeistTestSupport
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

    func testDecodeRejectsTheOldStringlyScreenChangeReason() {
        let json = #"{"screenChangeReason":"primaryHeaderChanged"}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(AccessibilityTrace.Transition.self, from: Data(json.utf8))
        )
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
                fallbackReason: .primaryHeaderChanged,
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
            activationPointEvidence: .unavailable,
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
                fallbackReason: .primaryHeaderChanged,
                transient: [transient]
            )
        )

        XCTAssertEqual(trace.captures[1].transition.fallbackReason, .primaryHeaderChanged)
        XCTAssertEqual(trace.captures[1].transition.transient, [transient])
        XCTAssertEqual(trace.captures[1].parentHash, trace.captures[0].hash)
    }

    func testTransitionCarriesOrderedAccessibilityNotificationsAsProductEvidence() throws {
        let targetReference = AccessibilityNotificationElementReference(
            path: TreePath([0]),
            traversalIndex: 0,
            resolution: .identity
        )
        let notifications = [
            AccessibilityNotificationEvidence(
                sequence: 7,
                kind: .elementChanged(.layout),
                timestamp: Date(timeIntervalSince1970: 7),
                notificationData: .unresolvedObject(AccessibilityNotificationObjectPayload(
                    className: "UICollectionView",
                    summary: "object(class=UICollectionView description=Shipping options changed)"
                )),
                associatedElement: .element(targetReference)
            ),
            AccessibilityNotificationEvidence(
                sequence: 8,
                kind: .screenChanged,
                timestamp: Date(timeIntervalSince1970: 8),
                notificationData: .string("Checkout"),
                associatedElement: .none
            ),
        ]
        let capture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: "sha256:before",
            transition: AccessibilityTrace.Transition(accessibilityNotifications: notifications)
        )

        let data = try JSONEncoder().encode(capture)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("accessibilityNotifications"))
        XCTAssertTrue(json.contains("Shipping options changed"))
        XCTAssertTrue(json.contains("Checkout"))

        let decoded = try JSONDecoder().decode(AccessibilityTrace.Capture.self, from: data)
        XCTAssertEqual(decoded.transition.accessibilityNotifications, notifications)
        XCTAssertEqual(
            decoded.transition.accessibilityNotifications.map(\.kind),
            [.elementChanged(.layout), .screenChanged]
        )
    }

    func testNotificationEvidenceUsesCanonicalNestedIdentity() throws {
        let kinds: [AccessibilityNotificationKind] = [
            .screenChanged,
            .elementChanged(.layout),
            .elementChanged(.value),
            .announcement,
        ]
        let notifications = kinds.enumerated().map { offset, kind in
            AccessibilityNotificationEvidence(
                sequence: UInt64(offset + 1),
                kind: kind,
                timestamp: Date(timeIntervalSince1970: TimeInterval(offset + 1)),
                notificationData: .none,
                associatedElement: .none
            )
        }

        let data = try JSONEncoder().encode(notifications)
        let decoded = try JSONDecoder().decode([AccessibilityNotificationEvidence].self, from: data)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        XCTAssertEqual(decoded.map(\.kind), kinds)
        XCTAssertEqual(
            json.compactMap { ($0["kind"] as? [String: Any])?["type"] as? String },
            ["screenChanged", "elementChanged", "elementChanged", "announcement"]
        )
        XCTAssertEqual(
            json.compactMap { ($0["kind"] as? [String: Any])?["notification"] as? String },
            ["layout", "value"]
        )
        XCTAssertTrue(json.allSatisfy { $0["rawCode"] == nil })
    }

    func testUnknownNotificationEvidencePreservesRawCodeAndPayload() throws {
        let notification = AccessibilityNotificationEvidence(
            sequence: 9,
            kind: .unknown(4002),
            timestamp: Date(timeIntervalSince1970: 9),
            notificationData: .string("private notification"),
            associatedElement: .unresolvedObject(AccessibilityNotificationObjectPayload(
                className: "NSObject",
                summary: "payload summary"
            ))
        )

        let data = try JSONEncoder().encode(notification)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(AccessibilityNotificationEvidence.self, from: data)

        let kind = try XCTUnwrap(json["kind"] as? [String: Any])
        XCTAssertEqual(kind["type"] as? String, "unknown")
        XCTAssertEqual(kind["rawCode"] as? Int, 4002)
        XCTAssertNil(json["rawCode"])
        XCTAssertEqual(decoded, notification)
    }

    func testNotificationPayloadRejectsFieldsFromOtherVariants() {
        let json = #"{"type":"none","value":"Hello"}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(AccessibilityNotificationPayload.self, from: Data(json.utf8))
        ) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(
                context.debugDescription,
                "none accessibility notification payload must not include value"
            )
        }
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

    func testFallbackReasonProjectsScreenBoundaryFacts() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeInterface(label: "Menu"))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeInterface(label: "Checkout"),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(fallbackReason: .primaryHeaderChanged)
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(facts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
    }

    func testFallbackReasonOverridesStructuralChange() throws {
        let before = AccessibilityTrace.Capture(sequence: 1, interface: makeListInterface(["Antipasti"]))
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: makeListInterface(["Antipasti", "Pasta"]),
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(fallbackReason: .primaryHeaderChanged)
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(facts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
    }

    func testScreenIdChangeProjectsScreenBoundaryFacts() throws {
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

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(facts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
    }

    func testSameScreenContextChangeProjectsElementChangedFact() throws {
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

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(facts.count, 1)
        guard case .elementsChanged(let fact) = facts[0] else {
            return XCTFail("Expected elementsChanged fact")
        }
        XCTAssertTrue(fact.appeared.isEmpty)
        XCTAssertTrue(fact.disappeared.isEmpty)
        XCTAssertTrue(fact.updated.isEmpty)
    }

    func testNotificationOnlySameScreenChangeProjectsElementFact() throws {
        let interface = makeInterface(label: "Menu")
        let before = AccessibilityTrace.Capture(sequence: 1, interface: interface)
        let notification = AccessibilityNotificationEvidence(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 1),
            notificationData: .none,
            associatedElement: .none
        )
        let after = AccessibilityTrace.Capture(
            sequence: 2,
            interface: interface,
            parentHash: before.hash,
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [notification])
        )

        let facts = AccessibilityTrace.ChangeFact.between(before, after)

        XCTAssertEqual(facts.count, 1)
        guard case .elementsChanged(let fact) = facts[0] else {
            return XCTFail("Expected notification-only elementsChanged fact")
        }
        XCTAssertTrue(fact.appeared.isEmpty)
        XCTAssertTrue(fact.disappeared.isEmpty)
        XCTAssertTrue(fact.updated.isEmpty)
        XCTAssertEqual(fact.metadata.accessibilityNotifications, [notification])
    }

    func testScreenChangedFactWireHasNoReplacementInterface() throws {
        let fact = AccessibilityTrace.ChangeFact.screenChanged(.init(metadata: .empty))

        let data = try JSONEncoder().encode(fact)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(AccessibilityTrace.ChangeFact.self, from: data)

        XCTAssertEqual(decoded, fact)
        XCTAssertTrue(json.contains(#""kind":"screenChanged""#))
        XCTAssertFalse(json.contains("replacementInterface"))

        let staleJSON = #"{"kind":"screenChanged","metadata":{},"replacementInterface":{}}"#
        XCTAssertThrowsError(
            try JSONDecoder().decode(AccessibilityTrace.ChangeFact.self, from: Data(staleJSON.utf8))
        )
    }

    func testTraceProjectsEndpointScreenContext() throws {
        let trace = AccessibilityTrace(first: makeInterface(label: "Home")).appending(
            makeInterface(label: "Settings"),
            context: AccessibilityTrace.Context(screenId: "settings_context")
        )

        XCTAssertEqual(trace.endpointScreenName, "Settings")
        XCTAssertEqual(trace.endpointScreenId, "settings_context")
    }

    func testTraceChangeFactsPreserveIntermediateElementUpdates() throws {
        let baseline = makeInterface(label: "Counter", saveValue: "0")
        let halfway = makeInterface(label: "Counter", saveValue: "50")
        let final = makeInterface(label: "Counter", saveValue: "100")
        let trace = AccessibilityTrace(first: baseline)
            .appending(halfway)
            .appending(final)

        let updates = trace.changeFacts.flatMap { fact -> [ElementUpdate] in
            if case .elementsChanged(let payload) = fact { return payload.updated }
            return []
        }
        let valueChanges = updates.flatMap(\.changes).filter { $0.property == .value }

        XCTAssertTrue(valueChanges.contains(.value(old: "0", new: "50")))
        XCTAssertTrue(valueChanges.contains(.value(old: "50", new: "100")))
    }

    func testTraceKeepsElementFactBeforeScreenBoundaryFacts() throws {
        let baseline = makeInterface(label: "Menu", saveValue: "0")
        let updated = makeInterface(label: "Menu", saveValue: "50")
        let final = makeInterface(label: "Settings", saveValue: "50")
        let trace = AccessibilityTrace(first: baseline)
            .appending(updated)
            .appending(
                final,
                transition: AccessibilityTrace.Transition(fallbackReason: .primaryHeaderChanged)
            )

        XCTAssertEqual(
            trace.changeFacts.map(\.kind),
            [.elementsChanged, .elementsChanged, .screenChanged, .elementsChanged]
        )
        guard case .elementsChanged(let elementFact) = trace.changeFacts[0] else {
            return XCTFail("Expected the first edge to be an element fact")
        }
        XCTAssertTrue(elementFact.updated.flatMap(\.changes).contains(.value(old: "0", new: "50")))
        guard case .screenChanged = trace.changeFacts[2] else {
            return XCTFail("Expected screen marker after departure facts")
        }
    }

    func testScreenChangeEdgeDoesNotProjectElementEdits() throws {
        let baseline = makeInterface(label: "Menu", saveValue: "0")
        let final = makeInterface(label: "Settings", saveValue: "50")
        let trace = AccessibilityTrace(first: baseline).appending(
            final,
            transition: AccessibilityTrace.Transition(fallbackReason: .primaryHeaderChanged)
        )

        XCTAssertEqual(trace.changeFacts.map(\.kind), [.elementsChanged, .screenChanged, .elementsChanged])
        guard case .elementsChanged(let disappearances) = trace.changeFacts[0] else {
            return XCTFail("Expected old interface disappearance fact")
        }
        guard case .screenChanged = trace.changeFacts[1] else {
            return XCTFail("Expected screen boundary marker")
        }
        guard case .elementsChanged(let appearances) = trace.changeFacts[2] else {
            return XCTFail("Expected replacement interface appearance fact")
        }
        XCTAssertEqual(disappearances.disappeared.count, baseline.projectedElements.count)
        XCTAssertTrue(disappearances.updated.isEmpty)
        XCTAssertEqual(appearances.appeared.count, final.projectedElements.count)
        XCTAssertTrue(appearances.updated.isEmpty)
    }

    func testScreenChangeDoesNotMergeEarlierElementFacts() throws {
        let baseline = makeInterface(label: "Menu", saveValue: "0")
        let outgoingUpdate = makeInterface(label: "Menu", saveValue: "1")
        let replacement = makeInterface(label: "Settings", saveValue: "0")
        let trace = AccessibilityTrace(first: baseline)
            .appending(outgoingUpdate)
            .appending(
                replacement,
                transition: AccessibilityTrace.Transition(fallbackReason: .primaryHeaderChanged)
            )

        XCTAssertEqual(
            trace.changeFacts.map(\.kind),
            [.elementsChanged, .elementsChanged, .screenChanged, .elementsChanged]
        )
        guard case .elementsChanged(let elementFact) = trace.changeFacts[0] else {
            return XCTFail("Expected outgoing same-screen update to stay on its own edge")
        }
        XCTAssertTrue(elementFact.updated.flatMap(\.changes).contains(.value(old: "0", new: "1")))
        guard case .elementsChanged(let screenDepartures) = trace.changeFacts[1] else {
            return XCTFail("Expected screen departure fact after the outgoing update")
        }
        XCTAssertTrue(screenDepartures.updated.isEmpty)
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
