import ButtonHeistTestSupport
import XCTest
import ThePlans
@testable import TheScore

final class HeistPlanTests: XCTestCase {

    func testHeistPlanRoundTrip() throws {
        let heist = try HeistPlan(body: [
            try activateStep(label: "Login", traits: [.button]),
            .action(ActionStep(command: .typeText(text: "user@example.com", target: nil))),
            try activateStep(label: "Submit", traits: [.button]),
        ])

        let data = try JSONEncoder().encode(heist)
        let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

        XCTAssertEqual(decoded.version, HeistPlan.currentVersion)
        XCTAssertEqual(decoded.body, heist.body)
    }

    func testDecodeRejectsUnsupportedVersionAtBoundary() {
        let json = """
        {
          "version": 3,
          "body": [{"type":"warn","warn":{"message":"check state"}}]
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistPlan.self, from: Data(json.utf8))) { error in
            guard let versionError = error as? HeistPlanVersionAdmissionError else {
                return XCTFail("Expected HeistPlanVersionAdmissionError, got \(error)")
            }
            XCTAssertEqual(versionError.observed, 3)
        }
    }

    func testDecodeRejectsUnknownTopLevelPlanField() {
        let json = """
        {
          "version": \(HeistPlan.currentVersion),
          "body": [{"type":"warn","warn":{"message":"check state"}}],
          "unexpectedField": {}
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistPlan.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpectedField"), "\(error)")
        }
    }

    func testDecodeRejectsEmptyPlan() {
        let json = #"{"version":\#(HeistPlan.currentVersion),"body":[]}"#

        XCTAssertThrowsError(try JSONDecoder().decode(HeistPlan.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("requires a non-empty body or definitions"), "\(error)")
        }
    }

    func testActionStepEncodesTypedClientMessage() throws {
        let step = try activateStep(label: "List", traits: [.adjustable])

        let data = try JSONEncoder().encode(step)
        let json = try JSONProbe(data: data)

        XCTAssertEqual(try json.string("type"), "action")
        let action = try json.object("action")
        let command = try action.object("command")
        XCTAssertEqual(try command.string("type"), "activate")
        let target = try command.object("payload").object("target")
        let checks = try target.array("checks")
        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(try checks[0].string("kind"), "label")
        let labelMatch = try checks[0].object("match")
        XCTAssertEqual(try labelMatch.string("mode"), "exact")
        XCTAssertEqual(try labelMatch.string("value"), "List")
        XCTAssertEqual(try checks[1].string("kind"), "traits")
        XCTAssertEqual(try checks[1].strings("values"), ["adjustable"])
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
              "payload": {
                "target": {
                  "checks": [{"kind": "label", "match": {"mode": "exact", "value": "Save"}}],
                  "unexpectedTargetField": "button_save"
                }
              }
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
              "payload": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Save"}}]}
            }
          }
        }
        """
        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("_recorded"), "\(error)")
        }
    }

    func testWaitWarnAndFailRoundTrip() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(predicate: .exists(.label("Ready")), timeout: 1.5)),
            .warn(WarnStep(message: "optional branch skipped")),
            .fail(FailStep(message: "unexpected state")),
        ])

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

        XCTAssertEqual(decoded, plan)
    }

    func testConditionalAndWaitRoundTrip() throws {
        let conditionCase = PredicateCase(
            predicate: .exists(.label("Home")),
            body: [.warn(WarnStep(message: "home"))]
        )
        let plan = try HeistPlan(body: [
            .conditional(try ConditionalStep(
                cases: [conditionCase],
                elseBody: [.warn(WarnStep(message: "not home"))]
            )),
            .wait(WaitStep(
                predicate: .exists(.label("Done")),
                timeout: 2,
                elseBody: [.fail(FailStep(message: "no known state"))]
            )),
        ])

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

        XCTAssertEqual(decoded, plan)
    }

    func testConditionalRejectsCamelCaseElseSteps() {
        let json = """
        {
          "type": "conditional",
          "conditional": {
            "cases": [{
              "predicate": {
                "type": "exists",
                "element": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Home"}}]}
              },
              "body": [{"type": "warn", "warn": {"message": "home"}}]
            }],
            "elseSteps": [{"type": "warn", "warn": {"message": "not home"}}]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("elseSteps"), "\(error)")
        }
    }

    func testWaitForCasesStepTypeIsRejected() {
        let json = """
        {
          "type": "wait_for_cases",
          "wait_for_cases": {
            "timeout": 1,
            "cases": [{
              "predicate": {
                "type": "exists",
                "element": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Home"}}]}
              },
              "body": [{"type": "warn", "warn": {"message": "home"}}]
            }],
            "elseSteps": [{"type": "warn", "warn": {"message": "not home"}}]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("wait_for_cases"), "\(error)")
        }
    }

    func testInvokeStepDecodesMissingArgumentAsNone() throws {
        let json = """
        {
          "type": "invoke",
          "invoke": {
            "path": "setup"
          }
        }
        """

        let decoded = try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))

        XCTAssertEqual(decoded, .invoke(HeistInvocationStep(path: "setup")))
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

    func testWaitRejectsNegativeTimeout() {
        let json = """
        {
          "type": "wait",
          "wait": {
            "predicate": {
              "type": "exists",
              "target": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Home"}}]}
            },
            "timeout": -1
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue(
                "\(error)".contains("wait timeout must be"),
                "\(error)"
            )
        }
    }

    func testWaitRejectsCamelCaseBodyKey() {
        let json = """
        {
          "type": "wait",
          "waitForCases": {
            "predicate": {
              "type": "exists",
              "element": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Home"}}]}
            },
            "timeout": 1
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "Unknown wait heist step field \"waitForCases\"")
        }
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
        let step = ActionStep(
            command: .activate(.predicate(ElementPredicateTemplate(label: "Save", traits: [.button]))),
            expectationPolicy: .expect(ActionExpectation(predicate: .changed(.screen()), timeout: 2)))

        XCTAssertEqual(
            step.description,
            #"action(command=activate expect=wait(changed(screen(*)) timeout=2))"#
        )
    }

    func testAccessibilityTargetSugarHashMatchesCanonicalValue() {
        let target = AccessibilityTarget.target(.label("Save"), ordinal: 1)
        let template = AccessibilityTarget.predicate(
            ElementPredicateTemplate(label: "Save"),
            ordinal: 1
        )

        XCTAssertEqual(target, template)
        XCTAssertEqual(Set([target, template]).count, 1)
    }

    // MARK: - ForEach

    func testForEachElementStepStoresRefBackedBodyAST() throws {
        let matching = ElementPredicateTemplate(label: "Cell", traits: [.button])
        let target = AccessibilityTarget(ref: "target")
        let step = try ForEachElementStep(
            matching: matching,
            limit: 5,
            parameter: "target",
            body: [
                .action(ActionStep(
                    command: .activate(target),
                    expectationPolicy: .expect(ActionExpectation(
                        predicate: .missing(target),
                        timeout: 2
                    )))),
                .warn(WarnStep(message: "activated one")),
            ]
        )

        XCTAssertEqual(
            step.body,
            [
                .action(ActionStep(
                    command: .activate(target),
                    expectationPolicy: .expect(ActionExpectation(
                        predicate: .missing(target),
                        timeout: 2
                    )))),
                .warn(WarnStep(message: "activated one")),
            ]
        )
    }

    func testForEachElementEncodesDurableBodyAST() throws {
        let matching = ElementPredicateTemplate(label: "Cell", traits: [.button])
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 5,
                parameter: "target",
                body: [.action(ActionStep(
                    command: .activate(AccessibilityTarget(ref: "target"))
                ))]
            )),
        ])

        let data = try JSONEncoder().encode(plan)
        let decoded = try JSONDecoder().decode(HeistPlan.self, from: data)

        XCTAssertEqual(decoded, plan)
    }

    func testForEachDecodeRejectsEmptyMatchingPredicate() {
        let json = """
        {
          "type": "for_each_element",
          "for_each_element": {
            "matching": {},
            "limit": 10,
            "parameter": "target",
            "body": [{"type": "warn", "warn": {"message": "hi"}}]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("AccessibilityTarget predicate requires"), "\(error)")
        }
    }

    func testForEachDecodeRejectsNonPositiveLimit() {
        let zeroJSON = """
        {
          "type": "for_each_element",
          "for_each_element": {
            "matching": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Cell"}}]},
            "limit": 0,
            "parameter": "target",
            "body": [{"type": "warn", "warn": {"message": "hi"}}]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(zeroJSON.utf8))) { error in
            XCTAssertTrue("\(error)".contains("invalidForEachLimit"), "\(error)")
        }

        let negativeJSON = """
        {
          "type": "for_each_element",
          "for_each_element": {
            "matching": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Cell"}}]},
            "limit": -1,
            "parameter": "target",
            "body": [{"type": "warn", "warn": {"message": "hi"}}]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(negativeJSON.utf8))) { error in
            XCTAssertTrue("\(error)".contains("invalidForEachLimit"), "\(error)")
        }
    }

    func testForEachDecodeRejectsMissingBodySteps() {
        let json = """
        {
          "type": "for_each_element",
          "for_each_element": {
            "matching": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Cell"}}]},
            "limit": 5,
            "parameter": "target"
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("body"), "\(error)")
        }
    }

    func testForEachDecodeRejectsOldForEachStepType() {
        let json = """
        {
          "type": "for_each",
          "for_each": {
            "matching": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Cell"}}]},
            "limit": 5,
            "element": {
              "checks": [{"kind": "label", "match": {"mode": "exact", "value": "Cell"}}],
              "ordinal": 0
            },
            "body": [{"type": "warn", "warn": {"message": "hi"}}]
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("for_each"), "\(error)")
        }
    }

    func testForEachDecodeRejectsUnknownFields() {
        let outerJSON = """
        {
          "type": "for_each_element",
          "for_each_element": {
            "matching": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Cell"}}]},
            "limit": 5,
            "parameter": "target",
            "body": [{"type": "warn", "warn": {"message": "hi"}}]
          },
          "unexpected": true
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(outerJSON.utf8))) { error in
            XCTAssertTrue("\(error)".contains("unexpected"), "\(error)")
        }

        let innerJSON = """
        {
          "type": "for_each_element",
          "for_each_element": {
            "matching": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Cell"}}]},
            "limit": 5,
            "parameter": "target",
            "body": [{"type": "warn", "warn": {"message": "hi"}}],
            "bogus": 42
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(innerJSON.utf8))) { error in
            XCTAssertTrue("\(error)".contains("bogus"), "\(error)")
        }
    }

    func testCurrentVersionIsOne() {
        XCTAssertEqual(HeistPlan.currentVersion, 2)
    }

    func testFullHeistJsonShape() throws {
        let heist = try HeistPlan(body: [
            try activateStep(label: "Go", traits: [.button]),
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(heist)
        let json = try JSONProbe(data: data)

        XCTAssertEqual(try json.int("version"), HeistPlan.currentVersion)
        try json.assertMissing("app")
        try json.assertMissing("recorded")

        let body = try json.array("body")
        XCTAssertEqual(body.count, 1)
        let step = try XCTUnwrap(body.first)
        XCTAssertEqual(try step.string("type"), "action")
    }
}

private func activateStep(
    label: String,
    traits: [HeistTrait] = []
) throws -> HeistStep {
    .action(ActionStep(
        command: .activate(.predicate(ElementPredicateTemplate(label: .exact(label), traits: traits)))
    ))
}
