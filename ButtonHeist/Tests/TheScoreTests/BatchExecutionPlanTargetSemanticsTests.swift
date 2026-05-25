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

        let target = SemanticActionTarget(minimumMatcher)

        XCTAssertEqual(target.sourceHeistId, "checkout_total_$12")
        XCTAssertEqual(target.matcher, ElementMatcher(label: "Total"))
        XCTAssertNil(target.matcher.heistId)
        XCTAssertNil(target.ordinal)
    }

    func testValueChangingActionTargetUsesMatcherIdentityAfterRoundTrip() throws {
        let target = SemanticActionTarget(
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
        XCTAssertEqual(decodedTarget.matcher, ElementMatcher(label: "Count", traits: [.adjustable]))
        XCTAssertNil(decodedTarget.ordinal)
    }

    func testBatchPlanClientMessageWireShapeKeepsTypedBatchPayload() throws {
        let plan = BatchPlan(
            steps: [
                .action(
                    .activate(SemanticActionTarget(
                        sourceHeistId: "settings_button_old",
                        matcher: ElementMatcher(label: "Settings", traits: [.button])
                    )),
                    expect: .screenChanged,
                    deadline: Deadline(timeout: 2.5)
                ),
                .action(.waitForIdle(WaitForIdleTarget(timeout: 0.25))),
                .action(
                    .waitForChange(WaitForChangeTarget(expect: .elementsChanged, timeout: 1.5)),
                    expect: .elementsChanged,
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

        let waitChangeAction = try XCTUnwrap(steps[2]["action"] as? [String: Any])
        XCTAssertEqual(waitChangeAction["type"] as? String, "wait_for_change")
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
