import XCTest
@testable import ButtonHeist
import TheScore

final class TheFenceCompactFormattingContractTests: XCTestCase {

    func testCompactActionRenderingUsesParsedCommandNames() {
        let cases: [(command: TheFence.Command, method: ActionMethod, expected: String)] = [
            (.typeText, .typeText, "type_text: ok"),
            (.wait, .wait, "wait: ok"),
            (.activate, .customAction, "activate: ok"),
            (.dismissKeyboard, .resignFirstResponder, "dismiss_keyboard: ok"),
            (.oneFingerTap, .syntheticTap, "one_finger_tap: ok"),
        ]

        for testCase in cases {
            let output = FenceResponse.action(
                command: testCase.command,
                result: ActionResult(success: true, method: testCase.method)
            ).compactFormatted()

            XCTAssertEqual(output, testCase.expected)
        }
    }

    func testCompactActionRenderingDoesNotInferCommandFromActionMethod() {
        let output = FenceResponse.action(
            command: .drag,
            result: ActionResult(success: true, method: .syntheticTap)
        ).compactFormatted()

        XCTAssertEqual(output, "drag: ok")
    }

    func testExplicitOneFingerTapKeepsMechanicalResultIdentity() {
        let result = ActionResult(success: true, method: .syntheticTap)
        let output = FenceResponse.action(command: .oneFingerTap, result: result).compactFormatted()

        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertEqual(output, "one_finger_tap: ok")
    }

    func testHumanHeistFormattingCountsNestedProjectedExpectations() throws {
        let expected = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let childAction = try HeistStep.action(ActionStep(
            command: .activate(.predicate(ElementPredicate(label: "Submit"))),
            expectation: WaitStep(predicate: expected, timeout: 1)
        ))
        let casePredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Home")))
        let conditional = try ConditionalStep(cases: [
            PredicateCase(predicate: casePredicate, body: [childAction]),
        ])
        let plan = HeistPlan(body: [.conditional(conditional)])
        let childResult = HeistExecutionStepResult(
            index: 0,
            path: "$.body[0].conditional.cases[0].body[0]",
            kind: .action,
            actionResult: ActionResult(success: true, method: .activate),
            expectation: ExpectationResult(met: true, predicate: expected),
            durationMs: 1
        )
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .conditional,
                    durationMs: 1,
                    caseSelection: HeistCaseSelectionResult(
                        cases: [
                            HeistCaseMatchResult(
                                predicate: casePredicate,
                                result: ExpectationResult(met: true, predicate: casePredicate)
                            ),
                        ],
                        selectedCaseIndex: 0,
                        elapsedMs: 1
                    ),
                    children: [childResult]
                ),
            ],
            totalTimingMs: 1
        )

        let output = FenceResponse.heistExecution(plan: plan, result: result).humanFormatted()

        XCTAssertTrue(output.contains("[expectations: 1/1 met]"), output)
    }

    func testCompactHeistFormattingReportsFailStepMessage() {
        let plan = HeistPlan(body: [.fail(FailStep(message: "Unknown screen"))])
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .fail,
                    message: "Unknown screen",
                    durationMs: 1,
                    stopsHeist: true
                ),
            ],
            totalTimingMs: 1,
            failedIndex: 0
        )

        let output = FenceResponse.heistExecution(plan: plan, result: result).compactFormatted()

        XCTAssertTrue(output.contains("[0] fail -> error: Unknown screen"), output)
    }

    func testPublicHeistJSONReportsFailStepMessage() {
        let plan = HeistPlan(body: [.fail(FailStep(message: "Unknown screen"))])
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .fail,
                    message: "Unknown screen",
                    durationMs: 1,
                    stopsHeist: true
                ),
            ],
            totalTimingMs: 1,
            failedIndex: 0
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

        let json = publicJSONObject(response)
        let report = json["report"] as? [String: Any]
        let nodes = report?["nodes"] as? [[String: Any]]

        XCTAssertEqual(json["status"] as? String, "partial")
        XCTAssertNil(json["results"])
        XCTAssertEqual(nodes?.first?["path"] as? String, "$.body[0]")
        XCTAssertEqual(nodes?.first?["kind"] as? String, "fail")
        XCTAssertEqual(nodes?.first?["status"] as? String, "failed")
        XCTAssertEqual(nodes?.first?["message"] as? String, "Unknown screen")
    }

    func testPublicHeistJSONReportsNestedSelectedCaseFailureAsTreeNodes() throws {
        let childAction = try HeistStep.action(ActionStep(
            command: .activate(.target(.predicate(ElementPredicate(label: "Continue"))))
        ))
        let casePredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Ready")))
        let conditional = try ConditionalStep(cases: [
            PredicateCase(predicate: casePredicate, body: [childAction]),
        ])
        let plan = HeistPlan(body: [.conditional(conditional)])
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .conditional,
                    durationMs: 9,
                    stopsHeist: true,
                    caseSelection: HeistCaseSelectionResult(
                        cases: [
                            HeistCaseMatchResult(
                                predicate: casePredicate,
                                result: ExpectationResult(met: true, predicate: casePredicate)
                            ),
                        ],
                        selectedCaseIndex: 0,
                        elapsedMs: 1
                    ),
                    children: [
                        HeistExecutionStepResult(
                            index: 0,
                            path: "$.body[0].conditional.cases[0].body[0]",
                            kind: .action,
                            actionResult: ActionResult(
                                success: false,
                                method: .activate,
                                message: "nested button failed",
                                errorKind: .actionFailed
                            ),
                            durationMs: 8,
                            stopsHeist: true
                        ),
                    ]
                ),
            ],
            totalTimingMs: 9,
            failedIndex: 0
        )

        let json = publicJSONObject(.heistExecution(plan: plan, result: result))
        let report = try XCTUnwrap(json["report"] as? [String: Any])
        let nodes = try XCTUnwrap(report["nodes"] as? [[String: Any]])
        let root = try XCTUnwrap(nodes.first)
        let children = try XCTUnwrap(root["children"] as? [[String: Any]])
        let child = try XCTUnwrap(children.first)
        let caseSelection = try XCTUnwrap(root["caseSelection"] as? [String: Any])
        let action = try XCTUnwrap(child["action"] as? [String: Any])
        let actionResult = try XCTUnwrap(action["result"] as? [String: Any])

        XCTAssertNil(json["results"])
        XCTAssertEqual(root["path"] as? String, "$.body[0]")
        XCTAssertEqual(root["kind"] as? String, "if")
        XCTAssertEqual(caseSelection["selectedCaseIndex"] as? Int, 0)
        XCTAssertEqual(child["path"] as? String, "$.body[0].conditional.cases[0].body[0]")
        XCTAssertEqual(child["kind"] as? String, "action")
        XCTAssertEqual(child["status"] as? String, "failed")
        XCTAssertEqual(action["commandName"] as? String, "activate")
        XCTAssertEqual(actionResult["status"] as? String, "error")
        XCTAssertEqual(actionResult["message"] as? String, "nested button failed")
    }

}
