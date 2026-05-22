import XCTest
@testable import TheScore

final class BatchPlanTargetSemanticsTests: XCTestCase {

    func testMinimumMatcherTargetKeepsSourceHeistIdAsMetadataOnly() throws {
        let targetElement = makeElement(heistId: "checkout_total_$12", label: "Total", value: "$12.00", traits: [.staticText])
        let capture = makeCapture([
            targetElement,
            makeElement(heistId: "checkout_tax_$1", label: "Tax", value: "$1.00", traits: [.staticText]),
        ])
        let minimumMatcher = MinimumMatcher.build(element: targetElement, in: capture)

        let target = BatchExecutionTarget(minimumMatcher)

        XCTAssertEqual(target.sourceHeistId, "checkout_total_$12")
        XCTAssertEqual(target.matcher, ElementMatcher(label: "Total"))
        XCTAssertNil(target.matcher.heistId)
        guard case .matcher(let executableMatcher, let ordinal) = target.executableTarget else {
            return XCTFail("Expected executable identity to be matcher-based")
        }
        XCTAssertEqual(executableMatcher, ElementMatcher(label: "Total"))
        XCTAssertNil(executableMatcher.heistId)
        XCTAssertNil(ordinal)
    }

    func testValueChangingActionTargetUsesMatcherIdentityAfterRoundTrip() throws {
        let target = BatchExecutionTarget(
            sourceHeistId: "stepper_count_1",
            matcher: ElementMatcher(label: "Count", traits: [.adjustable])
        )
        let plan = BatchPlan(steps: [
            .action(.increment(target), expect: .elementUpdated(newValue: "2")),
        ])

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(BatchPlan.self, from: data)

        guard let decodedStep = decoded.steps.first,
              case .increment(let decodedTarget) = decodedStep.action,
              decodedStep.expectation == .elementUpdated(newValue: "2") else {
            return XCTFail("Expected increment action with elementUpdated expectation")
        }
        XCTAssertEqual(decodedTarget.sourceHeistId, "stepper_count_1")
        XCTAssertNil(decodedTarget.matcher.heistId)
        guard case .matcher(let executableMatcher, let ordinal) = decodedTarget.executableTarget else {
            return XCTFail("Expected matcher executable target")
        }
        XCTAssertEqual(executableMatcher, ElementMatcher(label: "Count", traits: [.adjustable]))
        XCTAssertNil(ordinal)
    }

    func testBatchPlanClientMessageWireShapeKeepsTypedBatchPayload() throws {
        let plan = BatchPlan(
            steps: [
                .action(
                    .activate(BatchExecutionTarget(
                        sourceHeistId: "settings_button_old",
                        matcher: ElementMatcher(label: "Settings", traits: [.button])
                    )),
                    expect: .screenChanged,
                    deadline: Deadline(timeout: 2.5)
                ),
                .wait(.idle(WaitForIdleTarget(timeout: 0.25))),
                .checkpoint(BatchExecutionCheckpoint(
                    name: "loaded",
                    expect: .elementsChanged,
                    timeout: 1.5
                )),
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

        let actionStep = steps[0]
        XCTAssertNil(actionStep["kind"])
        let action = try XCTUnwrap(actionStep["action"] as? [String: Any])
        XCTAssertEqual(action["type"] as? String, "activate")
        let target = try XCTUnwrap(action["target"] as? [String: Any])
        XCTAssertEqual(target["sourceHeistId"] as? String, "settings_button_old")
        let matcher = try XCTUnwrap(target["matcher"] as? [String: Any])
        XCTAssertNil(matcher["heistId"])
        XCTAssertEqual(matcher["label"] as? String, "Settings")
        XCTAssertEqual(matcher["traits"] as? [String], ["button"])
        XCTAssertEqual((actionStep["expect"] as? [String: Any])?["type"] as? String, "screen_changed")
        XCTAssertEqual((actionStep["deadline"] as? [String: Any])?["timeout"] as? Double, 2.5)

        let waitAction = try XCTUnwrap(steps[1]["action"] as? [String: Any])
        XCTAssertEqual(waitAction["type"] as? String, "wait_for_idle")
        XCTAssertEqual(((waitAction["target"] as? [String: Any])?["timeout"] as? Double), 0.25)
        XCTAssertEqual((steps[1]["expect"] as? [String: Any])?["type"] as? String, "delivery")

        let checkpointAction = try XCTUnwrap(steps[2]["action"] as? [String: Any])
        XCTAssertEqual(checkpointAction["type"] as? String, "checkpoint")
        XCTAssertEqual(checkpointAction["name"] as? String, "loaded")
        XCTAssertEqual((steps[2]["expect"] as? [String: Any])?["type"] as? String, "elements_changed")
        XCTAssertEqual((steps[2]["deadline"] as? [String: Any])?["timeout"] as? Double, 1.5)

        guard case .batchExecutionPlan(let decodedPlan) = try JSONDecoder().decode(ClientMessage.self, from: data) else {
            return XCTFail("Expected batch execution client message")
        }
        XCTAssertEqual(decodedPlan.policy, .continueOnError)
        XCTAssertEqual(decodedPlan.steps.count, 3)
        XCTAssertEqual(decodedPlan.steps[0].expectation, .screenChanged)
        XCTAssertEqual(decodedPlan.steps[0].deadline, Deadline(timeout: 2.5))
    }

    func testBatchPlanStillDecodesLegacyWaitAndCheckpointStepShapes() throws {
        let json = """
        {
          "steps": [
            {
              "kind": "wait",
              "wait": {
                "type": "wait_for_idle",
                "target": { "timeout": 0.25 }
              }
            },
            {
              "kind": "checkpoint",
              "checkpoint": {
                "name": "loaded",
                "expect": { "type": "screen_changed" },
                "timeout": 1.5
              }
            }
          ],
          "policy": "continue_on_error"
        }
        """

        let plan = try JSONDecoder().decode(BatchPlan.self, from: Data(json.utf8))

        XCTAssertEqual(plan.policy, .continueOnError)
        XCTAssertEqual(plan.steps.count, 2)
        guard case .waitForIdle(let waitTarget) = plan.steps[0].action else {
            return XCTFail("Expected legacy wait step to lower to wait_for_idle action")
        }
        XCTAssertEqual(waitTarget.timeout, 0.25)
        XCTAssertEqual(plan.steps[0].expectation, .delivery)
        XCTAssertEqual(plan.steps[0].deadline, Deadline(timeout: 0.25))
        guard case .checkpoint(let checkpoint) = plan.steps[1].action else {
            return XCTFail("Expected legacy checkpoint step to lower to checkpoint action")
        }
        XCTAssertEqual(checkpoint.name, "loaded")
        XCTAssertEqual(plan.steps[1].expectation, .screenChanged)
        XCTAssertEqual(plan.steps[1].deadline, Deadline(timeout: 1.5))
    }

    func testBatchActionRejectsReadOnlyClientMessages() throws {
        let json = #"{"type":"get_pasteboard"}"#

        XCTAssertThrowsError(
            try JSONDecoder().decode(TheScore.Action.self, from: Data(json.utf8))
        ) { error in
            guard case .dataCorrupted(let context) = error as? DecodingError else {
                return XCTFail("Expected dataCorrupted decoding error, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "get_pasteboard is a read operation and is not a batch Action")
        }
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeCapture(_ elements: [HeistElement]) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: 1,
            interface: makeTestInterface(elements: elements)
        )
    }

    private func makeElement(
        heistId: HeistId,
        label: String? = nil,
        value: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label ?? heistId,
            label: label,
            value: value,
            identifier: nil,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
    }
}
