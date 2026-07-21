#if canImport(UIKit)
import UIKit
import XCTest
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsActionTests {
    func testScreenshotAdmitsOnceThenCapturesCursorBeforeDispatch() async throws {
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white
        let label = UILabel(frame: CGRect(x: 40, y: 120, width: 240, height: 44))
        label.isAccessibilityElement = true
        label.accessibilityLabel = "Continuity screenshot"
        rootView.addSubview(label)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        brains.stopSemanticObservation()
        let observation = try XCTUnwrap(TheVault.captureVisibleObservation(from: brains.vault))
        brains.vault.resetInterfaceForLifecycle()
        var baselineAdmissionCount = 0
        var admissionCompletionCursor: AccessibilityNotificationCursor?
        var admissionNotificationSequence: UInt64?
        brains.vault.semanticObservationStream.settleVisibleObservation = { vault, _, _, _, _ in
            baselineAdmissionCount += 1
            let notificationCursor = vault.accessibilityNotifications.cursor()
            UIAccessibility.post(
                notification: .announcement,
                argument: "Screenshot admission complete"
            )
            for _ in 0..<100 {
                if let event = vault.accessibilityNotifications.checkpoint(
                    after: notificationCursor,
                    selection: .all
                ).events.first(where: { $0.kind == .announcement }) {
                    admissionNotificationSequence = event.sequence
                    break
                }
                await Task.yield()
                _ = await Task.cancellableSleep(for: .milliseconds(10))
            }
            admissionCompletionCursor = vault.accessibilityNotifications.cursor()
            vault.observeInterface(observation)
            return SettleSession.Result(
                outcome: .settled(timeMs: baselineAdmissionCount),
                events: [],
                finalObservation: SettleSessionFinalObservation(observation: observation),
                elementsByKey: [:],
                tripwireSignal: vault.semanticObservationStream.currentTripwireSignal()
            )
        }
        brains.startSemanticObservation()

        let execution = await brains.executeRuntimeActionWithBaseline(
            .takeScreenshot,
            expectationBaselineScope: .visible
        )

        XCTAssertTrue(execution.result.outcome.isSuccess)
        XCTAssertEqual(baselineAdmissionCount, 1)
        let boundary = try XCTUnwrap(execution.successfulActionBoundary)
        let notificationSequence = try XCTUnwrap(admissionNotificationSequence)
        XCTAssertLessThanOrEqual(notificationSequence, boundary.notificationCursor.sequence)
        XCTAssertEqual(boundary.notificationCursor, admissionCompletionCursor)
        XCTAssertEqual(execution.expectationBaseline, boundary.settledCapture)
        guard case .screenshot(let payload?) = execution.result.payload else {
            return XCTFail("Expected screenshot payload")
        }
        XCTAssertEqual(payload.interface, boundary.settledCapture.capture.interface)
    }

    func testSingleSuccessfulActionReturnsItsEvidenceContinuity() async throws {
        let boundary = try continuityBoundary(notificationSequence: 1)
        let runtime = heistRuntime(
            observations: [],
            actionBoundaries: [boundary]
        )
        let plan = try HeistPlan(body: [actionStep(label: "First")])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        try assertResult(result, registered: boundary)
    }

    func testMultipleSuccessfulActionsReturnTheLastEvidenceContinuity() async throws {
        let first = try continuityBoundary(notificationSequence: 1)
        let second = try continuityBoundary(notificationSequence: 2)
        let runtime = heistRuntime(
            observations: [],
            actionBoundaries: [first, second]
        )
        let plan = try HeistPlan(body: [
            actionStep(label: "First"),
            actionStep(label: "Second"),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        try assertResult(result, registered: second)
    }

    func testFailedDispatchAndAutomaticScreenshotDoNotReplaceLastSuccessfulBoundary() async throws {
        let first = try continuityBoundary(notificationSequence: 1)
        let second = try continuityBoundary(notificationSequence: 2)
        let failureScreenshot = try continuityBoundary(notificationSequence: 3)
        var dispatchIndex = 0
        let runtime = heistRuntime(
            observations: [],
            actionBoundaries: [first, second, failureScreenshot],
            execute: { command in
                if case .takeScreenshot = command {
                    return .success(payload: .screenshot(nil))
                }
                defer { dispatchIndex += 1 }
                if dispatchIndex == 1 {
                    return .failure(
                        payload: .activate,
                        failureKind: .actionFailed,
                        message: "scripted dispatch failure"
                    )
                }
                return .success(payload: .activate)
            }
        )
        let plan = try HeistPlan(body: [
            actionStep(label: "First"),
            actionStep(label: "Second"),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
        try assertResult(result, registered: first)
    }

    func testNoSuccessfulActionReturnsNoEvidenceContinuity() async throws {
        let boundary = try continuityBoundary(notificationSequence: 1)
        let runtime = heistRuntime(
            observations: [],
            actionBoundaries: [boundary],
            execute: { _ in
                .failure(
                    payload: .activate,
                    failureKind: .actionFailed,
                    message: "scripted dispatch failure"
                )
            }
        )
        let plan = try HeistPlan(body: [actionStep(label: "Failure")])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertNil(try heistResult(from: result).evidenceContinuity)
    }

    func testSuccessfulDispatchRetainsContinuityWhenItsExpectationFails() async throws {
        let boundary = try continuityBoundary(notificationSequence: 1)
        let runtime = heistRuntime(
            observations: [],
            actionBoundaries: [boundary],
            wait: { _ in
                .failure(
                    payload: .wait,
                    failureKind: .timeout,
                    message: "scripted expectation failure"
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(
                command: .activate(.label("Save")),
                expectationPolicy: .expect(try ActionExpectation(WaitStep(
                    predicate: .exists(.label("Saved")),
                    timeout: .milliseconds(1)
                )))
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
        try assertResult(result, registered: boundary)
    }

    func testNestedExecutionReducesLastSuccessfulBoundaryInActualOrder() async throws {
        let boundaries = try (1...5).map { try continuityBoundary(notificationSequence: UInt64($0)) }
        let runtime = heistRuntime(
            observations: [observedState(labels: ["Ready"])],
            actionBoundaries: boundaries
        )
        let plan = try HeistPlan(
            definitions: [
                try HeistPlan(name: "finish", body: [actionStep(label: "Fifth")]),
            ],
            body: [
                actionStep(label: "First"),
                .conditional(try ConditionalStep(cases: [
                    PredicateCase(
                        predicate: .exists(.label("Ready")),
                        body: [actionStep(label: "Second")]
                    ),
                ])),
                .forEachString(try ForEachStringStep(
                    values: ["Third", "Fourth"],
                    parameter: "item",
                    body: [
                        .action(ActionStep(command: .activate(.label(
                            HeistReferenceName(stringLiteral: "item")
                        )))),
                    ]
                )),
                .invoke(HeistInvocationStep(path: "finish")),
            ]
        )

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess)
        try assertResult(result, registered: boundaries[4])
    }

    private func continuityBoundary(
        notificationSequence: UInt64
    ) throws -> EvidenceContinuity.Boundary {
        let baseline = observedState(labels: ["State \(notificationSequence)"])
        let sequence = try XCTUnwrap(baseline.settledObservationSequence)
        let settledCapture = try XCTUnwrap(
            brains.vault.semanticObservationStream.settledCapture(
                scope: .visible,
                at: sequence
            )
        )
        return brains.evidenceContinuityStore.captureBoundary(
            settledCapture: settledCapture,
            notificationCursor: AccessibilityNotificationCursor(sequence: notificationSequence)
        )
    }

    private func actionStep(label: String) -> HeistStep {
        .action(ActionStep(command: .activate(.label(label))))
    }

    private func assertResult(
        _ actionResult: ActionResult,
        registered expectedBoundary: EvidenceContinuity.Boundary,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let reference = try XCTUnwrap(
            heistResult(from: actionResult).evidenceContinuity,
            file: file,
            line: line
        )
        let admission = brains.evidenceContinuityStore.admit(
            reference,
            for: .settledObservation,
            retainsBoundary: { _ in true }
        )
        guard case .candidate(let admittedReference, let boundary) = admission else {
            return XCTFail("Expected a registered evidence continuity boundary", file: file, line: line)
        }
        XCTAssertEqual(admittedReference, reference, file: file, line: line)
        XCTAssertEqual(boundary, expectedBoundary, file: file, line: line)
    }

    private func heistResult(from actionResult: ActionResult) throws -> HeistResult {
        guard case .heist(let result?) = actionResult.payload else {
            throw EvidenceContinuityExecutionTestFailure()
        }
        return result
    }
}

private struct EvidenceContinuityExecutionTestFailure: Error {}
#endif // canImport(UIKit)
