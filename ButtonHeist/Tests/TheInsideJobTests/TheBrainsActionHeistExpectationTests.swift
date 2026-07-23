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

    func testHeistActionExpectationUsesWaitFailureDiagnostic() async throws {
        let observed = await observedState(labels: ["Loading"])
        var projectedActual: String?
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in ActionResult.success(payload: .activate) },
            settle: { command in
                let settlement = scriptedSettlement(command, observation: observed)
                projectedActual = Settlement.ResultProjector.projectWait(settlement).expectation.actual
                return settlement
            }
        )
        let expectation = WaitStep(
            predicate: .missing(.label("Loading")),
            timeout: 0.2
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Submit")),
                expectationPolicy: .expect(try ActionExpectation(expectation))
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let step = try XCTUnwrap(result.resultPayload?.steps.first)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(step.actionEvidence?.expectationResult?.outcome.failureKind, .timeout)
        XCTAssertEqual(step.reportExpectation?.met, false)
        XCTAssertEqual(step.reportExpectation?.actual, projectedActual)
        XCTAssertNotNil(projectedActual)
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

        XCTAssertTrue(action.outcome.isSuccess, action.message ?? "action heist failed")
        XCTAssertEqual(action.resultPayload?.steps.first?.reportExpectation?.met, true)
        XCTAssertEqual(saveObject.activationCount, 1)
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

    func testActionExpectationStartsWithVisibleScope() async throws {
        let targetObject = ActionActivationOverrideView()
        await installSyntheticObservation(.makeForTests(
            elements: [
                (makeElement(label: "Target", traits: .button), HeistId(rawValue: "target")),
                (makeElement(label: "Long List"), HeistId(rawValue: "long_list")),
            ],
            objects: [HeistId(rawValue: "target"): targetObject]
        ))
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Target")),
                expectationPolicy: .expect(ActionExpectation(
                    predicate: .exists(.label("Long List")),
                    timeout: 1
                ))
            )),
        ])

        let result = await brains.executeHeistPlan(plan)
        let step = try XCTUnwrap(result.resultPayload?.steps.first)
        let expectationResult = try XCTUnwrap(step.actionEvidence?.expectationResult)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        XCTAssertEqual(targetObject.activationCount, 1)
        XCTAssertTrue(expectationResult.evidence.settlement?.settled == true)
        let labels = expectationResult.accessibilityTrace?.captures.last?.interface.projectedElements.map(\.label)
        XCTAssertEqual(labels, ["Target", "Long List"])
    }

    func testHeistKeepsActiveObservationDemandThroughStateDependentStep() async throws {
        var demandDuringAction = false
        var demandDuringSettledEvidence = false
        let event = await brains.vault.semanticObservationStream.commitVisibleObservationForTesting(
            .makeForTests(elements: [(makeElement(label: "Ready"), HeistId(rawValue: "ready"))])
        )
        let runtime = TheBrains.HeistExecutionRuntime(
            execute: { command, _ in
                demandDuringAction = self.brains.vault.semanticObservationStream.hasActiveObservationDemand
                let result = ActionResult.success(payload: command.resultPayload)
                return RuntimeActionExecution(result: result, actionExpectationContext: nil)
            },
            settle: { command in
                XCTAssertEqual(command.observationScope, .visible)
                demandDuringSettledEvidence = self.brains.vault.semanticObservationStream.hasActiveObservationDemand
                return scriptedSettlement(command, observation: event)
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
        XCTAssertTrue(demandDuringSettledEvidence)
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
        let stream = brains.vault.semanticObservationStream
        let current = await stream.commitVisibleObservationForTesting(.makeForTests(elements: [
            (makeElement(label: "Loading"), HeistId(rawValue: "loading")),
        ]))
        let future = await stream.commitVisibleObservationForTesting(.makeForTests(elements: [
            (makeElement(label: "Loading"), HeistId(rawValue: "loading")),
            (makeElement(label: "Toast"), HeistId(rawValue: "toast")),
        ]))
        let observations = [current, future]
        var observationCount = 0
        let runtime = TheBrains.HeistExecutionRuntime(
            execute: { _, _ in
                preconditionFailure("Conditional heist must not dispatch an action")
            },
            settle: { command in
                defer { observationCount += 1 }
                return scriptedSettlement(
                    command,
                    observation: observations[observationCount]
                )
            }
        )
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
        XCTAssertEqual(observationCount, 1)
        XCTAssertEqual(
            step.caseSelectionEvidence?.selection.outcome,
            HeistCaseSelectionOutcome.noMatch
        )
        XCTAssertEqual(step.caseSelectionEvidence?.selection.cases.first?.result.met, false)
    }

    func testZeroTimeUnsequencedEvidenceReadsCurrentSettledObservation() async {
        let current = await brains.vault.semanticObservationStream
            .commitVisibleObservationForTesting(.makeForTests(elements: [
                (makeElement(label: "Current"), HeistId(rawValue: "current")),
            ]))

        let event = await brains.interactionCoordinator.settledEvent(
            scope: .visible,
            after: nil,
            timeout: 0
        )

        XCTAssertEqual(event?.moment, current.moment)
        XCTAssertEqual(
            event?.trace.captures.last?.interface.projectedElements.map(\.label),
            ["Current"]
        )
    }

}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
    }
}

#endif
