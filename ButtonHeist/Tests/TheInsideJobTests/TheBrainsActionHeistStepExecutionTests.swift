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

    func testHeistActionAndWaitStepsUseSeparateRuntimeTransitions() async throws {
        let observedReady = await observedState(labels: ["Ready"])
        let target = AccessibilityTarget.identifier("target")
        var dispatchedCommands: [ResolvedHeistActionCommand] = []
        var waitCommands: [Settlement.Command] = []
        let runtime = heistRuntime(
            observations: [observedReady],
            execute: { command in
                dispatchedCommands.append(command)
                return ActionResult.success(payload: .activate)
            },
            observedWaitCommands: { waitCommands.append($0) }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(target))),
            .wait(WaitStep(
                predicate: .exists(.label("Ready")),
                timeout: .milliseconds(1)
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heistResult: HeistResult = try XCTUnwrap(result.resultPayload)
        let actionStep = try XCTUnwrap(heistResult.steps.first)
        let waitStep = try XCTUnwrap(heistResult.steps.dropFirst().first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        XCTAssertEqual(dispatchedCommands, [.activate(try target.resolve(in: .empty))])
        XCTAssertEqual(waitCommands.count, 1)
        XCTAssertEqual(
            waitCommands.first?.predicate?.resolved,
            try resolvedPredicate(.exists(.label("Ready")))
        )
        XCTAssertEqual(waitCommands.first?.trigger, .observation)
        XCTAssertEqual(waitCommands.first?.baseline, .capture)
        XCTAssertEqual(heistResult.steps.map(\.kind), [HeistExecutionStepKind.action, .wait])
        XCTAssertNotNil(actionStep.actionEvidence)
        XCTAssertNil(actionStep.waitEvidence)
        XCTAssertNil(waitStep.actionEvidence)
        let waitEvidence = try XCTUnwrap(waitStep.waitEvidence)
        XCTAssertTrue(waitEvidence.expectation.met)
    }

    func testHeistActivateRecordsWeakAffordanceWarningOnSuccessfulActionEvidence() async throws {
        let target = AccessibilityTarget.label("Checkout")
        let resolvedTarget = try target.resolve(in: .empty)
        let subject = makeTestHeistElement(
            label: "Checkout",
            traits: [.staticText],
            actions: []
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.activationSuccess(
                    observation: .none,
                    subjectEvidence: ActionSubjectEvidence(
                        source: .resolvedSemanticTarget,
                        target: resolvedTarget,
                        element: subject,
                        resolution: ActionSubjectResolution(origin: .visible)
                    ),
                    activationTrace: ActivationTrace(.activationPointFallback(
                        axActivateReturned: false,
                        tapActivationPoint: ScreenPoint(x: 50, y: 50),
                        tapActivationSucceeded: true
                    ), implementsAccessibilityActivation: false)
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(target))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        let heistResult = try XCTUnwrap(result.resultPayload)
        let warning = try XCTUnwrap(heistResult.steps.first?.actionEvidence?.warning)
        XCTAssertEqual(warning.code, "activation_weak_affordance_evidence")
        XCTAssertEqual(
            warning.message,
            "target advertised no interactivity and implements no activation; "
                + "activate proceeded as VoiceOver would"
        )
        XCTAssertEqual(warning.evidence, #"label="Checkout" traits=[staticText] actions=[]"#)
        XCTAssertEqual(HeistReport.project(result: heistResult).warnings, [])
    }

    func testHeistTypeTextRecordsWeakAffordanceWarningOnSuccessfulActionEvidence() async throws {
        let target = AccessibilityTarget.label("Notes")
        let resolvedTarget = try target.resolve(in: .empty)
        let subject = makeTestHeistElement(
            label: "Notes",
            traits: [.staticText],
            actions: []
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(
                    payload: .typeText(nil),
                    observation: .none,
                    subjectEvidence: ActionSubjectEvidence(
                        source: .textInputTarget,
                        target: resolvedTarget,
                        element: subject,
                        resolution: ActionSubjectResolution(origin: .visible)
                    )
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .typeText(
                text: "hello",
                target: target
            ))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        let heistResult = try XCTUnwrap(result.resultPayload)
        let warning = try XCTUnwrap(heistResult.steps.first?.actionEvidence?.warning)
        XCTAssertEqual(warning.code, "text_entry_weak_affordance_evidence")
        XCTAssertEqual(
            warning.message,
            "typeText succeeded, but the target does not advertise a text-input trait"
        )
        XCTAssertEqual(warning.evidence, #"label="Notes" traits=[staticText] actions=[]"#)
    }

    func testHeistFailureRecordsScreenshotAsActionEvidence() async throws {
        let target = AccessibilityTarget.identifier("target")
        let screenshot = ScreenPayload(
            pngData: "png",
            width: 10,
            height: 20,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: Interface(timestamp: Date(timeIntervalSince1970: 0), tree: [])
        )
        var dispatchedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedCommands.append(command)
            if case .takeScreenshot = command {
                return ActionResult.success(payload: .screenshot(screenshot))
            }
            return ActionResult.failure(
                payload: .activate,
                failureKind: .actionFailed,
                message: "activate failed",
            )
        }
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(target))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(dispatchedCommands, [
            .activate(try target.resolve(in: .empty)),
            .takeScreenshot,
        ])
        let heistResult = try XCTUnwrap(result.resultPayload)
        let report = HeistReport.project(result: heistResult)
        XCTAssertEqual(heistResult.abortedAtPath, "$.body[0]")
        XCTAssertEqual(report.summary.executedTopLevelStepCount, 1)
        XCTAssertEqual(heistResult.outputNodes.count, 2)
        XCTAssertEqual(heistResult.steps.map(\.path), ["$.body[0]", "$.body[0].failure.actions[0]"])
        let screenshotStep = try XCTUnwrap(heistResult.steps.last)
        XCTAssertEqual(screenshotStep.kind, .action)
        XCTAssertEqual(screenshotStep.status, .passed)
        XCTAssertEqual(screenshotStep.actionCommand, .takeScreenshot)
        guard case .screenshot(let payload) = screenshotStep.actionEvidence?.dispatchResult?.payload else {
            return XCTFail("Expected screenshot action payload")
        }
        XCTAssertEqual(payload, screenshot)
    }

    func testHeistFailurePhaseSkipsRemainingStepsWithoutDispatchingActions() async throws {
        let target = AccessibilityTarget.identifier("target")
        var dispatchedCommands: [ResolvedHeistActionCommand] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedCommands.append(command)
            if case .takeScreenshot = command {
                return ActionResult.success(payload: .screenshot(nil))
            }
            return ActionResult.failure(
                payload: .activate,
                failureKind: .actionFailed,
                message: "activate failed",
            )
        }
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(target))),
            .action(ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "not dispatched")))),
            .heist(try HeistPlan(body: [
                .action(ActionStep(command: .dismissKeyboard)),
            ])),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(dispatchedCommands, [
            .activate(try target.resolve(in: .empty)),
            .takeScreenshot,
        ])
        let heistResult = try XCTUnwrap(result.resultPayload)
        XCTAssertEqual(heistResult.abortedAtPath, "$.body[0]")
        XCTAssertEqual(heistResult.steps.map(\.path), [
            "$.body[0]",
            "$.body[1]",
            "$.body[2]",
            "$.body[0].failure.actions[0]",
        ])
        XCTAssertEqual(heistResult.steps.map(\.status), [.failed, .skipped, .skipped, .passed])
        let skippedInlineHeist = try XCTUnwrap(heistResult.steps.dropFirst(2).first)
        XCTAssertEqual(skippedInlineHeist.children.map(\.status), [.skipped])
    }

}

private extension ActionResult {
    var resultPayload: HeistResult? {
        guard case .heist(let result) = payload else { return nil }
        return result
    }
}

#endif
