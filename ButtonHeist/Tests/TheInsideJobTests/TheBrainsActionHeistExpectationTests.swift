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
            observations: [observedState(labels: ["Home"])],
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
        inactiveBrains.vault.installObservationForTesting(.makeForTests(elements: [
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
        XCTAssertNil(inactiveBrains.vault.semanticObservationStream.latestCommittedObservation)
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

        isolatedBrains.vault.semanticObservationStream
            .commitDiscoveryObservationForTesting(beforeScreen)
        isolatedBrains.vault.semanticObservationStream
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
        let baselineEvent = isolatedBrains.vault.semanticObservationStream.commitVisibleObservationForTesting(baseline)
        let before = isolatedBrains.actionEvidenceProjector.projectBaseline(
            from: baselineEvent.settledObservation
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

        XCTAssertEqual(failedResult.accessibilityTrace.capturedAnnouncements.map(\.text), ["Action A"])

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
        XCTAssertEqual(successfulEvent.trace.capturedAnnouncements.map(\.text), ["Action B"])
        XCTAssertEqual(failedResult.accessibilityTrace.capturedAnnouncements.map(\.text), ["Action A"])
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
        let beforeEvent = isolatedBrains.vault.semanticObservationStream.commitVisibleObservationForTesting(beforeScreen)
        let afterEvent = isolatedBrains.vault.semanticObservationStream.commitVisibleObservationForTesting(afterScreen)
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

    func testActionExpectationUsesSettlementEvidence() async throws {
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
        saveObject.onActivation = {
            _ = self.brains.vault.semanticObservationStream
                .commitVisibleObservationForTesting(transient)
            _ = self.brains.vault.semanticObservationStream
                .commitVisibleObservationForTesting(after)
            self.visibleObservationSource.observation = after
        }
        announceObject.onActivation = {
            self.brains.vault.accessibilityNotifications.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload("Confirmed" as NSString),
                associatedElement: .none
            )
        }
        installSyntheticObservation(before)
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Save")),
                expectationPolicy: .expect(try ActionExpectation(WaitStep(
                    predicate: .changed(.elements([.appeared(.label("Saved"))])),
                    timeout: .milliseconds(1)
                )))
            )),
            .action(ActionStep(
                command: .activate(.label("Announce")),
                expectationPolicy: .expect(try ActionExpectation(WaitStep(
                    predicate: .announcement("Confirmed"),
                    timeout: .milliseconds(1)
                )))
            )),
        ])

        let result = await brains.executeHeistPlan(plan)
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
            elementTrace.captures.last?.interface.projectedElements.compactMap(\.label),
            ["Save", "Announce", "Saved"]
        )
        XCTAssertEqual(steps.last?.actionEvidence?.expectationResult?.announcement, "Confirmed")
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
        saveObject.onActivation = {
            _ = self.brains.vault.semanticObservationStream
                .commitVisibleObservationForTesting(transient)
            _ = self.brains.vault.semanticObservationStream
                .commitVisibleObservationForTesting(after)
            self.visibleObservationSource.observation = after
            self.brains.vault.accessibilityNotifications.recordForTesting(
                code: 1008,
                notificationData: CapturedAccessibilityNotificationPayload("Saved" as NSString),
                associatedElement: .none
            )
        }
        installSyntheticObservation(before)

        let action = await brains.executeHeistPlan(try HeistPlan(body: [
            .action(ActionStep(command: .activate(.label("Save")))),
        ]))
        let appeared = await brains.performWait(step: try resolvedWait(WaitStep(
            predicate: .changed(.elements([.appeared(.label("Saved"))])),
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

        XCTAssertTrue(action.outcome.isSuccess, action.message ?? "action heist failed")
        XCTAssertEqual(saveObject.activationCount, 1)
        for result in [appeared, exists, announcement] {
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
        registerScreenElement(
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
            expectationContextScope: .visible
        )

        XCTAssertFalse(execution.result.outcome.isSuccess)
        XCTAssertNil(execution.actionExpectationContext)
    }

    func testWaitResultTimeoutRetainsFinalSettledEvidence() async throws {
        let isolatedBrains = TheBrains(tripwire: TheTripwire())
        let knownScreen = InterfaceObservation.makeForTests(elements: [
            (makeElement(label: "Known"), "known"),
        ])
        isolatedBrains.vault.installObservationForTesting(knownScreen)

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

    func testHeistActionExpectationRequiresWaitObservationEvidence() async throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            .makeForTests()
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let expectation = WaitStep(
            predicate: .changed(.elements()),
            timeout: try .milliseconds(1)
        )
        let expectationContext = ActionExpectationContext(
            preActionCapture: baseline,
            throughObservationCursor: baseline.cursor,
            announcementCursor: .origin
        )
        var waitRequests: [TheBrains.HeistRuntimeWaitRequest] = []
        var contextScopes: [SemanticObservationScope?] = []
        let runtime = heistRuntime(
            observations: [],
            actionExpectationContext: expectationContext,
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
        let heistResult = try XCTUnwrap(result.resultPayload)
        let step = try XCTUnwrap(heistResult.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(contextScopes.first, .visible)
        XCTAssertEqual(waitRequests.count, 1)
        if case .actionEndpoint(
            let request,
            trace: nil,
            context: let capturedContext
        )? = waitRequests.first {
            XCTAssertEqual(request, try resolvedWait(expectation))
            XCTAssertEqual(capturedContext, expectationContext)
        } else {
            XCTFail("Expected action endpoint wait request")
        }
        XCTAssertEqual(step.actionEvidence?.expectationResult?.method, .wait)
        XCTAssertEqual(step.reportExpectation?.met, false)
        XCTAssertNil(step.actionEvidence?.expectationResult?.accessibilityTrace)
    }

    func testActionExpectationRejectsUnavailableObservationBound() async throws {
        let baselineEvent = brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            .makeForTests()
        )
        let baseline = try XCTUnwrap(baselineEvent.settledCapture)
        let unavailableCursor = ObservationCursor(
            generation: baseline.cursor.generation,
            scope: baseline.cursor.scope,
            sequence: baseline.cursor.sequence + 1,
            capture: baseline.capture,
            notificationSequence: baseline.cursor.notificationSequence
        )
        let context = ActionExpectationContext(
            preActionCapture: baseline,
            throughObservationCursor: unavailableCursor,
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
        let observedReady = observedState(labels: ["Long List"])
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
        let beforeState = observedState(labels: ["Controls Demo"])
        let afterState = observedState(labels: ["Buttons & Actions"])
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
        let beforeState = observedState(labels: ["Controls Demo"])
        let afterState = observedState(labels: ["Buttons & Actions"])
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
            observations: [observedState(labels: ["Home"])],
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
            observations: [observedState(labels: ["Loading"])],
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
            observations: [observedState(labels: ["Loading"])],
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
            observations: [observedState(labels: ["Ready"])],
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
            observedState(labels: ["Loading"]),
            observedState(labels: ["Loading", "Toast"]),
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
            HeistCaseSelectionOutcome.elseBranch(reason: .noMatch)
        )
        XCTAssertEqual(step.caseSelectionEvidence?.selection.cases.first?.result.met, false)
    }

}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
    }
}

#endif
