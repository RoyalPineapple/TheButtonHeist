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
                events.append("action:\(command.wireType.rawValue)")
                return ActionResult(
                    success: true,
                    method: .setPasteboard,
                    message: "delivered"
                )
            },
            waitForExpectation: { expectation, _ in
                events.append("expectation:\(expectation)")
                let trace: AccessibilityTrace.Delta
                switch expectation {
                case .screenChanged:
                    trace = .screenChanged(.init(
                        elementCount: 1,
                        newInterface: Interface(timestamp: Date(), tree: [])
                    ))
                default:
                    trace = .elementsChanged(.init(elementCount: 1, edits: ElementEdits()))
                }
                return ActionResult(
                    success: true,
                    method: .waitForChange,
                    message: expectation.description,
                    accessibilityTrace: AccessibilityTrace.projectingForTests(trace)
                )
            },
            settleRefreshRecordBaseline: {
                events.append("baseline")
            }
        )
        let plan = TheScore.BatchPlan(
            steps: [
                BatchStep(
                    command: .setPasteboard(SetPasteboardTarget(text: "ready")),
                    expectation: .elementsChanged,
                    deadline: Deadline()
                ),
                BatchStep(
                    command: .waitForChange(WaitForChangeTarget(expect: .screenChanged, timeout: 0.1)),
                    expectation: .screenChanged,
                    deadline: Deadline(timeout: 0.1)
                ),
            ],
            policy: .continueOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.method, TheScore.ActionMethod.batchExecutionPlan)
        XCTAssertEqual(events, [
            "action:setPasteboard",
            "expectation:elements_changed",
            "baseline",
            "action:waitForChange",
            "expectation:screen_changed",
            "baseline",
        ])

        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertNil(batch.failedIndex)
        XCTAssertEqual(batch.steps.count, 2)
        let first = batch.steps[0]
        XCTAssertEqual(first.expectation?.met, true)
        XCTAssertEqual(first.expectationActionResult?.method, .waitForChange)
        let second = batch.steps[1]
        XCTAssertNotNil(second.actionResult)
        XCTAssertEqual(second.expectation?.met, true)
    }

    func testBatchExecutionStopsLocallyOnFailedStepUnderStopOnError() async throws {
        var events: [String] = []
        let runtime = TheBrains.BatchExecutionRuntime(
            execute: { command in
                events.append("action:\(command.wireType.rawValue)")
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
                BatchStep(
                    command: .setPasteboard(SetPasteboardTarget(text: "first")),
                    expectation: nil,
                    deadline: Deadline()
                ),
                BatchStep(
                    command: .setPasteboard(SetPasteboardTarget(text: "next")),
                    expectation: nil,
                    deadline: Deadline()
                ),
                BatchStep(
                    command: .waitForChange(WaitForChangeTarget(timeout: 0.1)),
                    expectation: nil,
                    deadline: Deadline(timeout: 0.1)
                ),
            ],
            policy: .stopOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertFalse(result.success)
        XCTAssertEqual(events, ["action:setPasteboard", "baseline"])
        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertEqual(batch.failedIndex, 0)
        XCTAssertEqual(batch.steps.count, 3)
        let first = batch.steps[0]
        XCTAssertTrue(first.stopsBatch)
        let second = batch.steps[1]
        let third = batch.steps[2]
        XCTAssertTrue(second.isSkipped)
        XCTAssertTrue(third.isSkipped)
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
                events.append("action:\(command.wireType.rawValue)")
                return results.removeFirst()
            },
            waitForExpectation: { _, _ in
                XCTFail("Steps without explicit expectations should not wait")
                return ActionResult(success: true, method: .waitForChange)
            },
            settleRefreshRecordBaseline: {
                events.append("baseline")
            }
        )
        let plan = TheScore.BatchPlan(
            steps: [
                BatchStep(
                    command: .setPasteboard(SetPasteboardTarget(text: "first")),
                    expectation: nil,
                    deadline: Deadline()
                ),
                BatchStep(
                    command: .setPasteboard(SetPasteboardTarget(text: "second")),
                    expectation: nil,
                    deadline: Deadline()
                ),
            ],
            policy: .continueOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(events, [
            "action:setPasteboard",
            "baseline",
            "action:setPasteboard",
            "baseline",
        ])
        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertNil(batch.failedIndex)
        XCTAssertEqual(batch.steps.count, 2)
        XCTAssertEqual(batch.steps.map(\.actionResult?.success), [false, true])
    }

    func testBatchExecutionUsesTypedCommandsForCasesWithoutAssociatedValues() async throws {
        var events: [String] = []
        let runtime = TheBrains.BatchExecutionRuntime(
            execute: { command in
                events.append("action:\(command.wireType.rawValue)")
                let method: ActionMethod
                switch command {
                case .getPasteboard:
                    method = .getPasteboard
                case .resignFirstResponder:
                    method = .resignFirstResponder
                default:
                    XCTFail("Unexpected command \(command.wireType.rawValue)")
                    method = .batchExecutionPlan
                }
                return ActionResult(success: true, method: method)
            },
            waitForExpectation: { _, _ in
                XCTFail("Steps without explicit expectations should not wait")
                return ActionResult(success: true, method: .waitForChange)
            },
            settleRefreshRecordBaseline: {
                events.append("baseline")
            }
        )
        let plan = TheScore.BatchPlan(
            steps: [
                BatchStep(command: .getPasteboard, expectation: nil, deadline: Deadline()),
                BatchStep(command: .resignFirstResponder, expectation: nil, deadline: Deadline()),
            ],
            policy: .continueOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(events, [
            "action:getPasteboard",
            "baseline",
            "action:resignFirstResponder",
            "baseline",
        ])
        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertEqual(batch.steps.map(\.actionResult?.method), [.getPasteboard, .resignFirstResponder])
    }

    func testBatchExecutionDoesNotWaitWhenActionAlreadySatisfiesExpectation() async throws {
        var events: [String] = []
        let runtime = TheBrains.BatchExecutionRuntime(
            execute: { command in
                events.append("action:\(command.wireType.rawValue)")
                return ActionResult(
                    success: true,
                    method: .setPasteboard,
                    accessibilityTrace: .projectingForTests(.screenChanged(.init(
                        elementCount: 1,
                        newInterface: Interface(timestamp: Date(), tree: [])
                    )))
                )
            },
            waitForExpectation: { expectation, _ in
                XCTFail("Action delta already satisfies \(expectation)")
                return ActionResult(success: false, method: .waitForChange)
            },
            settleRefreshRecordBaseline: {
                events.append("baseline")
            }
        )
        let plan = TheScore.BatchPlan(
            steps: [
                BatchStep(
                    command: .setPasteboard(SetPasteboardTarget(text: "ready")),
                    expectation: .screenChanged,
                    deadline: Deadline()
                ),
            ],
            policy: .stopOnError
        )

        let result = await brains.executeBatchExecutionPlanForTest(plan, runtime: runtime)

        XCTAssertTrue(result.success)
        XCTAssertEqual(events, ["action:setPasteboard", "baseline"])
        let batch = try XCTUnwrap(result.batchExecutionPayload)
        XCTAssertEqual(batch.steps[0].expectation?.met, true)
    }

    func testClientBatchPlanDispatchesToBatchRunner() async throws {
        let plan = TheScore.BatchPlan(steps: [
            BatchStep(
                command: .setPasteboard(SetPasteboardTarget(text: "batch")),
                expectation: nil,
                deadline: Deadline(timeout: 0.01)
            ),
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
