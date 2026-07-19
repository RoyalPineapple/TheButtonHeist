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
        let observedReady = observedState(labels: ["Ready"])
        let target = AccessibilityTarget.identifier("target")
        var dispatchedTypes: [HeistActionCommandType] = []
        var waitRequests: [TheBrains.HeistRuntimeWaitRequest] = []
        let runtime = heistRuntime(
            observations: [],
            execute: { command in
                dispatchedTypes.append(command.runtimeType)
                return ActionResult.success(method: .activate, message: command.runtimeType.rawValue)
            },
            wait: { request in
                waitRequests.append(request)
                return ActionResult.success(
                    method: .wait,
                        observation: .trace(makeTestTraceEvidence(
                            AccessibilityTrace(capture: observedReady.capture),
                            completeness: .incomplete
                        ))

                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(target))),
            .wait(WaitStep(
                predicate: .exists(.label("Ready")),
                timeout: .milliseconds(1)
            )),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)
        let heist: HeistExecutionResult = try XCTUnwrap(result.heistExecutionPayload)
        let actionStep = try XCTUnwrap(heist.steps.first)
        let waitStep = try XCTUnwrap(heist.steps.dropFirst().first)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        XCTAssertEqual(dispatchedTypes, [.activate])
        XCTAssertEqual(waitRequests.count, 1)
        if case .standalone(let request, let startedAt)? = waitRequests.first {
            XCTAssertEqual(request.predicate, try resolvedPredicate(.exists(.label("Ready"))))
            XCTAssertLessThanOrEqual(startedAt, CFAbsoluteTimeGetCurrent())
        } else {
            XCTFail("Expected standalone wait request")
        }
        XCTAssertEqual(heist.steps.map(\.kind), [HeistExecutionStepKind.action, .wait])
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
            actions: [.activate]
        )
        let runtime = heistRuntime(
            observations: [],
            execute: { _ in
                ActionResult.success(
                    method: .activate,
                    observation: .none,
                    subjectEvidence: ActionSubjectEvidence(
                        source: .resolvedSemanticTarget,
                        target: resolvedTarget,
                        element: subject,
                        resolution: ActionSubjectResolution(origin: .visible)
                    )
                )
            }
        )
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(target))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.outcome.isSuccess, result.message ?? "heist failed")
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let warning = try XCTUnwrap(heist.steps.first?.actionEvidence?.warning)
        XCTAssertEqual(warning.code, "activation_weak_affordance_evidence")
        XCTAssertEqual(
            warning.message,
            "activate succeeded, but the target does not advertise a primary activation affordance"
        )
        XCTAssertEqual(warning.evidence, #"label="Checkout" traits=[staticText] actions=[activate]"#)
        XCTAssertEqual(heist.warnings, [])
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
                    method: .typeText,
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
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        let warning = try XCTUnwrap(heist.steps.first?.actionEvidence?.warning)
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
        var dispatchedTypes: [HeistActionCommandType] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedTypes.append(command.runtimeType)
            if case .takeScreenshot = command {
                return ActionResult.success(payload: .screenshot(screenshot))
            }
            return ActionResult.failure(
                method: .activate,
                errorKind: .actionFailed,
                message: "activate failed",
            )
        }
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(target))),
        ])

        let result = await brains.executeHeistPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.outcome.isSuccess)
        XCTAssertEqual(dispatchedTypes, [.activate, .takeScreenshot])
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        XCTAssertEqual(heist.abortedAtPath, "$.body[0]")
        XCTAssertEqual(heist.executedTopLevelStepCount, 1)
        XCTAssertEqual(heist.outputReceiptNodes.count, 2)
        XCTAssertEqual(heist.steps.map(\.path), ["$.body[0]", "$.body[0].failure.actions[0]"])
        let screenshotStep = try XCTUnwrap(heist.steps.last)
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
        var dispatchedTypes: [HeistActionCommandType] = []
        let runtime = heistRuntime(observations: []) { command in
            dispatchedTypes.append(command.runtimeType)
            if case .takeScreenshot = command {
                return ActionResult.success(method: .takeScreenshot)
            }
            return ActionResult.failure(
                method: .activate,
                errorKind: .actionFailed,
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
        XCTAssertEqual(dispatchedTypes, [.activate, .takeScreenshot])
        let heist = try XCTUnwrap(result.heistExecutionPayload)
        XCTAssertEqual(heist.abortedAtPath, "$.body[0]")
        XCTAssertEqual(heist.steps.map(\.path), [
            "$.body[0]",
            "$.body[1]",
            "$.body[2]",
            "$.body[0].failure.actions[0]",
        ])
        XCTAssertEqual(heist.steps.map(\.status), [.failed, .skipped, .skipped, .passed])
        let skippedInlineHeist = try XCTUnwrap(heist.steps.dropFirst(2).first)
        XCTAssertEqual(skippedInlineHeist.children.map(\.status), [.skipped])
    }

}

private extension ActionResult {
    var heistExecutionPayload: HeistExecutionResult? {
        guard case .heistExecution(let result) = payload else { return nil }
        return result
    }
}

#endif
