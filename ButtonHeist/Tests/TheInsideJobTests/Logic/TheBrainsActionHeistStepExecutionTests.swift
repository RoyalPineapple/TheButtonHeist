#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class HeistMachineStepExecutionTests: XCTestCase {
    func testBareActionUsesStandardPolicyBudgetAndOneTypedRequestPipeline() throws {
        let policy = ActionExpectationTimeoutPolicy(standard: 3, screenTransition: 12)
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
        ])
        var machine = try HeistExecution.Machine(
            plan: plan,
            actionExpectationTimeoutPolicy: policy
        )
        let observation = try XCTUnwrap(machine.start().singleBeginObservationRequest)

        XCTAssertEqual(
            observation.request.timeout,
            .seconds(policy.standard.seconds)
        )

        var driver = try HeistMachineTestDriver(
            plan: plan,
            actionExpectationTimeoutPolicy: policy,
            script: MachineRunScript(events: [.noChange])
        )

        let completion = try driver.run()

        XCTAssertEqual(completion.steps.map(\.status), [.passed])
        XCTAssertEqual(driver.requests.map(\.kind), [
            .beginObservation,
            .dispatch,
            .finishObservation,
        ])
        XCTAssertEqual(Array(driver.history), [.noChange])
    }

    func testRuntimePolicyResolvesStandardScreenAndExplicitExpectationBudgets() throws {
        let policy = ActionExpectationTimeoutPolicy(standard: 3, screenTransition: 12)
        let explicitTimeout = try WaitTimeout.seconds(7)
        let cases: [(
            name: String,
            predicate: AccessibilityPredicate,
            timeout: ActionExpectation.Timeout,
            expected: WaitTimeout
        )] = [
            ("standard", .exists(.label("Done")), .sessionDefault, policy.standard),
            ("screen", .screenChanged, .sessionDefault, policy.screenTransition),
            ("explicit", .screenChanged, .explicit(explicitTimeout), explicitTimeout),
        ]

        for expectationCase in cases {
            let plan = try HeistPlan(body: [
                .action(ActionStep(
                    command: .dismiss,
                    expectationPolicy: .expect(ActionExpectation(
                        predicate: expectationCase.predicate,
                        timeout: expectationCase.timeout
                    ))
                )),
            ])
            var machine = try HeistExecution.Machine(
                plan: plan,
                actionExpectationTimeoutPolicy: policy
            )
            let observation = try XCTUnwrap(
                machine.start().singleBeginObservationRequest,
                expectationCase.name
            )

            XCTAssertEqual(
                observation.request.timeout,
                .seconds(expectationCase.expected.seconds),
                expectationCase.name
            )
        }
    }

    func testStaleAndDuplicateDispatchCompletionsCannotAdvanceAction() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
        ])
        var machine = try HeistExecution.Machine(plan: plan)
        let observation = try XCTUnwrap(machine.start().singleBeginObservationRequest)
        let dispatchRequest = try XCTUnwrap(
            machine.advance(.observationBegan(
                observation.id,
                baseline: nil
            )).singleDispatchRequest
        )
        guard case .wait = machine.advance(.observationBegan(
            observation.id,
            baseline: makeTestObservationSnapshot(labels: ["Late"])
        )) else {
            return XCTFail("A duplicate observation receipt must be ignored")
        }

        guard case .wait = machine.advance(.dispatchCompleted(
            HeistExecution.RequestID(rawValue: dispatchRequest.id.rawValue + 1),
            .success(payload: .dismiss)
        )) else {
            return XCTFail("A stale dispatch completion must be ignored")
        }
        guard case .wait = machine.advance(.dispatchCompleted(
            dispatchRequest.id,
            .success(payload: .dismiss)
        )) else {
            return XCTFail("The admitted dispatch completion must await settlement")
        }
        guard case .wait = machine.advance(.dispatchCompleted(
            dispatchRequest.id,
            .failure(.dismiss, message: "duplicate")
        )) else {
            return XCTFail("A duplicate dispatch completion must be ignored")
        }
        XCTAssertEqual(machine.activeLeaf?.expectationIsSatisfied, false)
        guard case .action(let leaf) = machine.activeLeaf else {
            return XCTFail("The admitted action must remain active")
        }
        XCTAssertEqual(leaf.dispatch?.success, true)
    }

    func testHostBaselineStartsActionWithoutSecondSnapshotRequest() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
        ])
        var machine = try HeistExecution.Machine(plan: plan)
        let observation = try XCTUnwrap(machine.start().singleBeginObservationRequest)
        let dispatch = try XCTUnwrap(machine.advance(.observationBegan(
            observation.id,
            baseline: makeTestObservationSnapshot(labels: ["Before"])
        )).singleDispatchRequest)

        XCTAssertEqual(dispatch.id, observation.id)
    }

    func testDispatchFailureProducesFailedStepAndSkipsSibling() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
            .warn(WarnStep(message: "later")),
        ])
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(
                events: [.noChange],
                dispatchResults: [
                    .failure(.dismiss, message: "dismiss unavailable"),
                ]
            )
        )

        let completion = try driver.run()

        XCTAssertEqual(completion.steps.map(\.status), [.failed, .skipped])
        XCTAssertEqual(completion.steps.first?.actionEvidence?.result?.outcome.failureKind, .actionFailed)
        XCTAssertEqual(completion.abortedAtPath, completion.steps.first?.path)
    }

    func testCancelledActionIsTerminalFailure() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
            .warn(WarnStep(message: "later")),
        ])
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(
                events: [.noChange, .noChange],
                leafOutcomes: [.cancelled]
            )
        )

        let completion = try driver.run()

        XCTAssertEqual(completion.steps.map(\.status), [.failed, .skipped])
        XCTAssertEqual(
            completion.steps.first?.actionEvidence?.result?.outcome.failureKind,
            .actionFailed
        )
    }

    func testWarnAndFailRetainCanonicalPathsAndStatuses() throws {
        let plan = try HeistPlan(body: [
            .warn(WarnStep(message: "heads up")),
            .fail(FailStep(message: "stop")),
            .warn(WarnStep(message: "unreachable")),
        ])
        var driver = try HeistMachineTestDriver(plan: plan)

        let completion = try driver.run()

        XCTAssertEqual(completion.steps.map(\.kind), [.warn, .fail, .warn])
        XCTAssertEqual(completion.steps.map(\.status), [.passed, .failed, .skipped])
        XCTAssertEqual(
            completion.steps.map(\.path.description),
            ["$.body[0]", "$.body[1]", "$.body[2]"]
        )
        XCTAssertEqual(completion.abortedAtPath, completion.steps[1].path)
    }

    func testFailureScreenshotIsAHostRequestNotASecondExecutor() throws {
        let plan = try HeistPlan(body: [
            .fail(FailStep(message: "stop")),
        ])
        var machine = try HeistExecution.Machine(
            plan: plan,
            failureCaptureMode: .raw
        )

        guard case .perform(let request) = machine.start(),
              case let .captureFailureScreenshot(
                  id,
                  failedPath: failedPath,
                  mode: .raw
              ) = request else {
            return XCTFail("Failure capture must be one typed host request")
        }
        XCTAssertEqual(failedPath.description, "$.body[0]")

        let screenshot = ScreenPayload(
            pngData: "png",
            width: 1,
            height: 1
        )
        guard case .complete(let completion) = machine.advance(
            .failureScreenshotCaptured(id, .captured(screenshot))
        ) else {
            return XCTFail("The screenshot completion must finish the same machine")
        }
        XCTAssertEqual(completion.steps.map(\.kind), [.fail])
        XCTAssertEqual(completion.steps.map(\.status), [.failed])
        XCTAssertEqual(completion.failureCapture, .captured(screenshot))
        XCTAssertEqual(completion.abortedAtPath, completion.steps.first?.path)
    }
}

private enum MachineRequestKind: Equatable {
    case currentSnapshot
    case beginObservation
    case dispatch
    case explore
    case finishObservation
    case captureFailureScreenshot
}

struct BeginObservationRequest {
    let id: HeistExecution.RequestID
    let request: HeistExecution.ObservationRequest
}

struct DispatchRequest {
    let id: HeistExecution.RequestID
}

private extension HeistExecution.MainActorRequest {
    var kind: MachineRequestKind {
        switch self {
        case .currentSnapshot: .currentSnapshot
        case .beginObservation: .beginObservation
        case .dispatch: .dispatch
        case .explore: .explore
        case .finishObservation: .finishObservation
        case .captureFailureScreenshot: .captureFailureScreenshot
        }
    }
}

extension HeistExecution.Decision {
    var singleBeginObservationRequest: BeginObservationRequest? {
        guard case .perform(let action) = self,
              case .beginObservation(let id, let request) = action else {
            return nil
        }
        return BeginObservationRequest(id: id, request: request)
    }

    var singleDispatchRequest: DispatchRequest? {
        guard case .perform(let request) = self,
              case .dispatch(let id, _) = request else {
            return nil
        }
        return DispatchRequest(id: id)
    }
}

#endif // canImport(UIKit)
