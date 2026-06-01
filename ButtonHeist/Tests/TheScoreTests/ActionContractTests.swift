import XCTest

@testable import TheScore

final class ActionContractTests: XCTestCase {

    func testBatchStepRejectsNestedPlanOnEncode() throws {
        let plan = BatchPlan(steps: [
            BatchStep(
                command: .setPasteboard(SetPasteboardTarget(text: "ready")),
                predicate: nil,
                deadline: Deadline()
            ),
        ])
        let step = BatchStep(
            command: .batchExecutionPlan(plan),
            predicate: nil,
            deadline: Deadline()
        )

        XCTAssertThrowsError(try JSONEncoder().encode(step)) { error in
            XCTAssertTrue(
                "\(error)".contains("cannot be a nested batch execution plan"),
                "Expected nested batch rejection, got \(error)"
            )
        }
    }

    func testBatchStepRejectsMissingDeadline() throws {
        let command = ClientMessage.wait(WaitTarget(
            predicate: .changed(.elements),
            timeout: 0.25
        ))

        let data = try JSONEncoder().encode(BatchStepCommandOnlyFixture(command: command))
        XCTAssertThrowsError(try JSONDecoder().decode(BatchStep.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("deadline"), "Expected missing deadline rejection, got \(error)")
        }
    }

    private struct BatchStepCommandOnlyFixture: Encodable {
        let command: ClientMessage
    }

}
