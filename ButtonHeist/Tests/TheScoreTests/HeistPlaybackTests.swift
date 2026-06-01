import XCTest
@testable import TheScore

final class HeistPlanTests: XCTestCase {

    func testHeistPlanRoundTrip() throws {
        let heist = HeistPlan(steps: [
            try activateStep(label: "Login", traits: [.button]),
            .action(try ActionStep(command: .typeText(TypeTextTarget(text: "user@example.com")))),
            try activateStep(label: "Submit", traits: [.button]),
        ])

        let data = try JSONEncoder().encode(heist)
        let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

        XCTAssertEqual(decoded.version, HeistPlan.currentVersion)
        XCTAssertEqual(decoded.steps, heist.steps)
    }

    func testDecodeRejectsUnsupportedVersionAtBoundary() {
        let json = """
        {
          "version": \(HeistPlan.currentVersion + 1),
          "steps": [{"type":"warn","warn":{"message":"check state"}}]
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistPlan.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("Unsupported heist plan version"))
            XCTAssertTrue(context.debugDescription.contains("supports version \(HeistPlan.currentVersion)"))
        }
    }

    func testDecodeRejectsUnknownTopLevelPlanField() {
        let json = """
        {
          "version": \(HeistPlan.currentVersion),
          "steps": [{"type":"warn","warn":{"message":"check state"}}],
          "unexpectedField": {}
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistPlan.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpectedField"), "\(error)")
        }
    }

    func testDecodeRejectsEmptyPlan() {
        let json = #"{"version":1,"steps":[]}"#

        XCTAssertThrowsError(try JSONDecoder().decode(HeistPlan.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("requires at least one step"), "\(error)")
        }
    }

    func testActionStepEncodesTypedClientMessage() throws {
        let step = try activateStep(label: "List", traits: [.adjustable])

        let data = try JSONEncoder().encode(step)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "action")
        let action = try XCTUnwrap(json["action"] as? [String: Any])
        let command = try XCTUnwrap(action["command"] as? [String: Any])
        XCTAssertEqual(command["type"] as? String, "activate")
        let target = try XCTUnwrap(command["payload"] as? [String: Any])
        XCTAssertEqual(target["label"] as? String, "List")
        XCTAssertEqual(target["traits"] as? [String], ["adjustable"])
    }

    func testActionStepRejectsHeistIdAsDurableIdentity() {
        let json = """
        {
          "type": "action",
          "action": {
            "command": {
              "type": "activate",
              "payload": {"heistId": "button_save"}
            }
          }
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("heistId"), "\(error)")
        }
    }

    func testActionStepRejectsUnknownTargetField() {
        let json = """
        {
          "type": "action",
          "action": {
            "command": {
              "type": "activate",
              "payload": {"label": "Save", "unexpectedTargetField": "button_save"}
            }
          }
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpectedTargetField"), "\(error)")
        }
    }

    func testActionStepRejectsRecordingMetadata() {
        let json = """
        {
          "type": "action",
          "_recorded": {"heistId": "button_save"},
          "action": {
            "command": {
              "type": "activate",
              "payload": {"label": "Save"}
            }
          }
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("_recorded"), "\(error)")
        }
    }

    func testWaitWarnAndFailRoundTrip() throws {
        let plan = HeistPlan(steps: [
            .wait(WaitStep(predicate: .state(.present(ElementPredicate(label: "Ready"))), timeout: 1.5)),
            .warn(WarnStep(message: "optional branch skipped")),
            .fail(FailStep(message: "unexpected state")),
        ])

        let data = try JSONEncoder().encode(plan)

        let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

        XCTAssertEqual(decoded, plan)
    }

    func testConditionalAndWaitForCasesRoundTrip() throws {
        let conditionCase = try PredicateCase(
            predicate: .state(.present(ElementPredicate(label: "Home"))),
            steps: [.warn(WarnStep(message: "home"))]
        )
        let plan = HeistPlan(steps: [
            .conditional(try ConditionalStep(
                cases: [conditionCase],
                elseSteps: [.warn(WarnStep(message: "not home"))]
            )),
            .waitForCases(try WaitForCasesStep(
                timeout: 2,
                cases: [conditionCase],
                elseSteps: [.fail(FailStep(message: "no known state"))]
            )),
        ])

        let data = try JSONEncoder().encode(plan)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains(#""else_steps""#), json)
        XCTAssertFalse(json.contains("elseSteps"), json)

        let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

        XCTAssertEqual(decoded, plan)
    }

    func testRepeatStepsRoundTrip() throws {
        let body: [HeistStep] = [.warn(WarnStep(message: "scrolling"))]
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let plan = HeistPlan(steps: [
            .repeatCount(try RepeatCountStep(count: 3, steps: body)),
            .repeatUntil(try RepeatUntilStep(
                predicate: predicate,
                timeout: 20,
                maxIterations: 30,
                steps: body
            )),
        ])

        let data = try JSONEncoder().encode(plan)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains(#""max_iterations":30"#), json)
        XCTAssertFalse(json.contains("maxIterations"), json)

        let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

        XCTAssertEqual(decoded, plan)
    }

    func testRepeatCountAllowsZeroIterations() throws {
        let step = try RepeatCountStep(count: 0, steps: [.warn(WarnStep(message: "never"))])

        XCTAssertEqual(step.count, 0)
    }

    func testRepeatCountRejectsNegativeCount() {
        let json = """
        {
          "type": "repeat_count",
          "repeat_count": {
            "count": -1,
            "steps": [{"type": "warn", "warn": {"message": "never"}}]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("count must be >= 0"), "\(error)")
        }
    }

    func testRepeatCountRejectsEmptySteps() {
        let json = """
        {
          "type": "repeat_count",
          "repeat_count": {
            "count": 1,
            "steps": []
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("emptyRepeatSteps"), "\(error)")
        }
    }

    func testPredicateCaseRejectsEmptySteps() {
        let json = """
        {
          "type": "conditional",
          "conditional": {
            "cases": [
              {
                "predicate": {"type": "present", "element": {"label": "Home"}},
                "steps": []
              }
            ]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("emptyPredicateCaseSteps"), "\(error)")
        }
    }

    func testRepeatUntilRejectsInvalidBounds() {
        let negativeTimeout = """
        {
          "type": "repeat_until",
          "repeat_until": {
            "predicate": {"type": "present", "element": {"label": "Done"}},
            "timeout": -1,
            "max_iterations": 1,
            "steps": [{"type": "warn", "warn": {"message": "scroll"}}]
          }
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(negativeTimeout.utf8))) { error in
            XCTAssertTrue("\(error)".contains("timeout must be non-negative"), "\(error)")
        }

        let zeroIterations = """
        {
          "type": "repeat_until",
          "repeat_until": {
            "predicate": {"type": "present", "element": {"label": "Done"}},
            "timeout": 1,
            "max_iterations": 0,
            "steps": [{"type": "warn", "warn": {"message": "scroll"}}]
          }
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(zeroIterations.utf8))) { error in
            XCTAssertTrue("\(error)".contains("max_iterations must be > 0"), "\(error)")
        }

        let camelCaseIterations = """
        {
          "type": "repeat_until",
          "repeat_until": {
            "predicate": {"type": "present", "element": {"label": "Done"}},
            "timeout": 1,
            "maxIterations": 1,
            "steps": [{"type": "warn", "warn": {"message": "scroll"}}]
          }
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(camelCaseIterations.utf8))) { error in
            XCTAssertTrue("\(error)".contains("maxIterations"), "\(error)")
        }
    }

    func testRepeatStepsRejectCamelCaseBodyKeys() {
        let repeatCount = """
        {
          "type": "repeat_count",
          "repeatCount": {
            "count": 1,
            "steps": [{"type": "warn", "warn": {"message": "never"}}]
          }
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(repeatCount.utf8))) { error in
            XCTAssertTrue("\(error)".contains("repeatCount"), "\(error)")
        }

        let repeatUntil = """
        {
          "type": "repeat_until",
          "repeatUntil": {
            "predicate": {"type": "present", "element": {"label": "Done"}},
            "timeout": 1,
            "max_iterations": 1,
            "steps": [{"type": "warn", "warn": {"message": "never"}}]
          }
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(repeatUntil.utf8))) { error in
            XCTAssertTrue("\(error)".contains("repeatUntil"), "\(error)")
        }
    }

    func testConditionalRejectsCamelCaseElseSteps() {
        let json = """
        {
          "type": "conditional",
          "conditional": {
            "cases": [{
              "predicate": {"type": "present", "element": {"label": "Home"}},
              "steps": [{"type": "warn", "warn": {"message": "home"}}]
            }],
            "elseSteps": [{"type": "warn", "warn": {"message": "not home"}}]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("elseSteps"), "\(error)")
        }
    }

    func testWaitForCasesRejectsCamelCaseElseSteps() {
        let json = """
        {
          "type": "wait_for_cases",
          "wait_for_cases": {
            "timeout": 1,
            "cases": [{
              "predicate": {"type": "present", "element": {"label": "Home"}},
              "steps": [{"type": "warn", "warn": {"message": "home"}}]
            }],
            "elseSteps": [{"type": "warn", "warn": {"message": "not home"}}]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("elseSteps"), "\(error)")
        }
    }

    func testConditionalRejectsEmptyCases() {
        let json = """
        {
          "type": "conditional",
          "conditional": {
            "cases": []
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("emptyPredicateCases"), "\(error)")
        }
    }

    func testWaitForCasesRejectsNegativeTimeout() {
        let json = """
        {
          "type": "wait_for_cases",
          "wait_for_cases": {
            "timeout": -1,
            "cases": [{
              "predicate": {"type": "present", "element": {"label": "Home"}},
              "steps": [{"type": "warn", "warn": {"message": "home"}}]
            }]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("timeout must be non-negative"), "\(error)")
        }
    }

    func testWaitForCasesRejectsCamelCaseBodyKey() {
        let json = """
        {
          "type": "wait_for_cases",
          "waitForCases": {
            "timeout": 1,
            "cases": [{
              "predicate": {"type": "present", "element": {"label": "Home"}},
              "steps": [{"type": "warn", "warn": {"message": "home"}}]
            }]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "Unknown wait_for_cases heist step field \"waitForCases\"")
        }
    }

    func testHeistExecutionStepThatStopsHeistIsFailure() {
        let result = HeistExecutionStepResult(
            index: 0,
            kind: .conditional,
            message: "Could not observe settled accessibility state before evaluating heist cases",
            durationMs: 0,
            stopsHeist: true
        )

        XCTAssertTrue(result.isFailure)
    }

    func testHeistValueRoundTrips() throws {
        let values: [HeistValue] = [
            .string("hello"),
            .int(42),
            .double(3.14),
            .bool(true),
            .array([.string("a"), .int(1)]),
            .object(["key": .string("val")]),
        ]

        for original in values {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(HeistValue.self, from: data)
            XCTAssertEqual(decoded, original)
        }
    }

    func testHeistValueDescriptionIsDeterministicAndQuoted() {
        let value = HeistValue.object([
            "text": .string(#"Save "Now""#),
            "count": .int(2),
            "flags": .array([.bool(true), .double(3.5)]),
        ])

        XCTAssertEqual(value.description, #"{"count"=2, "flags"=[true, 3.5], "text"="Save \"Now\""}"#)
    }

    func testActionStepDescriptionComposesCommandAndExpectation() throws {
        let step = try ActionStep(
            command: .activate(.predicate(ElementPredicate(label: "Save", traits: [.button]))),
            expectation: WaitStep(predicate: .changed(.screen()), timeout: 2)
        )

        XCTAssertEqual(
            step.description,
            #"action(command=activate expect=wait(changed(screen_changed) timeout=2))"#
        )
    }

    func testCurrentVersionIsOne() {
        XCTAssertEqual(HeistPlan.currentVersion, 1)
    }

    func testFullHeistJsonShape() throws {
        let heist = HeistPlan(steps: [
            try activateStep(label: "Go", traits: [.button]),
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(heist)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["version"] as? Int, HeistPlan.currentVersion)
        XCTAssertNil(json["app"])
        XCTAssertNil(json["recorded"])

        let steps = try XCTUnwrap(json["steps"] as? [[String: Any]])
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps.first?["type"] as? String, "action")
    }
}

private func activateStep(
    label: String,
    traits: [HeistTrait] = []
) throws -> HeistStep {
    .action(try ActionStep(
        command: .activate(.predicate(ElementPredicate(label: label, traits: traits)))
    ))
}
