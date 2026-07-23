#if canImport(UIKit)
import ButtonHeistSupport
import ButtonHeistTestSupport
import XCTest
@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsActionTests {

    func testHeistWaitWithMinimumTimeoutSucceedsFromVisibleMissingObservation() async throws {
        var observedTimeouts: [Double?] = []
        let runtime = heistRuntime(
            observations: [await observedState(labels: ["Home"])],
            observedTimeouts: { observedTimeouts.append($0) }
        )
        let plan = try HeistPlan(body: [
            .wait(WaitStep(
                predicate: .missing(.label("Loading")),
                timeout: .milliseconds(1)
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(observedTimeouts, [0.001])
    }

    func testPerformWaitWithBoundedTimeoutDoesNotStartObservationWhenRuntimeInactive() async throws {
        let inactiveBrains = TheBrains(tripwire: TheTripwire())
        await inactiveBrains.vault.installObservationForTesting(.makeForTests(elements: [
            (makeElement(label: "Home"), HeistId(rawValue: "home")),
        ]))
        XCTAssertFalse(inactiveBrains.vault.semanticObservationStream.isActive)

        let step = WaitStep(predicate: .exists(.label("Home")), timeout: try .milliseconds(1))
        let result = await inactiveBrains.performWait(step: try resolvedWait(step))

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.outcome.failureKind, .actionFailed)
        XCTAssertEqual(result.message, TheBrains.runtimeInactiveMessage)
        XCTAssertFalse(inactiveBrains.vault.semanticObservationStream.isActive)
    }

    func testExecuteCommandDoesNotStartObservationWhenRuntimeInactive() async {
        let inactiveBrains = TheBrains(tripwire: TheTripwire())
        let initialSnapshot = await inactiveBrains.vault.semanticObservationStream.latestCommittedSnapshot()
        XCTAssertNil(initialSnapshot)
        XCTAssertFalse(inactiveBrains.vault.semanticObservationStream.isActive)

        let result = await inactiveBrains.executeRuntimeAction(.activate(.predicate(.label("Home"))))

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.outcome.failureKind, .actionFailed)
        XCTAssertEqual(result.message, TheBrains.runtimeInactiveMessage)
        XCTAssertFalse(inactiveBrains.vault.semanticObservationStream.isActive)
    }

    func testWaitResultUsesBeforeAndMatchedSettledObservations() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        let beforeScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Before"), "before"),
        ])
        let matchedScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Before"), "before"),
            (makeElement(label: "Loaded"), "loaded"),
        ])

        await isolatedBrains.vault.semanticObservationStream
            .commitDiscoveryObservationForTesting(beforeScreen)
        await isolatedBrains.vault.semanticObservationStream
            .commitDiscoveryObservationForTesting(matchedScreen)

        let result = await isolatedBrains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .exists(.label("Loaded")),
                timeout: 1
            ))
        )
        guard case .matched(let actionResult, _) = result.outcome else {
            return XCTFail("Expected the wait to match")
        }
        let trace = try XCTUnwrap(actionResult.accessibilityTrace)

        XCTAssertTrue(actionResult.outcome.isSuccess)
        XCTAssertEqual(trace.captures.first?.interface.projectedElements.map(\.label), ["Before"])
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Before", "Loaded"])
        XCTAssertTrue(trace.changeFacts.contains { if case .elementsChanged = $0 { true } else { false } })
    }

    func testFailedActionBatchBelongsToDiagnosticAndNextActionClaimsOnlyItsBatch() async {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        let baseline = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Before"), "before"),
        ])
        let baselineEvent = await isolatedBrains.vault.semanticObservationStream.commitVisibleObservationForTesting(baseline)
        let before = isolatedBrains.actionEvidenceProjector.projectBaseline(
            from: Observation.Store.AdmittedObservation(
                event: baselineEvent,
                tripwireSignal: .empty
            )
        )
        let failedScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Unstable"), "unstable"),
        ])

        let failedWindow = isolatedBrains.vault.accessibilityNotifications.beginActionWindow()
        isolatedBrains.vault.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Action A" as NSString),
            associatedElement: .none
        )
        let failedObservation = await isolatedBrains.vault.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            settleResult: SettleSession.Result(
                outcome: .timedOut(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(observation: failedScreen),
                elementsByKey: [:],
                tripwireSignal: isolatedBrains.vault.semanticObservationStream.currentTripwireSignal()
            ),
            notificationWindow: failedWindow
        )
        let failedResult = isolatedBrains.actionEvidenceProjector.projectResult(
            before: before,
            observation: failedObservation
        )

        XCTAssertEqual(failedResult.accessibilityTrace.capturedAnnouncements.map { $0.text }, ["Action A"])

        let successfulScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "After"), "after"),
        ])
        let successfulWindow = isolatedBrains.vault.accessibilityNotifications.beginActionWindow()
        isolatedBrains.vault.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload("Action B" as NSString),
            associatedElement: .none
        )
        isolatedBrains.vault.observeInterface(successfulScreen)
        let successfulObservation = await isolatedBrains.vault.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            settleResult: SettleSession.Result(
                outcome: .settled(timeMs: 1),
                events: [],
                finalObservation: SettleSessionFinalObservation(observation: successfulScreen),
                elementsByKey: [:],
                tripwireSignal: isolatedBrains.vault.semanticObservationStream.currentTripwireSignal()
            ),
            notificationWindow: successfulWindow
        )

        guard case .committed(let successfulEvent) = successfulObservation.commitOutcome else {
            return XCTFail("Expected action B to commit")
        }
        XCTAssertEqual(successfulEvent.trace.capturedAnnouncements.map { $0.text }, ["Action B"])
        XCTAssertEqual(failedResult.accessibilityTrace.capturedAnnouncements.map { $0.text }, ["Action A"])
        XCTAssertEqual(
            isolatedBrains.vault.accessibilityNotifications
                .checkpoint(after: .origin, selection: .all)
                .events
                .map(\.sequence),
            [1, 2]
        )
    }

    func testChangedActionExpectationUsesPreActionBaselineForSettledActionResult() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        defer { isolatedBrains.stopSemanticObservation() }
        let beforeScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Menu", traits: .header), "menu_header"),
        ])
        let afterScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Controls Demo", traits: .header), "controls_demo_header"),
        ])
        let beforeEvent = await isolatedBrains.vault.semanticObservationStream.commitVisibleObservationForTesting(beforeScreen)
        let afterEvent = await isolatedBrains.vault.semanticObservationStream.commitVisibleObservationForTesting(afterScreen)
        let before = isolatedBrains.actionEvidenceProjector.projectBaseline(
            from: beforeScreen,
            tripwireSignal: .empty,
            settledObservationSequence: beforeEvent.sequence
        )
        let after = isolatedBrains.actionEvidenceProjector.projectBaseline(
            from: afterScreen,
            tripwireSignal: .empty,
            settledObservationSequence: afterEvent.sequence
        )
        let detachedBeforeCapture = AccessibilityTrace.Capture(
            sequence: before.capture.sequence,
            interface: before.capture.interface,
            parentHash: before.capture.parentHash,
            context: AccessibilityTrace.Context(
                keyboardVisible: !(before.capture.context.keyboardVisible ?? false),
                screenId: before.capture.context.screenId,
                windowStack: before.capture.context.windowStack
            ),
            transition: before.capture.transition
        )
        let screenChanged = AccessibilityNotificationEvidence(
            sequence: 1,
            kind: .screenChanged,
            timestamp: Date(timeIntervalSince1970: 0),
            notificationData: .none,
            associatedElement: .none
        )
        let classification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: after.screenSnapshot,
            notifications: [screenChanged.kind]
        )
        let initialTrace = isolatedBrains.actionEvidenceProjector.makeAccessibilityTrace(
            afterCapture: after.capture,
            parentCapture: detachedBeforeCapture,
            classification: classification,
            accessibilityNotifications: [screenChanged]
        )
        let actionResult = ActionResult.success(
            payload: .activate,
observation: .settledTrace(
                makeTestTraceEvidence(initialTrace, completeness: .incomplete),
                .settled(duration: 0)
            )
        )

        XCTAssertEqual(classification, .replacement(.screenChangedNotification))
        XCTAssertNotEqual(initialTrace.captures.first?.hash, afterEvent.trace.captures.first?.hash)
        XCTAssertEqual(initialTrace.captures.first?.hash, detachedBeforeCapture.hash)
        XCTAssertEqual(initialTrace.captures.last?.interface, after.interface)
        XCTAssertEqual(initialTrace.captures.last?.context, after.capture.context)
        XCTAssertEqual(initialTrace.captures.last?.transition.accessibilityNotifications, [screenChanged])
        XCTAssertNil(initialTrace.captures.last?.transition.fallbackReason)
        XCTAssertEqual(actionResult.settled, true)

        let result = await isolatedBrains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .changed(.screen([.exists(.element(
                    .label("Controls Demo"),
                    traits: [.header]
                ))])),
                timeout: 1
            )),
            initialTrace: actionResult.accessibilityTrace
        )

        guard case .matched(let waitActionResult, _) = result.outcome else {
            return XCTFail("Expected the screen-change wait to match")
        }
        XCTAssertTrue(waitActionResult.outcome.isSuccess)
        XCTAssertTrue(waitActionResult.accessibilityTrace?.changeFacts.contains {
            if case .screenChanged = $0 { true } else { false }
        } == true)
    }

    func testAttachedExpectationSettlesInsideItsActionInvocation() async throws {
        let saveObject = ActionActivationOverrideView()
        let announceObject = ActionActivationOverrideView()
        let saveElement = makeElement(label: "Save", traits: .button)
        let announceElement = makeElement(label: "Announce", traits: .button)
        let elements: [(AccessibilityElement, HeistId)] = [
            (saveElement, "save_button"),
            (announceElement, "announce_button"),
        ]
        let objects: [HeistId: NSObject?] = [
            "save_button": saveObject,
            "announce_button": announceObject,
        ]
        let before = InterfaceObservation.makeForTests(elements: elements, objects: objects)
        let transient = InterfaceObservation.makeForTests(
            elements: elements + [(makeElement(label: "Saved", traits: .staticText), "saved")],
            objects: objects
        )
        let after = InterfaceObservation.makeForTests(elements: elements, objects: objects)
        let committedObservations = ObservationCommitFixture(
            stream: brains.vault.semanticObservationStream,
            observations: [transient, after]
        ) {
            self.visibleObservationSource.observation = after
        }
        saveObject.onActivation = committedObservations.signal
        announceObject.onActivation = {
            self.brains.vault.accessibilityNotifications.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload("Confirmed" as NSString),
                associatedElement: .none
            )
        }
        await installSyntheticObservation(before)
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Save")),
                expectationPolicy: .expect(try ActionExpectation(WaitStep(
                    predicate: .changed(.elements([
                        .appeared(.label("Saved")),
                    ])),
                    timeout: .seconds(1)
                )))
            )),
            .action(ActionStep(
                command: .activate(.label("Announce")),
                expectationPolicy: .expect(try ActionExpectation(WaitStep(
                    predicate: .announcement("Confirmed"),
                    timeout: .seconds(1)
                )))
            )),
        ])

        let result = await brains.executeHeistPlan(plan)
        await committedObservations.wait()
        let steps = try XCTUnwrap(result.resultPayload?.steps)
        let elementTrace = try XCTUnwrap(steps.first?.actionEvidence?.expectationResult?.accessibilityTrace)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        XCTAssertEqual(saveObject.activationCount, 1)
        XCTAssertEqual(announceObject.activationCount, 1)
        XCTAssertEqual(steps.map(\.reportExpectation?.met), [true, true])
        XCTAssertEqual(
            elementTrace.captures.first?.interface.projectedElements.compactMap(\.label),
            ["Save", "Announce"]
        )
        XCTAssertEqual(
            elementTrace.captures.dropFirst().first?.interface.projectedElements.compactMap(\.label),
            ["Save", "Announce", "Saved"]
        )
        XCTAssertEqual(
            elementTrace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Save", "Announce"]
        )
        XCTAssertEqual(steps.last?.actionEvidence?.expectationResult?.announcement, "Confirmed")
    }

    func testSettledTraceAnnouncementUsesFirstMatch() async throws {
        let notifications = ["Saving", "Confirmed"].enumerated().map { index, text in
            AccessibilityNotificationEvidence(
                sequence: UInt64(index + 1),
                kind: .announcement,
                timestamp: Date(timeIntervalSince1970: Double(index)),
                notificationData: .string(text),
                associatedElement: .none
            )
        }
        let interface = try XCTUnwrap(Interface(
            admitting: Date(timeIntervalSince1970: 0),
            tree: []
        ))
        let trace = AccessibilityTrace(interface: interface).appending(
            interface,
            transition: AccessibilityTrace.Transition(accessibilityNotifications: notifications)
        )
        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .announcement("Confirmed"),
                timeout: .milliseconds(1)
            )),
            initialTrace: trace
        )

        guard case .matched(let actionResult, let expectation) = result.outcome else {
            return XCTFail("Expected matching announcement in settled trace")
        }
        XCTAssertTrue(actionResult.outcome.isSuccess)
        XCTAssertEqual(actionResult.accessibilityTrace, trace)
        XCTAssertEqual(expectation.actual, "Confirmed")
    }

    func testStandaloneWaitStartsAtItsOwnFirstObservation() async throws {
        let saveObject = ActionActivationOverrideView()
        let saveElement = makeElement(label: "Save", traits: .button)
        let elements: [(AccessibilityElement, HeistId)] = [(saveElement, "save_button")]
        let objects: [HeistId: NSObject?] = ["save_button": saveObject]
        let before = InterfaceObservation.makeForTests(elements: elements, objects: objects)
        let transient = InterfaceObservation.makeForTests(
            elements: elements + [(makeElement(label: "Saved", traits: .staticText), "saved")],
            objects: objects
        )
        let after = InterfaceObservation.makeForTests(elements: elements, objects: objects)
        let committedObservations = ObservationCommitFixture(
            stream: brains.vault.semanticObservationStream,
            observations: [transient, after]
        ) {
            self.visibleObservationSource.observation = after
            self.brains.vault.accessibilityNotifications.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload("Saved" as NSString),
                associatedElement: .none
            )
        }
        saveObject.onActivation = committedObservations.signal
        await installSyntheticObservation(before)
        let initialEvent = await brains.vault.semanticObservationStream.latestCommittedEvent()
        let initialMoment = try XCTUnwrap(initialEvent?.moment)

        let action = await brains.executeHeistPlan(try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Save")),
                expectationPolicy: .expect(try ActionExpectation(WaitStep(
                    predicate: .changed(.elements([.appeared(.label("Saved"))])),
                    timeout: .seconds(1)
                )))
            )),
        ]))
        await committedObservations.wait()
        let actionEvent = await brains.vault.semanticObservationStream.latestCommittedEvent()
        let actionMoment = try XCTUnwrap(actionEvent?.moment)
        let actionAnnouncementCursor = brains.vault.accessibilityNotifications.cursor()
        let isolationSettlement = try await standaloneIsolationSettlement(
            after: actionMoment,
            cursor: actionAnnouncementCursor
        )
        let appeared = await brains.performWait(step: try resolvedWait(WaitStep(
            predicate: .changed(.elements([.appeared(.label("Saved"))])),
            timeout: .milliseconds(1)
        )))
        let disappeared = await brains.performWait(step: try resolvedWait(WaitStep(
            predicate: .changed(.elements([.disappeared(.label("Saved"))])),
            timeout: .milliseconds(1)
        )))
        let exists = await brains.performWait(step: try resolvedWait(WaitStep(
            predicate: .exists(.label("Saved")),
            timeout: .milliseconds(1)
        )))
        let announcement = await brains.performWait(step: try resolvedWait(WaitStep(
            predicate: .announcement("Saved"),
            timeout: .milliseconds(1)
        )))
        let finalEvent = await brains.vault.semanticObservationStream.latestCommittedEvent()
        let finalMoment = try XCTUnwrap(finalEvent?.moment)

        XCTAssertTrue(action.outcome.isSuccess, action.message ?? "action heist failed")
        XCTAssertEqual(action.resultPayload?.steps.first?.reportExpectation?.met, true)
        XCTAssertEqual(saveObject.activationCount, 1)
        XCTAssertTrue(actionMoment.isSameOrAfter(initialMoment))
        XCTAssertNotEqual(actionMoment, initialMoment)
        XCTAssertFalse(isolationSettlement.evidence.predicate.isSatisfied)
        XCTAssertTrue(finalMoment.isSameOrAfter(actionMoment))
        XCTAssertNotEqual(finalMoment, actionMoment)
        for result in [appeared, disappeared, exists, announcement] {
            XCTAssertFalse(result.outcome.isSuccess)
            XCTAssertEqual(result.outcome.failureKind, .timeout)
        }
        XCTAssertTrue(appeared.accessibilityTrace?.changeFacts.isEmpty == true)
        XCTAssertEqual(
            appeared.accessibilityTrace?.captures.first?.interface.projectedElements.compactMap(\.label),
            ["Save"]
        )
        XCTAssertNil(announcement.announcement)
    }

    private func standaloneIsolationSettlement(
        after actionMoment: Observation.Moment,
        cursor actionCursor: AccessibilityNotificationCursor
    ) async throws -> Settlement.Result {
        brains.vault.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload(
                "Standalone wait boundary" as NSString
            ),
            associatedElement: .none
        )
        let postActionCursor = brains.vault.accessibilityNotifications.cursor()
        let settlement = try await standaloneSettlementForIsolationTest(WaitStep(
            predicate: .changed(.elements([.appeared(.label("Saved"))])),
            timeout: .milliseconds(100)
        ))
        guard case .established(let boundary) = settlement.evidence.boundary else {
            XCTFail("Standalone wait did not establish its own evidence boundary")
            return settlement
        }
        guard case .events(let events)? = settlement.evidence.observationHistory else {
            XCTFail("Standalone wait did not retain post-baseline observation history")
            return settlement
        }
        let snapshots = events.compactMap { event -> Observation.SnapshotEvent? in
            guard case .snapshot(let snapshot) = event else { return nil }
            return snapshot
        }

        XCTAssertGreaterThan(postActionCursor.sequence, actionCursor.sequence)
        XCTAssertGreaterThanOrEqual(boundary.announcementCursor.sequence, postActionCursor.sequence)
        XCTAssertTrue(boundary.moment.isSameOrAfter(actionMoment))
        XCTAssertNotEqual(boundary.moment, actionMoment)
        XCTAssertFalse(snapshots.isEmpty)
        for snapshot in snapshots {
            XCTAssertTrue(snapshot.moment.isSameOrAfter(boundary.moment))
            XCTAssertNotEqual(snapshot.moment, boundary.moment)
        }
        return settlement
    }

    private func standaloneSettlementForIsolationTest(
        _ step: WaitStep
    ) async throws -> Settlement.Result {
        let resolved = try resolvedWait(step)
        let startedAt = RuntimeElapsed.now
        let command = Settlement.Command(
            trigger: .observation,
            predicate: Settlement.Predicate(
                authored: resolved.predicateExpression,
                resolved: resolved.predicate
            ),
            deadline: Settlement.Deadline(
                instant: startedAt.advanced(by: .seconds(resolved.timeout.seconds))
            )
        )
        let discoveryDeadline = SemanticObservationDeadline(
            start: startedAt,
            timeoutSeconds: resolved.timeout.seconds
        )
        return await brains.executeSettlement(
            command,
            observationEffects: { control in
                await self.brains.interactionCoordinator.publishStandaloneWaitDiscovery(
                    target: resolved.predicate.waitTarget,
                    deadline: discoveryDeadline,
                    control: control
                )
            },
            dispatch: { _ in
                preconditionFailure("Observation settlement cannot dispatch an action")
            }
        )
    }

    func testStandaloneWaitMatchesPreexistingLevelStateWithoutDispatch() async throws {
        let object = ActionActivationOverrideView()
        let ready = InterfaceObservation.makeForTests(
            elements: [(makeElement(label: "Ready", traits: .button), "ready")],
            objects: ["ready": object]
        )
        await installSyntheticObservation(ready)

        let result = await brains.performWait(step: try resolvedWait(WaitStep(
            predicate: .exists(.label("Ready")),
            timeout: .seconds(1)
        )))

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "standalone wait failed")
        XCTAssertEqual(result.method, .wait)
        XCTAssertEqual(object.activationCount, 0)
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.interface.projectedElements.map(\.label),
            ["Ready"]
        )
    }

    func testStandaloneWaitRejectsAppearedWhenElementExistsAtBaseline() async throws {
        let object = ActionActivationOverrideView()
        let ready = InterfaceObservation.makeForTests(
            elements: [(makeElement(label: "Ready", traits: .button), "ready")],
            objects: ["ready": object]
        )
        await installSyntheticObservation(ready)

        let result = await brains.performWait(step: try resolvedWait(WaitStep(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            timeout: .milliseconds(1)
        )))

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(result.outcome.failureKind, .timeout)
        XCTAssertEqual(object.activationCount, 0)
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.isEmpty == true)
    }

    func testStandaloneWaitLatchesPostBaselineAppearanceAndReturnsPostReadinessObservation() async throws {
        let baseline = InterfaceObservation.makeForTests()
        let transient = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Ready", traits: .staticText), "ready"),
        ])
        let final = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Ready", traits: .staticText), "ready"),
            (makeElement(label: "Settled", traits: .staticText), "settled"),
        ])
        let commits = ObservationCommitFixture(
            stream: brains.vault.semanticObservationStream,
            observations: [transient]
        ) {
            self.visibleObservationSource.observation = final
        }
        brains.interactionCoordinator.observePredicateWaitScheduledEffects { effect in
            if effect == .discovery {
                self.visibleObservationSource.observation = final
                commits.signal()
            }
        }
        await installSyntheticObservation(baseline)

        let result = await brains.performWait(step: try resolvedWait(WaitStep(
            predicate: .changed(.elements([.appeared(.label("Ready"))])),
            timeout: .seconds(1)
        )))
        await commits.wait()

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "standalone wait failed")
        XCTAssertTrue(result.accessibilityTrace?.changeFacts.contains {
            guard case .elementsChanged(let changes) = $0 else { return false }
            return changes.appeared.contains(where: { node in
                guard case .element(let element, _) = node.node else { return false }
                return element.label == "Ready"
            })
        } == true)
        XCTAssertEqual(
            result.accessibilityTrace?.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Ready", "Settled"]
        )
    }

    func testFailedProductionDispatchDiscardsActionExpectationContext() async throws {
        let heistId: HeistId = "options_button"
        let liveObject = UIView()
        liveObject.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Archive") { _ in
                self.brains.vault.accessibilityNotifications.recordForTesting(
                    code: 1008,
                    notificationData: CapturedAccessibilityNotificationPayload("Declined" as NSString),
                    associatedElement: .none
                )
                return false
            },
        ]
        await registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Options", traits: .button, customActions: ["Archive"]),
            object: liveObject
        )
        let command = try HeistActionCommand.customAction(
            name: "Archive",
            target: .label("Options")
        ).resolve(in: .empty)

        let execution = await brains.executeRuntimeActionForHeist(
            command,
            expectation: try resolvedWait(WaitStep(
                predicate: .announcement("Declined"),
                timeout: .milliseconds(20)
            ))
        )

        XCTAssertFalse(execution.result.outcome.isSuccess)
        XCTAssertNil(execution.actionExpectationContext)
        XCTAssertNil(execution.evidence.expectationResult)
    }

    func testWaitResultTimeoutRetainsFinalSettledEvidence() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        let knownScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Known"), "known"),
        ])
        await isolatedBrains.vault.installObservationForTesting(knownScreen)

        let result = await isolatedBrains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .exists(.label("Missing")),
                timeout: .milliseconds(1)
            ))
        )
        guard case .unmatched(let actionResult, _) = result.outcome else {
            return XCTFail("Expected the wait to time out without a match")
        }
        let trace = try XCTUnwrap(actionResult.accessibilityTrace)

        XCTAssertFalse(actionResult.outcome.isSuccess)
        XCTAssertEqual(actionResult.outcome.failureKind, .timeout)
        XCTAssertEqual(trace.captures.last?.interface.projectedElements.map(\.label), ["Known"])
    }

    func testHeistActionExpectationDoesNotInvokeStandaloneWait() async throws {
        let expectation = WaitStep(
            predicate: .exists(.label("Saved")),
            timeout: try .milliseconds(100)
        )
        let resolvedExpectation = try resolvedWait(expectation)
        var executedExpectation: ResolvedWaitRuntimeInput?
        var standaloneWaitCount = 0
        let runtime = TheBrains.HeistExecutionRuntime(
            execute: { _, predicate in
                executedExpectation = predicate
                let dispatchResult = ActionResult.success(payload: .activate)
                let expectationResult = ActionResult.success(payload: .wait)
                return RuntimeActionExecution(evidence: .expectation(
                    dispatchResult: dispatchResult,
                    expectationResult: expectationResult,
                    expectation: ExpectationResult(
                        met: true,
                        predicate: expectation.predicate,
                        actual: "Saved"
                    )
                ))
            },
            wait: { _ in
                standaloneWaitCount += 1
                return .failed(
                    failureKind: .actionFailed,
                    message: "unexpected standalone wait",
                    traceEvidence: nil,
                    expectation: ExpectationResult.Unmet(
                        predicate: expectation.predicate,
                        actual: "unexpected standalone wait"
                    )
                )
            },
            settledEvidence: { _, _, _ in nil }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Submit")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(executedExpectation, resolvedExpectation)
        XCTAssertEqual(standaloneWaitCount, 0)
        XCTAssertEqual(step.actionEvidence?.expectationResult?.method, .wait)
        XCTAssertEqual(step.reportExpectation?.met, true)
        XCTAssertNil(step.actionEvidence?.expectationResult?.accessibilityTrace)
    }

    func testActionExpectationRejectsUnavailableObservationBound() async throws {
        let baselineEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            .makeForTests()
        )
        let baseline = baselineEvent.moment
        let unrelatedBrains = TheBrains(tripwire: TheTripwire())
        let unavailableMoment = await unrelatedBrains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(.makeForTests())
            .moment
        let context = ActionExpectationContext(
            preActionMoment: baseline,
            throughMoment: unavailableMoment,
            announcementCursor: .origin
        )

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .changed(.elements()),
                timeout: 1
            )),
            actionExpectationContext: context
        )

        guard case .unmatched(let actionResult, let expectation) = result.outcome else {
            return XCTFail("Expected unavailable action observation evidence to fail")
        }
        XCTAssertEqual(actionResult.outcome.failureKind, .actionFailed)
        XCTAssertTrue(
            actionResult.message?.hasPrefix("Action expectation observation history unavailable:") == true
        )
        XCTAssertEqual(expectation.actual, actionResult.message)
    }

    func testActionNoChangeUsesFrozenUpperBoundBeforeLaterObservation() async throws {
        let stream = brains.vault.semanticObservationStream
        let baselineEvent = await stream.commitVisibleObservationForTesting(actionVolumeObservation(value: "50%"))
        let actionEndpoint = await stream.commitVisibleObservationForTesting(actionVolumeObservation(value: "50%"))
        _ = await stream.commitVisibleObservationForTesting(actionVolumeObservation(value: "60%"))
        let baseline = baselineEvent.moment
        let actionEndpointMoment = actionEndpoint.moment
        let context = ActionExpectationContext(
            preActionMoment: baseline,
            throughMoment: actionEndpointMoment,
            announcementCursor: .origin
        )

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .noChange, timeout: .milliseconds(1))),
            actionExpectationContext: context
        )

        XCTAssertTrue(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertTrue(result.outcome.expectation.met)
        XCTAssertEqual(result.observationMoment, actionEndpoint.moment)
        XCTAssertEqual(result.observedSequence, actionEndpoint.sequence)
    }

    func testActionNoChangeConsumesEntireFrozenWindow() async throws {
        let stream = brains.vault.semanticObservationStream
        let baselineEvent = await stream.commitVisibleObservationForTesting(actionVolumeObservation(value: "50%"))
        _ = await stream.commitVisibleObservationForTesting(actionVolumeObservation(value: "50%"))
        let actionEndpoint = await stream.commitVisibleObservationForTesting(actionVolumeObservation(value: "60%"))
        let baseline = baselineEvent.moment
        let actionEndpointMoment = actionEndpoint.moment
        let context = ActionExpectationContext(
            preActionMoment: baseline,
            throughMoment: actionEndpointMoment,
            announcementCursor: .origin
        )

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .noChange, timeout: .milliseconds(1))),
            actionExpectationContext: context
        )

        XCTAssertFalse(result.outcome.actionResult.outcome.isSuccess)
        XCTAssertEqual(result.outcome.actionResult.outcome.failureKind, .timeout)
        XCTAssertFalse(result.outcome.expectation.met)
    }

    func testActionNoChangeRejectsEvictedObservationHistory() async throws {
        let stream = brains.vault.semanticObservationStream
        let baselineEvent = await stream.commitVisibleObservationForTesting(actionVolumeObservation(value: "50%"))
        let baseline = baselineEvent.moment
        var actionEndpoint = baselineEvent
        for _ in 0...Observation.Store.defaultRetentionLimit {
            actionEndpoint = await stream.commitVisibleObservationForTesting(actionVolumeObservation(value: "50%"))
        }
        let actionEndpointMoment = actionEndpoint.moment
        let context = ActionExpectationContext(
            preActionMoment: baseline,
            throughMoment: actionEndpointMoment,
            announcementCursor: .origin
        )

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(predicate: .noChange, timeout: .milliseconds(1))),
            actionExpectationContext: context
        )

        XCTAssertEqual(result.outcome.actionResult.outcome.failureKind, .actionFailed)
        XCTAssertTrue(
            result.outcome.actionResult.message?.hasPrefix(
                "Action expectation observation history unavailable:"
            ) == true
        )
    }

    func testActionReplayCarriesTransientNearMissIntoTimeoutDiagnostics() async throws {
        let stream = brains.vault.semanticObservationStream
        let baselineEvent = await stream.commitVisibleObservationForTesting(.makeForTests())
        _ = await stream.commitVisibleObservationForTesting(.makeForTests(elements: [
            (
                makeElement(label: "Ticket saved., Dismiss", traits: .staticText),
                HeistId(rawValue: "toast")
            ),
        ]))
        let actionEndpoint = await stream.commitVisibleObservationForTesting(.makeForTests())
        let baseline = baselineEvent.moment
        let actionEndpointMoment = actionEndpoint.moment
        let context = ActionExpectationContext(
            preActionMoment: baseline,
            throughMoment: actionEndpointMoment,
            announcementCursor: .origin
        )

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .changed(.elements([.appeared(.label("Ticket saved."))])),
                timeout: .milliseconds(1)
            )),
            actionExpectationContext: context
        )
        let message = try XCTUnwrap(result.outcome.actionResult.message)

        XCTAssertEqual(result.outcome.actionResult.outcome.failureKind, .timeout)
        XCTAssertTrue(message.contains(#"label="Ticket saved., Dismiss""#), message)
    }

    func testActionAnnouncementRejectsEvictedMatchingEvidence() async throws {
        let baselineEvent = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            .makeForTests()
        )
        let baseline = baselineEvent.moment
        let announcementCursor = brains.vault.accessibilityNotifications.cursor()
        brains.vault.accessibilityNotifications.recordForTesting(
            code: 1008,
            notificationData: CapturedAccessibilityNotificationPayload(
                "Expected announcement" as NSString
            ),
            associatedElement: .none
        )
        for index in 0..<64 {
            brains.vault.accessibilityNotifications.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload(
                    "Unrelated announcement \(index)" as NSString
                ),
                associatedElement: .none
            )
        }
        let context = ActionExpectationContext(
            preActionMoment: baseline,
            throughMoment: baseline,
            announcementCursor: announcementCursor
        )

        let result = await brains.interactionCoordinator.waitForPredicate(
            try resolvedWait(WaitStep(
                predicate: .announcement("Expected announcement"),
                timeout: .milliseconds(1)
            )),
            actionExpectationContext: context
        )

        XCTAssertEqual(result.outcome.actionResult.outcome.failureKind, .actionFailed)
        XCTAssertTrue(
            result.outcome.actionResult.message?.hasPrefix(
                "Action expectation announcement history unavailable:"
            ) == true
        )
    }

    func testTemporalActionExpectationCarriesUnavailableBaselineWithoutReplacement() async throws {
        let expectation = WaitStep(predicate: .changed(.elements()), timeout: 1)
        var waitRequests: [TheBrains.HeistRuntimeWaitRequest] = []
        var contextScopes: [SemanticObservationScope?] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(payload: .activate)
            },
            wait: { request in
                waitRequests.append(request)
                return ActionResult.success(payload: .wait)
            },
            expectationContextScopes: { scope in
                contextScopes.append(scope)
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Submit")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let step = try XCTUnwrap(result.resultPayload?.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(contextScopes.first, .visible)
        XCTAssertEqual(waitRequests.count, 1)
        guard case .actionEndpoint(_, trace: nil, context: nil)? = waitRequests.first else {
            return XCTFail("Expected action endpoint wait with unavailable context")
        }
        XCTAssertEqual(step.reportExpectation?.met, false)
        XCTAssertNil(step.actionEvidence?.expectationResult?.accessibilityTrace)
    }

    func testActionExpectationStartsWithVisibleScope() async throws {
        let observedReady = await observedState(labels: ["Long List"])
        let target = AccessibilityTarget.identifier("target")
        var observedScopes: [SemanticObservationScope] = []
        var contextScopes: [SemanticObservationScope?] = []
        let runtime = heistRuntime(
            observations: [observedReady],
            execute: { _ in
                ActionResult.success(payload: .activate)
            },
            observedScopes: { scope in
                observedScopes.append(scope)
            },
            expectationContextScopes: { scope in
                contextScopes.append(scope)
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(target),
                expectationPolicy: .expect(ActionExpectation(
                    predicate: .exists(.label("Long List")),
                    timeout: 0.01
                )))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        XCTAssertEqual(contextScopes, [.visible])
        XCTAssertEqual(observedScopes, [.visible])
    }

    func testHeistActionExpectationWithExpiredDeadlineUsesActionInteractionTrace() async throws {
        let expectation = WaitStep(predicate: .changed(.screen()), timeout: try .milliseconds(1))
        let beforeState = await observedState(labels: ["Controls Demo"])
        let afterState = await observedState(labels: ["Buttons & Actions"])
        let beforeCapture = AccessibilityTrace.Capture(
            sequence: 1,
            interface: beforeState.interface,
            context: AccessibilityTrace.Context(screenId: "controls_demo")
        )
        let afterCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterState.interface,
            parentHash: beforeCapture.hash,
            context: AccessibilityTrace.Context(screenId: "buttons_actions"),
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [
                AccessibilityNotificationEvidence(
                    sequence: 1,
                    kind: .screenChanged,
                    timestamp: Date(timeIntervalSince1970: 0),
                    notificationData: .none,
                    associatedElement: .none
                ),
            ])
        )
        let trace = AccessibilityTrace(captures: [beforeCapture, afterCapture])
        XCTAssertEqual(
            trace.changeFacts.map(\.kind),
            [.elementsChanged, .screenChanged, .elementsChanged]
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(
                    payload: .activate,
observation: .settledTrace(
                        makeTestTraceEvidence(trace, completeness: .incomplete),
                        .settled(duration: 7)
                    )
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Controls Demo")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.settled, true)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.settleTimeMs, 7)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.accessibilityTrace, trace)
        XCTAssertEqual(step.actionEvidence?.expectationResult?.method, .wait)
        XCTAssertTrue(step.actionEvidence?.expectationResult?.outcome.isSuccess == true)
        XCTAssertEqual(step.actionEvidence?.expectationResult?.accessibilityTrace, trace)
        XCTAssertEqual(step.reportExpectation?.met, true)
        XCTAssertNil(step.reportExpectation?.actual)
    }

    func testHeistActionExpectationWithExpiredDeadlineRejectsUnsettledActionTrace() async throws {
        let expectation = WaitStep(predicate: .changed(.screen()), timeout: try .milliseconds(1))
        let beforeState = await observedState(labels: ["Controls Demo"])
        let afterState = await observedState(labels: ["Buttons & Actions"])
        let beforeCapture = AccessibilityTrace.Capture(
            sequence: 1,
            interface: beforeState.interface,
            context: AccessibilityTrace.Context(screenId: "controls_demo")
        )
        let afterCapture = AccessibilityTrace.Capture(
            sequence: 2,
            interface: afterState.interface,
            parentHash: beforeCapture.hash,
            context: AccessibilityTrace.Context(screenId: "buttons_actions"),
            transition: AccessibilityTrace.Transition(accessibilityNotifications: [
                AccessibilityNotificationEvidence(
                    sequence: 1,
                    kind: .screenChanged,
                    timestamp: Date(timeIntervalSince1970: 0),
                    notificationData: .none,
                    associatedElement: .none
                ),
            ])
        )
        let trace = AccessibilityTrace(captures: [beforeCapture, afterCapture])
        let runtime = heistRuntime(
            observations: [afterState],
            execute: { _ in
                ActionResult.success(
                    payload: .activate,
observation: .settledTrace(
                        makeTestTraceEvidence(trace, completeness: .incomplete),
                        .timedOut(duration: 7)
                    )
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Controls Demo")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.actionEvidence?.dispatchResult?.settled, false)
        XCTAssertFalse(step.actionEvidence?.expectationResult?.outcome.isSuccess == true)
        XCTAssertEqual(step.reportExpectation?.met, false)
    }

    func testHeistActionExpectationUsesWaitFailureDiagnostic() async throws {
        let expectation = WaitStep(
            predicate: .missing(.label("Loading")),
            timeout: 0.2
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(payload: .activate)
            },
            wait: { _ in
                ActionResult.failure(
                    payload: .wait,
                    failureKind: .timeout,
                    message: "timed out after 0.2s — expectation not met",
                        observation: .trace(makeTestTraceEvidence(
                            .noChangeForTests(elementCount: 1),
                            completeness: .incomplete
                        ))

                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Submit")),
                expectationPolicy: .expect(try ActionExpectation(expectation)))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.actionEvidence?.expectationResult?.outcome.failureKind, .timeout)
        XCTAssertEqual(step.reportExpectation?.met, false)
        XCTAssertEqual(step.reportExpectation?.actual, "timed out after 0.2s — expectation not met")
    }

    func testHeistSemanticObservationScopeUsesVisibleForPredicateSugarCases() async throws {
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [await observedState(labels: ["Home"])],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Home")),
                    body: [.warn(WarnStep(message: "home"))]
                ),
                PredicateCase(
                    predicate: .missing(.label("Login")),
                    body: [.warn(WarnStep(message: "not login"))]
                ),
            ])),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.visible])
    }

    func testHeistSemanticObservationScopeUsesVisibleForStateCases() async throws {
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [await observedState(labels: ["Loading"])],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Toast")),
                        body: [.warn(WarnStep(message: "toast"))]
                    ),
                ],
                elseBody: [.warn(WarnStep(message: "no toast"))]
            )),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.visible])
    }

    func testHeistSemanticObservationScopeKeepsStateCasesVisible() async throws {
        var observedScopes: [SemanticObservationScope] = []
        let runtime = heistRuntime(
            observations: [await observedState(labels: ["Loading"])],
            observedScopes: { observedScopes.append($0) }
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Home")),
                        body: [.warn(WarnStep(message: "home"))]
                    ),
                    PredicateCase(
                        predicate: .exists(.label("Toast")),
                        body: [.warn(WarnStep(message: "toast"))]
                    ),
                ],
                elseBody: [.warn(WarnStep(message: "unknown"))]
            )),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(observedScopes, [.visible])
    }

    func testHeistKeepsActiveObservationDemandThroughStateDependentStep() async throws {
        var demandDuringAction = false
        var demandDuringObservation = false
        let runtime = heistRuntime(
            observations: [await observedState(labels: ["Ready"])],
            execute: { _ in
                demandDuringAction = self.brains.vault.semanticObservationStream.hasActiveObservationDemand
                return ActionResult.success(payload: .activate)
            },
            observedScopes: { _ in
                demandDuringObservation = self.brains.vault.semanticObservationStream.hasActiveObservationDemand
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(.label("Submit")))),
            .conditional(try ConditionalStep(cases: [
                PredicateCase(
                    predicate: .exists(.label("Ready")),
                    body: [.warn(WarnStep(message: "ready"))]
                ),
            ])),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(demandDuringAction)
        XCTAssertTrue(demandDuringObservation)
        XCTAssertFalse(brains.vault.semanticObservationStream.hasActiveObservationDemand)
    }

    func testHeistKeepsActiveObservationDemandAcrossConsecutiveBareActions() async throws {
        var demandDuringActions: [Bool] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                demandDuringActions.append(self.brains.vault.semanticObservationStream.hasActiveObservationDemand)
                return ActionResult.success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(.label("1")))),
            .action(ActionStep(command: .activate(.label("2")))),
            .action(ActionStep(command: .activate(.label("3")))),
        ])

        _ = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertEqual(demandDuringActions, [true, true, true])
        XCTAssertFalse(brains.vault.semanticObservationStream.hasActiveObservationDemand)
    }

    func testIfStatePredicateDoesNotWaitForFutureObservation() async throws {
        let runtime = heistRuntime(observations: [
            await observedState(labels: ["Loading"]),
            await observedState(labels: ["Loading", "Toast"]),
        ])
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .exists(.label("Toast")),
                        body: [.warn(WarnStep(message: "toast"))]
                    ),
                ]
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertTrue(result.outcome.isSuccess)
        XCTAssertEqual(
            step.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.noMatch
        )
        XCTAssertEqual(step.caseSelectionEvidence?.selection.cases.first?.result.met, false)
    }

    private func actionVolumeObservation(value: String) -> InterfaceObservation {
        .makeForTests(elements: [
            (
                makeElement(label: "Volume", value: value, traits: .adjustable),
                HeistId(rawValue: "volume")
            ),
        ])
    }

}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
    }
}

#endif
