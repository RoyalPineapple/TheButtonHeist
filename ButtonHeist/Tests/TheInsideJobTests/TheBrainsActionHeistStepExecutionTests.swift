#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest

@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

final class HeistMachineStepExecutionTests: XCTestCase {
    func testBareActionUsesOneTypedRequestPipeline() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
        ])
        var driver = try HeistMachineTestDriver(
            plan: plan,
            script: MachineRunScript(events: [.noChange])
        )

        let completion = try driver.run()

        XCTAssertEqual(completion.steps.map(\.status), [.passed])
        XCTAssertEqual(driver.requests.map(\.kind), [
            .beginObservation,
            .currentSnapshot,
            .dispatch,
            .finishObservation,
        ])
        XCTAssertEqual(Array(driver.history), [.noChange])
    }

    func testStaleDispatchCompletionCannotFinishAction() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
        ])
        var machine = try HeistExecution.Machine(plan: plan)
        let observation = try XCTUnwrap(machine.start().singleBeginObservationRequest)
        let boundary = TheVault.State.HistoryBoundary(
            baseline: nil,
            historyIndex: 0
        )
        let snapshotRequest = try XCTUnwrap(
            machine.advance(.observationBegan(
                observation.id,
                boundary
            )).singleSnapshotRequest
        )
        let dispatchRequest = try XCTUnwrap(
            machine.advance(.currentSnapshot(snapshotRequest.id, nil))
                .singleDispatchRequest
        )

        guard case .pending(.wait) = machine.advance(.dispatchCompleted(
            HeistExecution.RequestID(rawValue: dispatchRequest.id.rawValue + 1),
            .success(payload: .dismiss)
        )) else {
            return XCTFail("A stale dispatch completion must be ignored")
        }
        guard case .pending(.wait) = machine.advance(.dispatchCompleted(
            dispatchRequest.id,
            .success(payload: .dismiss)
        )) else {
            return XCTFail("The admitted dispatch completion must await settlement")
        }
    }

    func testActionCapturesBaselineBeforeDispatchWithoutWaitingForStillness() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .dismiss)),
        ])
        var machine = try HeistExecution.Machine(plan: plan)
        let observation = try XCTUnwrap(machine.start().singleBeginObservationRequest)
        let boundary = TheVault.State.HistoryBoundary(
            baseline: heistSnapshot(labels: ["Before"]),
            historyIndex: 0
        )

        let snapshot = try XCTUnwrap(machine.advance(.observationBegan(
            observation.id,
            boundary
        )).singleSnapshotRequest)

        XCTAssertEqual(snapshot.id, observation.id)
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

        guard case .pending(.perform(let requests)) = machine.start(),
              requests.count == 1,
              case let .captureFailureScreenshot(
                  id,
                  failedPath: failedPath,
                  mode: .raw
              ) = requests[0] else {
            return XCTFail("Failure capture must be one typed host request")
        }
        XCTAssertEqual(failedPath.description, "$.body[0]")

        let screenshot = HeistResultFixture.action(
            path: "$.body[0].failure.actions[0]",
            command: .takeScreenshot,
            result: .success(payload: .screenshot(nil))
        )
        guard case .complete(let completion) = machine.advance(
            .failureScreenshotCaptured(id, screenshot)
        ) else {
            return XCTFail("The screenshot completion must finish the same machine")
        }
        XCTAssertEqual(
            completion.steps.map(\.kind),
            [HeistExecutionStepKind.fail, .action]
        )
        XCTAssertEqual(
            completion.steps.map(\.status),
            [HeistExecutionStepStatus.failed, .passed]
        )
        XCTAssertEqual(completion.steps.last?.actionCommand, .takeScreenshot)
        XCTAssertEqual(
            completion.steps.last?.path.description,
            "$.body[0].failure.actions[0]"
        )
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

private struct BeginObservationRequest {
    let id: HeistExecution.RequestID
}

private struct DispatchRequest {
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

private extension HeistExecution.State {
    var singleBeginObservationRequest: BeginObservationRequest? {
        guard case .pending(.perform(let requests)) = self,
              requests.count == 1,
              case .beginObservation(let id, _) = requests[0] else {
            return nil
        }
        return BeginObservationRequest(id: id)
    }

    var singleDispatchRequest: DispatchRequest? {
        guard case .pending(.perform(let requests)) = self,
              requests.count == 1,
              case .dispatch(let id, _) = requests[0] else {
            return nil
        }
        return DispatchRequest(id: id)
    }
}

#endif // canImport(UIKit)
