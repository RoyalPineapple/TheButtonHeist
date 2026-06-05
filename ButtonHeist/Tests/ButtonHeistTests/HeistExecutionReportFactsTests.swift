import XCTest
@testable import ButtonHeist
import TheScore

/// The heist execution tree is the report structure. These tests lock the
/// report facts derived directly from `HeistExecutionResult` /
/// `HeistExecutionStepResult` — status, wire step name, command name, target,
/// final action result, surfaced expectation, and expectation counts.
final class HeistExecutionReportFactsTests: XCTestCase {

    func testActionWithExpectationReportsActionAndExpectation() {
        let expectationPredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .action,
                    actionCommand: .activate(.target(.predicate(ElementPredicate(label: "Submit")))),
                    actionResult: ActionResult(success: true, method: .activate),
                    expectation: ExpectationResult(met: true, predicate: expectationPredicate),
                    durationMs: 5
                ),
            ],
            totalTimingMs: 5
        )

        XCTAssertEqual(result.expectationsChecked, 1)
        XCTAssertEqual(result.expectationsMet, 1)
        XCTAssertEqual(result.steps.map(\.path), ["$.body[0]"])
        XCTAssertEqual(result.steps.first?.reportStepName, "action")
        XCTAssertEqual(result.steps.first?.reportCommandName, "activate")
    }

    func testReportFactsUseExecutionTreeInsteadOfPlanSiblingRematch() {
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    path: "$.body[9]",
                    kind: .action,
                    actionCommand: .activate(.target(.predicate(ElementPredicate(label: "Delete")))),
                    actionResult: ActionResult(success: true, method: .activate),
                    durationMs: 5
                ),
            ],
            totalTimingMs: 5
        )

        XCTAssertEqual(result.steps.map(\.path), ["$.body[9]"])
        XCTAssertEqual(result.steps.first?.reportStepName, "action")
        XCTAssertEqual(result.steps.first?.reportCommandName, "activate")
        XCTAssertEqual(result.steps.first?.reportTarget, .predicate(ElementPredicate(label: "Delete")))
    }

    func testFailedActionSkipsLaterSibling() {
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .action,
                    actionResult: ActionResult(
                        success: false,
                        method: .activate,
                        message: "Delete failed",
                        errorKind: .actionFailed
                    ),
                    durationMs: 4,
                    stopsHeist: true
                ),
                HeistExecutionStepResult(
                    index: 1,
                    kind: .skipped,
                    durationMs: 0,
                    skipped: HeistExecutionSkippedStepResult(
                        index: 1,
                        reason: "skipped: heist stopped after step 0",
                        afterFailedIndex: 0
                    )
                ),
            ],
            totalTimingMs: 4,
            failedIndex: 0
        )

        XCTAssertEqual(result.steps.map(\.reportStatus), [.failed, .skipped])
        XCTAssertEqual(result.steps.map(\.reportMessage), [nil, "skipped: heist stopped after step 0"])
        XCTAssertEqual(result.steps.first?.reportActionResult?.message, "Delete failed")
    }

    func testWaitReportsWaitNode() {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .wait,
                    actionResult: ActionResult(success: true, method: .wait),
                    expectation: ExpectationResult(met: true, predicate: predicate),
                    durationMs: 20
                ),
            ],
            totalTimingMs: 20
        )

        let node = result.steps[0]
        XCTAssertEqual(node.path, "$.body[0]")
        XCTAssertEqual(node.reportStepName, "wait")
        XCTAssertEqual(node.reportStatus, .passed)
        XCTAssertEqual(node.reportExpectation?.met, true)
        XCTAssertNil(node.reportActionResult)
    }

    func testConditionalSelectedCaseKeepsOnlySelectedChildren() {
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .conditional,
                    durationMs: 8,
                    caseSelection: HeistCaseSelectionResult(
                        cases: [],
                        selectedCaseIndex: 0,
                        elapsedMs: 1
                    ),
                    children: [
                        HeistExecutionStepResult(
                            index: 0,
                            path: "$.body[0].conditional.cases[0].body[0]",
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 7
                        ),
                    ]
                ),
            ],
            totalTimingMs: 8
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStepName, "if")
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].conditional.cases[0].body[0]"])
        XCTAssertEqual(node.children.first?.reportCommandName, "activate")
    }

    func testConditionalElseKeepsOnlyElseChildren() {
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .conditional,
                    durationMs: 3,
                    caseSelection: HeistCaseSelectionResult(
                        cases: [],
                        selectedCaseIndex: nil,
                        elapsedMs: 1,
                        elseRan: true
                    ),
                    children: [
                        HeistExecutionStepResult(
                            index: 0,
                            path: "$.body[0].conditional.else_body[0]",
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 2
                        ),
                    ]
                ),
            ],
            totalTimingMs: 3
        )

        let node = result.steps[0]
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].conditional.else_body[0]"])
    }

    func testWaitForTimeoutWithoutElseReportsWaitFailure() {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .waitForCases,
                    message: "timed out after 2s waiting for heist case",
                    durationMs: 2000,
                    stopsHeist: true,
                    caseSelection: HeistCaseSelectionResult(
                        cases: [caseMatch(predicate, met: false)],
                        selectedCaseIndex: nil,
                        elapsedMs: 2000,
                        timeout: 2,
                        timedOut: true
                    )
                ),
            ],
            totalTimingMs: 2000,
            failedIndex: 0
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStepName, "wait_for_cases")
        XCTAssertEqual(node.reportStatus, .failed)
        XCTAssertEqual(node.children.count, 0)
        XCTAssertEqual(node.caseSelection?.timedOut, true)
    }

    func testWaitForTimeoutWithElseReportsElseChildrenAsHandled() {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .waitForCases,
                    message: "timed out after 2s; else ran",
                    durationMs: 2000,
                    caseSelection: HeistCaseSelectionResult(
                        cases: [caseMatch(predicate, met: false)],
                        selectedCaseIndex: nil,
                        elapsedMs: 2000,
                        timeout: 2,
                        timedOut: true,
                        elseRan: true
                    ),
                    children: [
                        HeistExecutionStepResult(
                            index: 0,
                            path: "$.body[0].wait_for_cases.else_body[0]",
                            kind: .warn,
                            message: "No result",
                            durationMs: 1
                        ),
                    ]
                ),
            ],
            totalTimingMs: 2000
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStatus, .passed)
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].wait_for_cases.else_body[0]"])
        XCTAssertEqual(node.children.first?.reportStatus, .warned)
    }

    func testForEachSuccessGroupsChildrenByIteration() {
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    path: "$.body[0]",
                    kind: .forEachElement,
                    message: "for_each completed 2 iteration(s) from 2 matched element(s)",
                    durationMs: 20,
                    forEachResult: HeistForEachResult(matchedCount: 2, limit: 20, iterationCount: 2),
                    children: [
                        forEachIteration(path: "$.body[0].for_each_element.iterations[0]", durationMs: 5),
                        forEachIteration(path: "$.body[0].for_each_element.iterations[1]", durationMs: 6),
                    ]
                ),
            ],
            totalTimingMs: 20
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStepName, "for_each_element")
        XCTAssertEqual(node.children.map(\.path), [
            "$.body[0].for_each_element.iterations[0]",
            "$.body[0].for_each_element.iterations[1]",
        ])
        XCTAssertEqual(node.children.flatMap { $0.children.map(\.path) }, [
            "$.body[0].for_each_element.iterations[0].body[0]",
            "$.body[0].for_each_element.iterations[1].body[0]",
        ])
    }

    func testForEachBodyFailureReportsIterationFailureInStructuredNodes() {
        let result = forEachStringFailureResult()
        let node = result.steps[0]

        XCTAssertEqual(node.reportStatus, .failed)
        XCTAssertEqual(node.children.map(\.reportStatus), [.passed, .failed])
        XCTAssertEqual(node.children[1].children.first?.reportActionResult?.message, "field missing")
        XCTAssertEqual(node.reportMessage, "for_each_string stopped after 2 of 2 iteration(s): iteration 1 failed for value \"Eggs\"")
    }

    func testWarnAndFailAreStructuralNodes() {
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(index: 0, kind: .warn, message: "Heads up", durationMs: 1),
                HeistExecutionStepResult(index: 1, kind: .fail, message: "Stop here", durationMs: 1, stopsHeist: true),
            ],
            totalTimingMs: 2,
            failedIndex: 1
        )

        XCTAssertEqual(result.steps.map(\.reportStepName), ["warn", "fail"])
        XCTAssertEqual(result.steps.map(\.reportStatus), [.warned, .failed])
    }

    func testInlineHeistKeepsChildBodyPaths() {
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .heist,
                    durationMs: 5,
                    children: [
                        HeistExecutionStepResult(
                            index: 0,
                            path: "$.body[0].heist.body[0]",
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 5
                        ),
                    ]
                ),
            ],
            totalTimingMs: 5
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStepName, "heist")
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].heist.body[0]"])
        XCTAssertEqual(node.children.first?.reportCommandName, "activate")
    }

    func testInvokeKeepsDefinitionBodyPaths() {
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .invoke,
                    durationMs: 5,
                    children: [
                        HeistExecutionStepResult(
                            index: 0,
                            path: "$.body[0].invoke.body[0]",
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 5
                        ),
                    ]
                ),
            ],
            totalTimingMs: 5
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStepName, "invoke")
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].invoke.body[0]"])
        XCTAssertEqual(node.children.first?.reportCommandName, "activate")
    }

    func testForEachBodyResultsStayNestedUnderLoopNode() throws {
        let result = forEachStringFailureResult()
        let node = try XCTUnwrap(result.steps.first)

        XCTAssertEqual(node.reportStepName, "for_each_string")
        XCTAssertEqual(node.reportStatus, .failed)
        XCTAssertEqual(node.reportMessage, "for_each_string stopped after 2 of 2 iteration(s): iteration 1 failed for value \"Eggs\"")
        XCTAssertEqual(node.children.map(\.path), [
            "$.body[0].for_each_string.iterations[0]",
            "$.body[0].for_each_string.iterations[1]",
        ])
        XCTAssertEqual(node.children[1].children.first?.reportCommandName, "typeText")
    }

    // MARK: - Fixtures

    private func forEachIteration(path: String, durationMs: Int) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            index: 0,
            path: path,
            kind: .forEachIteration,
            durationMs: durationMs,
            children: [
                HeistExecutionStepResult(
                    index: 0,
                    path: "\(path).body[0]",
                    kind: .action,
                    actionResult: ActionResult(success: true, method: .activate),
                    durationMs: durationMs
                ),
            ]
        )
    }

    private func forEachStringFailureResult() -> HeistExecutionResult {
        HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    path: "$.body[0]",
                    kind: .forEachString,
                    message: "for_each_string stopped after 2 of 2 iteration(s): iteration 1 failed for value \"Eggs\"",
                    durationMs: 30,
                    stopsHeist: true,
                    forEachResult: HeistForEachResult(
                        matchedCount: 2,
                        limit: 2,
                        iterationCount: 2,
                        failureReason: "iteration 1 failed for value \"Eggs\""
                    ),
                    children: [
                        HeistExecutionStepResult(
                            index: 0,
                            path: "$.body[0].for_each_string.iterations[0]",
                            kind: .forEachIteration,
                            message: "iteration 0 value \"Milk\"",
                            durationMs: 5,
                            children: [
                                HeistExecutionStepResult(
                                    index: 0,
                                    path: "$.body[0].for_each_string.iterations[0].body[0]",
                                    kind: .action,
                                    actionResult: ActionResult(success: true, method: .typeText),
                                    durationMs: 5
                                ),
                            ]
                        ),
                        HeistExecutionStepResult(
                            index: 1,
                            path: "$.body[0].for_each_string.iterations[1]",
                            kind: .forEachIteration,
                            message: "iteration 1 value \"Eggs\"",
                            durationMs: 6,
                            stopsHeist: true,
                            children: [
                                HeistExecutionStepResult(
                                    index: 0,
                                    path: "$.body[0].for_each_string.iterations[1].body[0]",
                                    kind: .action,
                                    actionResult: ActionResult(
                                        success: false,
                                        method: .typeText,
                                        message: "field missing",
                                        errorKind: .elementNotFound
                                    ),
                                    durationMs: 6,
                                    stopsHeist: true
                                ),
                            ]
                        ),
                    ]
                ),
            ],
            totalTimingMs: 30,
            failedIndex: 0
        )
    }

    private func caseMatch(_ predicate: AccessibilityPredicate, met: Bool) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicate,
            result: ExpectationResult(met: met, predicate: predicate)
        )
    }
}
