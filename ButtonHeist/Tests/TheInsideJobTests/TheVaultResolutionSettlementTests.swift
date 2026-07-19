#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheVaultResolutionTests {

    func testAccessibilityNotificationObjectIdentityRequiresLivePayload() {
        var payloadObject: NSObject? = NSObject()
        let identity = AccessibilityNotificationObjectIdentity(
            object: payloadObject!,
            className: "NSObject",
            summary: nil
        )
        payloadObject = nil

        let screenObject = NSObject()
        let observation = InterfaceObservation.makeForTests(
            elements: [(element(label: "Save", traits: .button), "save")],
            objects: ["save": screenObject]
        )
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .object(identity),
            associatedElement: .none,
            provenance: .scoped
        )

        let evidence = bagman.resolveAccessibilityNotificationEvidence([event], in: observation)

        XCTAssertEqual(
            evidence.first?.notificationData,
            .unresolvedObject(AccessibilityNotificationObjectPayload(className: "NSObject", summary: nil))
        )
    }

    func testAccessibilityNotificationObjectIdentityResolvesIntoReferenceScreen() {
        let payloadObject = NSObject()
        let source = InterfaceObservation.makeForTests([
            .init(element(label: "Old", traits: .button), heistId: "old"),
            .init(element(label: "A acid", traits: .button), heistId: "a_acid", object: payloadObject),
        ])
        let reference = InterfaceObservation.makeForTests(elements: [
            (element(label: "Section A", traits: .header), "section_a_header"),
            (element(label: "A acid", traits: .button), "a_acid"),
        ])
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .object(AccessibilityNotificationObjectIdentity(
                object: payloadObject,
                className: "NSObject",
                summary: nil
            )),
            associatedElement: .none,
            provenance: .scoped
        )

        let evidence = bagman.resolveAccessibilityNotificationEvidence(
            [event],
            identityObservation: source,
            referenceObservation: reference
        )

        guard case .element(let reference)? = evidence.first?.notificationData else {
            return XCTFail("Expected notification object to resolve into reference observation")
        }
        XCTAssertEqual(reference.path, TreePath([1]))
        XCTAssertEqual(reference.traversalIndex, 1)
    }

    func testAccessibilityNotificationReferenceUsesNestedSemanticGraphPath() {
        let payloadObject = NSObject()
        let target = element(label: "Pay", traits: .button)
        let source = InterfaceObservation.makeForTests([
            .init(target, heistId: "pay", object: payloadObject),
        ])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: nil, value: nil),
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let reference = InterfaceObservation.makeForTests(
            elements: [
                "pay": InterfaceTree.Element(heistId: "pay", scrollMembership: nil, element: target),
            ],
            hierarchy: [.container(container, children: [.element(target, traversalIndex: 0)])],
            heistIdsByPath: [TreePath([0, 0]): "pay"],
            firstResponderHeistId: nil
        )
        let event = PendingAccessibilityNotificationEvent(
            sequence: 1,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .object(AccessibilityNotificationObjectIdentity(
                object: payloadObject,
                className: "NSObject",
                summary: nil
            )),
            associatedElement: .none,
            provenance: .scoped
        )

        let evidence = bagman.resolveAccessibilityNotificationEvidence(
            [event],
            identityObservation: source,
            referenceObservation: reference
        )

        guard case .element(let resolved)? = evidence.first?.notificationData else {
            return XCTFail("Expected nested notification element reference")
        }
        XCTAssertEqual(resolved.path, TreePath([0, 0]))
        XCTAssertEqual(resolved.traversalIndex, 0)
    }

    func testScreenChangedAfterActionBatchCaptureInvalidatesCommittedObservation() async throws {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Checkout"), "checkout")])
        let action = bagman.accessibilityNotifications.beginActionWindow()
        let batch = try XCTUnwrap(action.capture())
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )

        bagman.semanticObservationStream.commitVisibleObservationForTesting(observation, notificationBatch: batch)
        action.cancel()

        let served = await bagman.semanticObservationStream.settledEvent(
            scope: .visible,
            after: nil,
            timeout: 0
        )
        XCTAssertNil(served)
    }

    func testDiscoveryObservationHonorsExplicitCursorWhenNextEventAlreadyExists() async throws {
        let baseline = bagman.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "Baseline"), "baseline")])
        )
        let current = bagman.semanticObservationStream.commitDiscoveryObservationForTesting(
            InterfaceObservation.makeForTests(elements: [(element(label: "Current"), "current")])
        )

        let served = await bagman.semanticObservationStream.settledEvent(
            scope: .discovery,
            after: baseline.sequence,
            timeout: 0.1
        )

        XCTAssertEqual(try XCTUnwrap(served).sequence, current.sequence)
    }

    func testNotificationOverflowIsExplicitInCommittedTrace() async throws {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        let action = bagman.accessibilityNotifications.beginActionWindow()
        for _ in 0..<65 {
            bagman.accessibilityNotifications.recordForTesting(
                code: 1008,
                notificationData: .none,
                associatedElement: .none
            )
        }
        let batch = try XCTUnwrap(action.capture())

        let event = bagman.semanticObservationStream.commitVisibleObservationForTesting(
            observation,
            notificationBatch: batch
        )
        action.cancel()

        XCTAssertEqual(
            event.trace.captures.last?.transition.accessibilityNotificationGap,
            AccessibilityNotificationGap(droppedThroughSequence: 1)
        )
    }

    func testCommittedTraceRetainsFirstResponderAsDurableTarget() {
        let observation = InterfaceObservation.makeForTests(
            [
                .init(label: "Email", heistId: "email", traits: .textEntry),
                .init(label: "Continue", heistId: "continue", traits: .button),
            ],
            firstResponderHeistId: "email"
        )

        let event = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertNotNil(event.trace.captures.last?.context.firstResponder)
        XCTAssertEqual(event.settledObservation.observation.liveCapture.firstResponderHeistId, "email")
    }

    func testFailedSettlePreservesScreenChangedForNextIdenticalCommit() async {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        let firstEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)
        let firstHeist = bagman.accessibilityNotifications.beginHeistScope()
        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let settleResult = SettleSession.Result(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        _ = await bagman.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleResult: settleResult,
            notificationWindow: action
        )
        firstHeist.cancel()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )

        XCTAssertEqual(
            bagman.accessibilityNotifications.checkpoint(
                after: .origin,
                selection: .all
            ).events.map(\.provenance),
            [.scoped, .ambient]
        )

        let secondHeist = bagman.accessibilityNotifications.beginHeistScope()
        defer { secondHeist.cancel() }
        let secondEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertNotEqual(secondEvent.generation, firstEvent.generation)
        XCTAssertEqual(
            secondEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.screenChanged]
        )
        XCTAssertEqual(
            secondEvent.trace.captures.last?.transition.accessibilityNotifications.map(\.sequence),
            [1]
        )
        XCTAssertEqual(
            secondEvent.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    func testAmbientScreenChangedBetweenHeistScopesDoesNotStartGeneration() {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        let firstEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)
        let firstHeist = bagman.accessibilityNotifications.beginHeistScope()
        firstHeist.cancel()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let secondHeist = bagman.accessibilityNotifications.beginHeistScope()
        defer { secondHeist.cancel() }

        let secondEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        XCTAssertEqual(secondEvent.generation, firstEvent.generation)
        XCTAssertTrue(secondEvent.trace.captures.last?.transition.accessibilityNotifications.isEmpty == true)
        XCTAssertTrue(secondEvent.trace.changeFacts.isEmpty)
    }

    func testSettledActionRequiresActionWindowToClaimAccessibilityNotifications() async {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        bagman.observeInterface(observation)
        bagman.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )
        let settleResult = SettleSession.Result(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        let result = await bagman.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleResult: settleResult
        )

        guard case .committed(let event) = result.commitOutcome else {
            return XCTFail("Expected successful settlement to commit")
        }
        XCTAssertEqual(event.trace.captures.last?.transition.accessibilityNotifications, [])
        XCTAssertEqual(
            bagman.accessibilityNotifications.checkpoint(
                after: .origin,
                selection: .all
            ).events.map(\.kind),
            [.announcement]
        )
    }

    func testSettlementAdmissionCarriesTheExactObservation() throws {
        let stableElement = element(label: "Stable")
        let settled = InterfaceObservation.makeForTests(elements: [(stableElement, "stable")])
        let finalObservation = SettleSessionFinalObservation(observation: settled)
        let settleResult = SettleSession.Result(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: finalObservation,
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )
        bagman.observeInterface(settled)

        let replacement = InterfaceObservation.makeForTests(elements: [(stableElement, "stable")])
        XCTAssertEqual(replacement.tree, settled.tree)
        XCTAssertEqual(replacement.liveCapture.snapshot, settled.liveCapture.snapshot)
        XCTAssertNotEqual(replacement.captureID, settled.captureID)
        bagman.observeInterface(replacement)

        let committableObservation = try XCTUnwrap(CommittableInterfaceObservation.admit(settleResult))
        XCTAssertEqual(committableObservation.observation.captureID, settled.captureID)
        XCTAssertNotEqual(committableObservation.observation.captureID, replacement.captureID)
    }

    func testViewportMovementLineageRequiresDedicatedAdmissionConstructor() throws {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        bagman.observeInterface(observation)
        let settleResult = SettleSession.Result(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        let ordinary = try XCTUnwrap(CommittableInterfaceObservation.admit(settleResult))
        let afterMovement = try XCTUnwrap(
            CommittableInterfaceObservation.admit(
                settleResult,
                lineageEvidence: .viewportMovement
            )
        )

        XCTAssertNil(ordinary.lineageEvidence)
        XCTAssertEqual(afterMovement.lineageEvidence, .viewportMovement)
    }

    func testRecaptureOnlyValueChangedNotificationProducesNotificationFact() async throws {
        let observation = InterfaceObservation.makeForTests(elements: [
            (element(label: "Volume", value: "50%", traits: .adjustable), "volume"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )
        let result = await bagman.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleResult: SettleSession.Result(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(observation: observation),
                elementsByKey: [:],
                tripwireSignal: bagman.tripwire.tripwireSignal()
            ),
            notificationWindow: action
        )

        guard case .committed(let event) = result.commitOutcome else {
            return XCTFail("Expected successful settlement to commit")
        }
        XCTAssertEqual(
            event.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.elementChanged(.value)]
        )
        XCTAssertEqual(event.trace.changeFacts.count, 1)
        guard case .elementsChanged(let fact)? = event.trace.changeFacts.first else {
            return XCTFail("Expected notification-only elementsChanged fact")
        }
        XCTAssertTrue(fact.isNotificationOnly)
        XCTAssertEqual(fact.metadata.accessibilityNotifications.map(\.kind), [.elementChanged(.value)])
    }

    func testValueChangedNotificationRequiresAccessibilityValueChangeForElementDelta() async throws {
        let before = InterfaceObservation.makeForTests(elements: [
            (element(label: "Volume", value: "50%", traits: .adjustable), "volume"),
        ])
        let after = InterfaceObservation.makeForTests(elements: [
            (element(label: "Volume", value: "75%", traits: .adjustable), "volume"),
        ])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(before)
        bagman.observeInterface(after)

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1005,
            notificationData: .none,
            associatedElement: .none
        )
        let result = await bagman.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleResult: SettleSession.Result(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(observation: after),
                elementsByKey: [:],
                tripwireSignal: bagman.tripwire.tripwireSignal()
            ),
            notificationWindow: action
        )

        guard case .committed(let event) = result.commitOutcome else {
            return XCTFail("Expected successful settlement to commit")
        }
        XCTAssertEqual(
            event.trace.captures.last?.transition.accessibilityNotifications.map(\.kind),
            [.elementChanged(.value)]
        )
        XCTAssertEqual(event.trace.changeFacts.count, 1)
        guard case .elementsChanged(let fact)? = event.trace.changeFacts.first else {
            return XCTFail("Expected value edit to drive elementsChanged")
        }
        XCTAssertEqual(fact.metadata.accessibilityNotifications.map(\.kind), [.elementChanged(.value)])
        let change = try XCTUnwrap(fact.updated.first?.changes.first)
        XCTAssertEqual(change.property, .value)
        XCTAssertEqual(change.oldDisplayText, "50%")
        XCTAssertEqual(change.newDisplayText, "75%")
    }

    func testAnnouncementNotificationIsPreservedOutsideInterfaceChangeFacts() async {
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Stable"), "stable")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(observation)

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Saved" as NSString),
            associatedElement: .none
        )
        let result = await bagman.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleResult: SettleSession.Result(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(observation: observation),
                elementsByKey: [:],
                tripwireSignal: bagman.tripwire.tripwireSignal()
            ),
            notificationWindow: action
        )

        guard case .committed(let event) = result.commitOutcome else {
            return XCTFail("Expected successful settlement to commit")
        }
        XCTAssertEqual(event.trace.capturedAnnouncements.map(\.text), ["Saved"])
        XCTAssertEqual(event.trace.captures.last?.transition.accessibilityNotifications.map(\.kind), [.announcement])
        XCTAssertTrue(event.trace.changeFacts.isEmpty)
    }

    func testScreenChangedNotificationStartsGenerationAndPreservesBoundaryFacts() throws {
        let first = InterfaceObservation.makeForTests(elements: [(element(label: "Menu", traits: .header), "menu")])
        let firstEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(first)
        let action = bagman.accessibilityNotifications.beginActionWindow()
        defer { action.cancel() }
        bagman.accessibilityNotifications.recordForTesting(
            code: 1000,
            notificationData: .none,
            associatedElement: .none
        )
        let notificationBatch = try XCTUnwrap(action.capture())
        let second = InterfaceObservation.makeForTests(elements: [(element(label: "Checkout", traits: .header), "checkout")])

        let secondEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(
            second,
            notificationBatch: notificationBatch
        )

        XCTAssertNotEqual(secondEvent.generation, firstEvent.generation)
        XCTAssertEqual(secondEvent.previous?.sequence, firstEvent.sequence)
        XCTAssertEqual(secondEvent.previousCursor, firstEvent.cursor)
        XCTAssertEqual(secondEvent.trace.captures.count, 2)

        let baseline = try XCTUnwrap(firstEvent.settledCapture)
        let window = try XCTUnwrap(bagman.semanticObservationStream.observationWindow(
            from: baseline,
            through: secondEvent
        ))
        XCTAssertEqual(window.completeness, .complete)
        XCTAssertEqual(
            window.trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
    }

    func testDiscoveryCommitClassifiesAgainstLatestVisibleWithoutCrossScopeLineage() {
        let visible = InterfaceObservation.makeForTests(elements: [
            (element(label: "Menu", traits: .header), "menu"),
        ])
        let visibleEvent = bagman.semanticObservationStream.commitVisibleObservationForTesting(visible)
        let discoveryHeader = element(label: "Checkout", traits: .header)
        let discovery = InterfaceObservation.makeForTests(elements: [(discoveryHeader, "checkout")])

        let discoveryEvent = bagman.semanticObservationStream.commitDiscoveryObservationForTesting(discovery)

        XCTAssertNotEqual(discoveryEvent.generation, visibleEvent.generation)
        XCTAssertNil(discoveryEvent.previous)
    }

    func testPostActionFailedSettlePreservesPendingAccessibilityNotificationsDuringHeistScope() async {
        let heist = bagman.accessibilityNotifications.beginHeistScope()
        defer { heist.cancel() }

        let action = bagman.accessibilityNotifications.beginActionWindow()
        bagman.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Done" as NSString),
            associatedElement: .none
        )
        let observation = InterfaceObservation.makeForTests(elements: [(element(label: "Unstable"), "unstable")])
        let settleResult = SettleSession.Result(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        _ = await bagman.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleResult: settleResult,
            notificationWindow: action
        )

        XCTAssertEqual(
            bagman.accessibilityNotifications.checkpoint(
                after: .origin,
                selection: .all
            ).events.map(\.kind),
            [.announcement],
            "Action attribution must not consume retained notification history."
        )
    }

    func testPostActionFailedSettleReturnsObservedUnsettledEvidenceInsteadOfBaseline() async {
        let object = NSObject()
        let observation = InterfaceObservation.makeForTests([
            .init(element(label: "Unstable"), heistId: "unstable", object: object),
        ])
        let settleResult = SettleSession.Result(
            outcome: .timedOut(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: observation),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )

        let result = await bagman.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleResult: settleResult
        )

        guard case .observedUnsettled(let observedObservation, _) = result.commitOutcome else {
            return XCTFail("Expected observed unsettled settle evidence")
        }
        XCTAssertEqual(observedObservation.tree.orderedElements.first?.element.label, "Unstable")
        XCTAssertEqual(observedObservation.captureID, observation.captureID)
        XCTAssertTrue(observedObservation.liveCapture.object(for: "unstable") === object)
        XCTAssertEqual(
            bagman.latestFailedSettleDiagnosticEvidence?.tree.orderedElements.first?.element.label,
            "Unstable"
        )
        XCTAssertEqual(bagman.latestFailedSettleDiagnosticEvidence?.captureID, observation.captureID)
        XCTAssertTrue(bagman.latestFailedSettleDiagnosticEvidence?.liveCapture.object(for: "unstable") === object)
        XCTAssertTrue(bagman.semanticObservationStream.latestSettledObservationInvalidated)
    }

    func testPublicInterfaceReadsSettledTruthNotFailedSettleDiagnosticEvidence() throws {
        let settled = InterfaceObservation.makeForTests(elements: [(element(label: "Settled"), "settled")])
        bagman.semanticObservationStream.commitVisibleObservationForTesting(settled)

        let diagnostic = InterfaceObservation.makeForTests(elements: [(element(label: "Timeout"), "timeout")])
        bagman.recordFailedSettleDiagnosticEvidence(diagnostic)

        let interface = try bagman.selectInterface(InterfaceQuery())
        XCTAssertEqual(interface.projectedElements.compactMap(\.label), ["Settled"])
        XCTAssertNil(bagman.resolveVisibleTarget(literalTarget(ElementPredicate.label("Timeout"))).resolvedElement)
    }

    func testRejectedSettleDiagnosticDoesNotReplaceNewerParsedObservation() async {
        let objectA = NSObject()
        let objectB = NSObject()
        let screenA = InterfaceObservation.makeForTests([
            .init(element(label: "A"), heistId: "a", object: objectA),
        ])
        let screenB = InterfaceObservation.makeForTests([
            .init(element(label: "B"), heistId: "b", object: objectB),
        ])
        let rejectedResult = SettleSession.Result(
            outcome: .settled(timeMs: 1),
            events: [],
            finalObservation: SettleSessionFinalObservation(observation: screenA),
            elementsByKey: [:],
            tripwireSignal: bagman.tripwire.tripwireSignal()
        )
        bagman.observeInterface(screenA)
        bagman.observeInterface(screenB)

        let result = await bagman.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: bagman.tripwire.tripwireSignal(),
            settleResult: rejectedResult
        )

        guard case .unavailable = result.commitOutcome else {
            return XCTFail("Expected stale settlement admission to be rejected")
        }
        XCTAssertEqual(bagman.latestObservation.captureID, screenB.captureID)
        XCTAssertTrue(bagman.latestObservation.liveCapture.object(for: "b") === objectB)
        XCTAssertNil(bagman.latestObservation.liveCapture.object(for: "a"))
        XCTAssertEqual(bagman.latestFailedSettleDiagnosticEvidence?.captureID, screenA.captureID)
        XCTAssertTrue(bagman.latestFailedSettleDiagnosticEvidence?.liveCapture.object(for: "a") === objectA)
    }
}

#endif
