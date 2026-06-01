import XCTest
@testable import TheScore

final class BatchPlanTargetSemanticsTests: XCTestCase {

    func testBatchStepPreservesNormalCommandTargetAfterRoundTrip() throws {
        let command = ClientMessage.increment(.predicate(
            ElementPredicate(label: "Count", traits: [.adjustable])
        ))
        let plan = BatchPlan(steps: [
            BatchStep(
                command: command,
                predicate: .changed(.updated(ElementUpdatePredicate(to: "2"))),
                deadline: Deadline()
            ),
        ])

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(BatchPlan.self, from: data)

        guard let decodedStep = decoded.steps.first,
              case .increment(let decodedTarget) = decodedStep.command,
              decodedStep.predicate == .changed(.updated(ElementUpdatePredicate(to: "2"))) else {
            return XCTFail("Expected increment command with element_updated predicate")
        }
        XCTAssertEqual(
            decodedTarget,
            .predicate(ElementPredicate(label: "Count", traits: [.adjustable]))
        )
    }

    func testBatchPlanClientMessageWireShapeCarriesNormalCommands() throws {
        let plan = BatchPlan(
            steps: [
                BatchStep(
                    command: .activate(.heistId("settings_button_current")),
                    predicate: .changed(.screen()),
                    deadline: Deadline(timeout: 2.5)
                ),
                BatchStep(
                    command: .wait(WaitTarget(predicate: .changed(.elements), timeout: 0.25)),
                    predicate: nil,
                    deadline: Deadline(timeout: 0.25)
                ),
                BatchStep(
                    command: .wait(WaitTarget(predicate: .changed(.elements), timeout: 1.5)),
                    predicate: .changed(.elements),
                    deadline: Deadline(timeout: 1.5)
                ),
            ],
            policy: .continueOnError
        )
        let message = ClientMessage.batchExecutionPlan(plan)

        let data = try JSONEncoder().encode(message)
        let payload = try jsonObject(data)

        XCTAssertEqual(payload["type"] as? String, "batchExecutionPlan")
        let batchPayload = try XCTUnwrap(payload["payload"] as? [String: Any])
        XCTAssertEqual(batchPayload["policy"] as? String, "continue_on_error")
        let steps = try XCTUnwrap(batchPayload["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 3)

        let commandStep = steps[0]
        XCTAssertNil(commandStep["action"])
        let command = try XCTUnwrap(commandStep["command"] as? [String: Any])
        XCTAssertEqual(command["type"] as? String, "activate")
        let target = try XCTUnwrap(command["payload"] as? [String: Any])
        XCTAssertEqual(target["heistId"] as? String, "settings_button_current")
        XCTAssertEqual((commandStep["expect"] as? [String: Any])?["type"] as? String, "screen_changed")
        XCTAssertEqual((commandStep["deadline"] as? [String: Any])?["timeout"] as? Double, 2.5)

        let waitCommand = try XCTUnwrap(steps[1]["command"] as? [String: Any])
        XCTAssertEqual(waitCommand["type"] as? String, "wait")
        XCTAssertEqual(((waitCommand["payload"] as? [String: Any])?["timeout"] as? Double), 0.25)
        XCTAssertNil(steps[1]["expect"])

        let waitChangeCommand = try XCTUnwrap(steps[2]["command"] as? [String: Any])
        XCTAssertEqual(waitChangeCommand["type"] as? String, "wait")
        XCTAssertEqual((steps[2]["expect"] as? [String: Any])?["type"] as? String, "elements_changed")
        XCTAssertEqual((steps[2]["deadline"] as? [String: Any])?["timeout"] as? Double, 1.5)

        guard case .batchExecutionPlan(let decodedPlan) = try JSONDecoder().decode(ClientMessage.self, from: data) else {
            return XCTFail("Expected batch execution client message")
        }
        XCTAssertEqual(decodedPlan.policy, .continueOnError)
        XCTAssertEqual(decodedPlan.steps.count, 3)
        XCTAssertEqual(decodedPlan.steps[0].predicate, .changed(.screen()))
        XCTAssertEqual(decodedPlan.steps[0].deadline, Deadline(timeout: 2.5))
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
