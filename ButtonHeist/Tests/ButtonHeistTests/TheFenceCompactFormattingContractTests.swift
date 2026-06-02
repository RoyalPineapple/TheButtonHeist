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

    func testCompactScrollSearchUsesDescriptorProjectedCommandName() {
        let search = ScrollSearchResult(
            scrollCount: 0,
            uniqueElementsSeen: 0,
            exhaustive: false
        )
        let output = FenceResponse.action(
            command: .scrollToVisible,
            result: ActionResult(
                success: true,
                method: .scrollToVisible,
                payload: .scrollSearch(search)
            )
        ).compactFormatted()

        XCTAssertEqual(output, "scroll_to_visible: already visible")
    }

    func testCompactActionRenderingDoesNotInferCommandFromActionMethod() {
        let output = FenceResponse.action(
            command: .drag,
            result: ActionResult(success: true, method: .syntheticTap)
        ).compactFormatted()

        XCTAssertEqual(output, "drag: ok")
    }

    func testHumanHeistFormattingCountsNestedProjectedExpectations() throws {
        let expected = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let childAction = try HeistStep.action(ActionStep(
            command: .activate(.predicate(ElementPredicate(label: "Submit"))),
            expectation: WaitStep(predicate: expected, timeout: 1)
        ))
        let casePredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Home")))
        let conditional = try ConditionalStep(cases: [
            PredicateCase(predicate: casePredicate, steps: [childAction]),
        ])
        let plan = HeistPlan(steps: [.conditional(conditional)])
        let childResult = HeistExecutionStepResult(
            index: 0,
            kind: .action,
            actionResult: ActionResult(success: true, method: .activate),
            expectation: ExpectationResult(met: true, predicate: expected),
            durationMs: 1
        )
        let result = HeistExecutionResult(
            steps: [
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
                    childResults: [childResult]
                ),
            ],
            totalTimingMs: 1
        )

        let output = FenceResponse.heistExecution(plan: plan, result: result).humanFormatted()

        XCTAssertTrue(output.contains("[expectations: 1/1 met]"), output)
    }

    func testCompactHeistFormattingReportsFailStepMessage() {
        let plan = HeistPlan(steps: [.fail(FailStep(message: "Unknown screen"))])
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
        let plan = HeistPlan(steps: [.fail(FailStep(message: "Unknown screen"))])
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
        let results = json["results"] as? [[String: Any]]

        XCTAssertEqual(json["status"] as? String, "partial")
        XCTAssertEqual(results?.first?["status"] as? String, "error")
        XCTAssertEqual(results?.first?["message"] as? String, "Unknown screen")
    }

}
