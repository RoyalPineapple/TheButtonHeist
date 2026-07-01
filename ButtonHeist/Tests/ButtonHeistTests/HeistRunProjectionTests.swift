import XCTest
@testable import ButtonHeist
import ThePlans
import TheScore

final class HeistRunProjectionTests: XCTestCase {

    func testRemoteAbortedResultPreservesAbortedPathAndOverwritesDuration() throws {
        let plan = try samplePlan()
        let remoteResult = abortedRemoteResult(durationMs: 17)

        let projection = HeistRunProjection(
            plan: plan,
            remoteResult: remoteResult,
            totalMs: 82
        )

        XCTAssertTrue(projection.projectedResult.isFailure)
        XCTAssertEqual(projection.projectedResult.steps, remoteResult.steps)
        XCTAssertEqual(projection.projectedResult.abortedAtPath, "$.body[0]")
        XCTAssertEqual(projection.projectedResult.durationMs, 82)
        assertResponse(projection, wraps: plan)
    }

    func testRemotePassedResultBecomesPassedWithMeasuredDuration() throws {
        let plan = try samplePlan()
        let remoteResult = passedRemoteResult(durationMs: 11)

        let projection = HeistRunProjection(
            plan: plan,
            remoteResult: remoteResult,
            totalMs: 43
        )

        XCTAssertFalse(projection.projectedResult.isFailure)
        XCTAssertEqual(projection.projectedResult.steps, remoteResult.steps)
        XCTAssertNil(projection.projectedResult.abortedAtPath)
        XCTAssertEqual(projection.projectedResult.durationMs, 43)
        assertResponse(projection, wraps: plan)
    }

    func testReceiptEffectIsEmittedWithProjectedResult() throws {
        let plan = try samplePlan()
        let remoteResult = passedRemoteResult(durationMs: 11)

        let projection = HeistRunProjection(
            plan: plan,
            remoteResult: remoteResult,
            totalMs: 43
        )

        XCTAssertEqual(projection.effects, [
            .recordReceipt(result: projection.projectedResult, plan: plan),
        ])
    }

    private func assertResponse(
        _ projection: HeistRunProjection,
        wraps plan: HeistPlan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .heistExecution(let responsePlan, let responseResult, let accessibilityTrace) = projection.response else {
            XCTFail("Expected heistExecution response", file: file, line: line)
            return
        }

        XCTAssertEqual(responsePlan, plan, file: file, line: line)
        XCTAssertEqual(responseResult, projection.projectedResult, file: file, line: line)
        XCTAssertNil(accessibilityTrace, file: file, line: line)
    }

    private func samplePlan() throws -> HeistPlan {
        try HeistPlan(
            name: "projection",
            body: [.warn(WarnStep(message: "ready"))]
        )
    }

    private func passedRemoteResult(durationMs: Int) -> HeistExecutionResult {
        .passed(
            steps: [
                .passed(
                    path: "$.body[0]",
                    kind: .warn,
                    durationMs: durationMs,
                    intent: .warn(message: "ready"),
                    evidence: .warning(HeistExecutionWarning(path: "$.body[0]", message: "ready"))
                ),
            ],
            durationMs: durationMs
        )
    }

    private func abortedRemoteResult(durationMs: Int) -> HeistExecutionResult {
        .failed(
            steps: [
                .failed(
                    path: "$.body[0]",
                    kind: .fail,
                    durationMs: durationMs,
                    intent: .fail(message: "boom"),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "Fail",
                        observed: "boom"
                    )
                ),
            ],
            durationMs: durationMs,
            abortedAtPath: "$.body[0]"
        )
    }
}
