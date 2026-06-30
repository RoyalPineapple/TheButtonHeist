import ButtonHeistTestSupport
import XCTest
import ThePlans
@testable import TheScore

final class HeistPlanTests: XCTestCase {

    func testHeistPlanRoundTrip() throws {
        let heist = try HeistPlan(body: [
            try activateStep(label: "Login", traits: [.button]),
            .action(try ActionStep(command: .typeText(text: .literal("user@example.com"), target: nil))),
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
          "version": 2,
          "body": [{"type":"warn","warn":{"message":"check state"}}]
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
        let target = try command.object("payload")
        let checks = try target.array("checks")
        XCTAssertEqual(checks.count, 2)
        XCTAssertEqual(try checks[0].string("kind"), "label")
        XCTAssertEqual(try checks[0].string("match"), "List")
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
        let plan = try HeistPlan(body: [
            .wait(WaitStep(predicate: .state(.exists(ElementPredicate(label: "Ready"))), timeout: 1.5)),
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
                predicate: .state(.exists(ElementPredicate(label: "Done"))),
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
              "predicate": {"type": "exists", "element": {"label": "Home"}},
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
              "predicate": {"type": "exists", "element": {"label": "Home"}},
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
            "path": ["setup"]
          }
        }
        """

        let decoded = try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))

        XCTAssertEqual(decoded, .invoke(HeistInvocationStep(path: ["setup"])))
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
            "predicate": {"type": "exists", "element": {"label": "Home"}},
            "timeout": -1
          }
        }
        """

        XCTAssertThrowsError(try JSONDecoder().decode(HeistStep.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("timeout must be non-negative"), "\(error)")
        }
    }

    func testWaitRejectsCamelCaseBodyKey() {
        let json = """
        {
          "type": "wait",
          "waitForCases": {
            "predicate": {"type": "exists", "element": {"label": "Home"}},
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

    func testHeistExecutionStepThatStopsHeistIsFailure() {
        let result = HeistExecutionStepResult.failed(
            path: "$.body[0]",
            kind: .conditional,
            durationMs: 0,
            failure: HeistFailureDetail(
                category: .runtimeUnavailable,
                contract: "settled accessibility state is observable before evaluating heist cases",
                observed: "Could not observe settled accessibility state before evaluating heist cases"
            )
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
            command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Save")), traits: [.button]))),
            expectation: WaitStep(predicate: .change(.screen()), timeout: 2)
        )

        XCTAssertEqual(
            step.description,
            #"action(command=activate expect=wait(change(screen(*)) timeout=2))"#
        )
    }

    func testElementTargetExprHashMatchesCrossCaseEquality() {
        let target = ElementTargetExpr.target(.predicate(ElementPredicate(label: "Save"), ordinal: 1))
        let template = ElementTargetExpr.predicate(ElementPredicateTemplate(label: .exact(.literal("Save"))), ordinal: 1)

        XCTAssertEqual(target, template)
        XCTAssertEqual(Set([target, template]).count, 1)
    }

    // MARK: - ForEach

    func testForEachElementStepStoresRefBackedBodyAST() throws {
        let matching = ElementPredicate(label: "Cell", traits: [.button])
        let target = try ElementTargetExpr(ref: HeistReferenceName(rawValue: "target"))
        let step = try ForEachElementStep(
            matching: matching,
            limit: 5,
            parameter: "target",
            body: [
                .action(try ActionStep(
                    command: .activate(target),
                    expectation: WaitStep(
                        predicate: .state(.missingTarget(target)),
                        timeout: 2
                    )
                )),
                .warn(WarnStep(message: "activated one")),
            ]
        )

        XCTAssertEqual(
            step.body,
            [
                .action(try ActionStep(
                    command: .activate(target),
                    expectation: WaitStep(
                        predicate: .state(.missingTarget(target)),
                        timeout: 2
                    )
                )),
                .warn(WarnStep(message: "activated one")),
            ]
        )
    }

    func testForEachElementEncodesDurableBodyAST() throws {
        let matching = ElementPredicate(label: "Cell", traits: [.button])
        let plan = try HeistPlan(body: [
            .forEachElement(try ForEachElementStep(
                matching: matching,
                limit: 5,
                parameter: "target",
                body: [.action(try ActionStep(
                    command: .activate(try ElementTargetExpr(ref: HeistReferenceName(rawValue: "target")))
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
            XCTAssertTrue("\(error)".contains("emptyForEachPredicate"), "\(error)")
        }
    }

    func testForEachDecodeRejectsNonPositiveLimit() {
        let zeroJSON = """
        {
          "type": "for_each_element",
          "for_each_element": {
            "matching": {"label": "Cell"},
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
            "matching": {"label": "Cell"},
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
            "matching": {"label": "Cell"},
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
            "matching": {"label": "Cell"},
            "limit": 5,
            "element": {"label": "Cell", "ordinal": 0},
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
            "matching": {"label": "Cell"},
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
            "matching": {"label": "Cell"},
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

    func testForEachExecutionResultWithFailureIsFailure() {
        let result = HeistExecutionStepResult.failed(
            path: "$.body[0]",
            kind: .forEachElement,
            durationMs: 100,
            evidence: .forEachElement(HeistForEachElementEvidence(
                parameter: "target",
                matching: ElementPredicate(label: "Cell"),
                limit: 10,
                matchedCount: 3,
                iterationCount: 2,
                failureReason: "child step failed at iteration 2"
            )),
            failure: HeistFailureDetail(
                category: .loop,
                contract: "for_each_element completes all matched iterations",
                observed: "child step failed at iteration 2"
            )
        )

        XCTAssertTrue(result.isFailure)
    }

    func testForEachExecutionResultWithoutFailureIsNotFailure() {
        let result = HeistExecutionStepResult.passed(
            path: "$.body[0]",
            kind: .forEachElement,
            durationMs: 100,
            evidence: .forEachElement(HeistForEachElementEvidence(
                parameter: "target",
                matching: ElementPredicate(label: "Cell"),
                limit: 10,
                matchedCount: 3,
                iterationCount: 3
            ))
        )

        XCTAssertFalse(result.isFailure)
    }

    func testCurrentVersionIsOne() {
        XCTAssertEqual(HeistPlan.currentVersion, 1)
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
    .action(try ActionStep(
        command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal(label)), traits: traits)))
    ))
}
