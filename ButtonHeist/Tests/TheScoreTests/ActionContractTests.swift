import XCTest

@testable import TheScore

final class ActionContractTests: XCTestCase {

    func testBatchStepRejectsNestedPlanOnEncode() throws {
        let plan = BatchPlan(steps: [
            BatchStep(
                command: .setPasteboard(SetPasteboardTarget(text: "ready")),
                expectation: .delivery,
                deadline: Deadline()
            ),
        ])
        let step = BatchStep(
            command: .batchExecutionPlan(plan),
            expectation: .delivery,
            deadline: Deadline()
        )

        XCTAssertThrowsError(try JSONEncoder().encode(step)) { error in
            XCTAssertTrue(
                "\(error)".contains("cannot be a nested batch execution plan"),
                "Expected nested batch rejection, got \(error)"
            )
        }
    }

    func testBatchStepRejectsImplicitExpectationAndDeadline() throws {
        let command = ClientMessage.waitForChange(WaitForChangeTarget(
            expect: .elementsChanged,
            timeout: 0.25
        ))

        let data = try JSONEncoder().encode(BatchStepCommandOnlyFixture(command: command))
        XCTAssertThrowsError(try JSONDecoder().decode(BatchStep.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("expect") || "\(error)".contains("deadline"))
        }
    }

    private struct BatchStepCommandOnlyFixture: Encodable {
        let command: ClientMessage
    }

}
