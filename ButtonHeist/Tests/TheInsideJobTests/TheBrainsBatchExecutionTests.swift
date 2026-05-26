#if canImport(UIKit)
import XCTest

@testable import TheInsideJob
@testable import TheScore

@MainActor
final class TheBrainsBatchExecutionTests: XCTestCase {

    private var brains: TheBrains!

    override func setUp() async throws {
        try await super.setUp()
        brains = TheBrains(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        brains = nil
        try await super.tearDown()
    }

    func testBatchExecutionRunsStepsWaitsForExpectationsAndRecordsBaselineBetweenSteps() async throws {
        var events: [String] = []
        let runtime = TheBrains.BatchExecutionRuntime(
            execute: { command in
                events.append("action:\(command.canonicalName)")
                return ActionResult(
                    success: true,
                    method: .setPasteboard,
                    message: "delivered"
                )
            },
            waitForExpectation: { expectation, _ in
                events.append("expectation:\(expectation.summaryDescription)")
                return ActionResult(
                    success: true,
                    method: .waitForChange,
                    message: expectation.summaryDescription
                )
            },
            settleRefreshRecordBaseline: {
                events.append("baseline")
            }
        )
        let plan = TheScore.BatchPlan(
            steps: [
                .command(.setPasteboard(SetPasteboardTarget(text: "ready")), expect: .elementsChanged),
                .command(
                    .waitForChange(WaitForChangeTarget(expect: .screenChanged, timeout: 0.1)),
                    expect: .screenChanged,
                    deadline: Deadline(timeout: 0.1)
                ),
            ],
            policy: .continueOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, TheScore.ActionMethod.batchExecutionPlan)
        XCTAssertEqual(events, [
            "action:set_pasteboard",
            "expectation:elements_changed",
            "baseline",
            "action:wait_for_change",
            "baseline",
        ])

        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertNil(batch.failedIndex)
        XCTAssertEqual(batch.steps.count, 2)
        let first = batch.steps[0]
        XCTAssertEqual(first.actionName, "set_pasteboard")
        XCTAssertEqual(first.expectationName, "elements_changed")
        XCTAssertEqual(first.expectation?.met, true)
        XCTAssertEqual(first.expectationActionResult?.method, .waitForChange)
        let second = batch.steps[1]
        XCTAssertEqual(second.actionName, "wait_for_change")
        XCTAssertEqual(second.expectationName, "screen_changed")
        XCTAssertNotNil(second.actionResult)
        XCTAssertEqual(second.expectation?.met, true)
    }

    func testBatchExecutionStopsLocallyOnFailedStepUnderStopOnError() async throws {
        var events: [String] = []
        let runtime = TheBrains.BatchExecutionRuntime(
            execute: { command in
                events.append("action:\(command.canonicalName)")
                return ActionResult(
                    success: false,
                    method: .setPasteboard,
                    message: "boom",
                    errorKind: .actionFailed
                )
            },
            waitForExpectation: { _, _ in
                XCTFail("Stop-on-error should not wait after a failed action")
                return ActionResult(success: true, method: .waitForChange)
            },
            settleRefreshRecordBaseline: {
                events.append("baseline")
            }
        )
        let plan = TheScore.BatchPlan(
            steps: [
                .command(.setPasteboard(SetPasteboardTarget(text: "first"))),
                .command(.setPasteboard(SetPasteboardTarget(text: "next"))),
                .command(.waitForIdle(WaitForIdleTarget(timeout: 0.1))),
            ],
            policy: .stopOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.success)
        XCTAssertEqual(events, ["action:set_pasteboard", "baseline"])
        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertEqual(batch.failedIndex, 0)
        XCTAssertEqual(batch.steps.count, 3)
        let first = batch.steps[0]
        XCTAssertEqual(first.actionName, "set_pasteboard")
        XCTAssertTrue(first.stopsBatch)
        let second = batch.steps[1]
        let third = batch.steps[2]
        XCTAssertTrue(second.isSkipped)
        XCTAssertTrue(third.isSkipped)
        XCTAssertEqual(second.actionName, "set_pasteboard")
        XCTAssertEqual(third.actionName, "wait_for_idle")
        XCTAssertEqual(third.expectationName, "delivery")
        XCTAssertEqual(second.skipped?.afterFailedIndex, 0)
        XCTAssertEqual(third.skipped?.afterFailedIndex, 0)
    }

    func testBatchExecutionContinuesAfterFailedStepUnderContinueOnError() async throws {
        var events: [String] = []
        var results = [
            ActionResult(success: false, method: .setPasteboard, message: "first failed", errorKind: .actionFailed),
            ActionResult(success: true, method: .setPasteboard, message: "second ran"),
        ]
        let runtime = TheBrains.BatchExecutionRuntime(
            execute: { command in
                events.append("action:\(command.canonicalName)")
                return results.removeFirst()
            },
            waitForExpectation: { _, _ in
                XCTFail("Delivery expectation should not wait")
                return ActionResult(success: true, method: .waitForChange)
            },
            settleRefreshRecordBaseline: {
                events.append("baseline")
            }
        )
        let plan = TheScore.BatchPlan(
            steps: [
                .command(.setPasteboard(SetPasteboardTarget(text: "first"))),
                .command(.setPasteboard(SetPasteboardTarget(text: "second"))),
            ],
            policy: .continueOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(events, [
            "action:set_pasteboard",
            "baseline",
            "action:set_pasteboard",
            "baseline",
        ])
        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertNil(batch.failedIndex)
        XCTAssertEqual(batch.steps.count, 2)
        XCTAssertEqual(batch.steps.map(\.actionResult?.success), [false, true])
    }

    func testBatchExecutionUsesExplicitActionNamesForCasesWithoutAssociatedValues() async throws {
        var events: [String] = []
        let runtime = TheBrains.BatchExecutionRuntime(
            execute: { command in
                events.append("action:\(command.canonicalName)")
                return ActionResult(success: true, method: TheBrains.diagnosticMethod(for: command))
            },
            waitForExpectation: { _, _ in
                XCTFail("Delivery expectation should not wait")
                return ActionResult(success: true, method: .waitForChange)
            },
            settleRefreshRecordBaseline: {
                events.append("baseline")
            }
        )
        let plan = TheScore.BatchPlan(
            steps: [
                .command(.explore),
                .command(.resignFirstResponder),
            ],
            policy: .continueOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(events, [
            "action:explore",
            "baseline",
            "action:resign_first_responder",
            "baseline",
        ])
        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertEqual(batch.steps.map(\.actionName), ["explore", "resign_first_responder"])
        XCTAssertEqual(batch.steps.map(\.actionResult?.method), [.explore, .resignFirstResponder])
    }

    func testBatchExecutionDoesNotWaitWhenActionAlreadySatisfiesExpectation() async throws {
        var events: [String] = []
        let runtime = TheBrains.BatchExecutionRuntime(
            execute: { command in
                events.append("action:\(command.canonicalName)")
                return ActionResult(
                    success: true,
                    method: .setPasteboard,
                    accessibilityDelta: .screenChanged(.init(
                        elementCount: 1,
                        newInterface: Interface(timestamp: Date(), tree: [])
                    ))
                )
            },
            waitForExpectation: { expectation, _ in
                XCTFail("Action delta already satisfies \(expectation.summaryDescription)")
                return ActionResult(success: false, method: .waitForChange)
            },
            settleRefreshRecordBaseline: {
                events.append("baseline")
            }
        )
        let plan = TheScore.BatchPlan(
            steps: [
                .command(.setPasteboard(SetPasteboardTarget(text: "ready")), expect: .screenChanged),
            ],
            policy: .stopOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(events, ["action:set_pasteboard", "baseline"])
        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertEqual(batch.steps[0].expectation?.met, true)
    }

    func testClientBatchPlanDispatchesToBatchRunner() async throws {
        let plan = TheScore.BatchPlan(steps: [
            .command(.waitForIdle(WaitForIdleTarget(timeout: 0.01))),
        ])

        let result = await brains.executeCommand(.batchExecutionPlan(plan))

        XCTAssertEqual(result.method, .batchExecutionPlan)
        XCTAssertNotEqual(result.errorKind, .unsupported)
        XCTAssertNotNil(result.batchExecutionPayload)
    }

}

private extension TheScore.ActionResult {
    var batchExecutionPayload: BatchExecutionResult? {
        guard case .batchExecution(let payload) = payload else { return nil }
        return payload
    }
}

#endif // canImport(UIKit)
