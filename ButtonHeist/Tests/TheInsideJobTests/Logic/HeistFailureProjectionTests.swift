#if canImport(UIKit)
import ButtonHeistTestSupport
import XCTest

@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class HeistFailureProjectionTests: XCTestCase {
    func testFailureSeparatesOneWaitCauseFromContractAndExpectation() throws {
        let step = HeistResultFixture.failedWait(failure: HeistFailureDetail(
            category: .timeout,
            contract: "wait predicate is met",
            observed: "deadline expired",
            expected: "exists(label: Done)"
        ))
        let failure = Heist.Failure(try HeistResult(steps: [step], durationMs: 0))

        XCTAssertEqual(
            failure.description,
            """
            Wait for .exists(.label("Done")) failed after 250ms
            Cause: deadline expired
            Contract: wait predicate is met
            Expected: exists(label: Done)
            Recent steps:
              ✗ Wait for .exists(.label("Done"))  250ms
            Wait evidence:
              Screen changes: 0
              Semantic element changes: 1
              Notifications: 0
              Final interface quiet: 125ms
              Observation coverage: complete
            """
        )
        XCTAssertEqual(failure.description.components(separatedBy: "deadline expired").count, 2)
    }

    func testActionFailureLabelsDispatchTargetSeparately() throws {
        let result = ActionResult.failure(
            payload: .activate,
            failureKind: .elementNotFound,
            message: "target missing"
        )
        let step = HeistResultFixture.action(
            result: result,
            failure: HeistFailureDetail(
                category: .targetResolution,
                contract: "target resolves uniquely",
                observed: "target missing",
                expected: "label: Delete"
            )
        )
        let failure = Heist.Failure(try HeistResult(steps: [step], durationMs: 0))

        XCTAssertTrue(failure.description.contains("Target: label: Delete"))
        XCTAssertFalse(failure.description.contains("Expected: label: Delete"))
    }
}

#endif
