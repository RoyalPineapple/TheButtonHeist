import XCTest
@testable import ButtonHeist
import TheScore

final class HeistReportProjectionTests: XCTestCase {

    func testActionWithExpectationProjectsActionAndExpectation() throws {
        let expectationPredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let step = try actionStep(
            command: .activate(.target(.predicate(ElementPredicate(label: "Submit")))),
            expectation: WaitStep(predicate: expectationPredicate, timeout: 1)
        )
        let plan = HeistPlan(body: [step])
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .action,
                    actionResult: ActionResult(success: true, method: .activate),
                    expectation: ExpectationResult(met: true, predicate: expectationPredicate),
                    durationMs: 5
                ),
            ],
            totalTimingMs: 5
        )

        let projection = HeistReportProjection(plan: plan, result: result)

        XCTAssertEqual(projection.summary.expectationsChecked, 1)
        XCTAssertEqual(projection.summary.expectationsMet, 1)
        XCTAssertEqual(projection.nodes.map(\.path), ["$.body[0]"])
        XCTAssertEqual(projection.nodes.first?.kind, .action)
        XCTAssertEqual(projection.nodes.first?.action?.commandName, "activate")
    }

    func testFailedActionSkipsLaterSibling() throws {
        let plan = HeistPlan(body: [
            try actionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Delete"))))),
            try actionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Confirm"))))),
        ])
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

        let projection = HeistReportProjection(plan: plan, result: result)

        XCTAssertEqual(projection.nodes.map(\.status), [.failed, .skipped])
        XCTAssertEqual(projection.nodes.map(\.message), [nil, "skipped: heist stopped after step 0"])
        XCTAssertEqual(projection.nodes.first?.action?.finalActionResult?.message, "Delete failed")
    }

    func testWaitProjectsWaitNode() throws {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let plan = HeistPlan(body: [.wait(WaitStep(predicate: predicate, timeout: 2))])
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

        let node = HeistReportProjection(plan: plan, result: result).nodes[0]

        XCTAssertEqual(node.path, "$.body[0]")
        XCTAssertEqual(node.kind, .wait)
        XCTAssertEqual(node.status, .passed)
        XCTAssertEqual(node.expectation?.met, true)
        XCTAssertNil(node.action)
    }

    func testConditionalSelectedCaseProjectsOnlySelectedChildren() throws {
        let child = try actionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Home")))))
        let unselected = try actionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Login")))))
        let selectedPredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Home")))
        let unselectedPredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Login")))
        let conditional = try ConditionalStep(cases: [
            PredicateCase(predicate: selectedPredicate, body: [child]),
            PredicateCase(predicate: unselectedPredicate, body: [unselected]),
        ])
        let plan = HeistPlan(body: [.conditional(conditional)])
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .conditional,
                    durationMs: 8,
                    caseSelection: HeistCaseSelectionResult(
                        cases: [
                            caseMatch(selectedPredicate, met: true),
                            caseMatch(unselectedPredicate, met: false),
                        ],
                        selectedCaseIndex: 0,
                        elapsedMs: 1
                    ),
                    childResults: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 7
                        ),
                    ]
                ),
            ],
            totalTimingMs: 8
        )

        let node = HeistReportProjection(plan: plan, result: result).nodes[0]

        XCTAssertEqual(node.kind, .conditional)
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].conditional.cases[0].body[0]"])
        XCTAssertEqual(node.children.first?.action?.commandName, "activate")
    }

    func testConditionalElseProjectsOnlyElseChildren() throws {
        let elseStep = try actionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Fallback")))))
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Home")))
        let conditional = try ConditionalStep(
            cases: [PredicateCase(predicate: predicate, body: [try actionStep()])],
            elseBody: [elseStep]
        )
        let plan = HeistPlan(body: [.conditional(conditional)])
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .conditional,
                    durationMs: 3,
                    caseSelection: HeistCaseSelectionResult(
                        cases: [caseMatch(predicate, met: false)],
                        selectedCaseIndex: nil,
                        elapsedMs: 1,
                        elseRan: true
                    ),
                    childResults: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 2
                        ),
                    ]
                ),
            ],
            totalTimingMs: 3
        )

        let node = HeistReportProjection(plan: plan, result: result).nodes[0]

        XCTAssertEqual(node.children.map(\.path), ["$.body[0].conditional.else_body[0]"])
    }

    func testWaitForTimeoutWithoutElseProjectsWaitFailure() throws {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let waitForCases = try WaitForCasesStep(
            timeout: 2,
            cases: [PredicateCase(predicate: predicate, body: [try actionStep()])]
        )
        let plan = HeistPlan(body: [.waitForCases(waitForCases)])
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

        let node = HeistReportProjection(plan: plan, result: result).nodes[0]

        XCTAssertEqual(node.kind, .waitForCases)
        XCTAssertEqual(node.status, .failed)
        XCTAssertEqual(node.children.count, 0)
        XCTAssertEqual(node.caseSelection?.timedOut, true)
    }

    func testWaitForTimeoutWithElseProjectsElseChildrenAsHandled() throws {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let waitForCases = try WaitForCasesStep(
            timeout: 2,
            cases: [PredicateCase(predicate: predicate, body: [try actionStep()])],
            elseBody: [.warn(WarnStep(message: "No result"))]
        )
        let plan = HeistPlan(body: [.waitForCases(waitForCases)])
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
                    childResults: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .warn,
                            message: "No result",
                            durationMs: 1
                        ),
                    ]
                ),
            ],
            totalTimingMs: 2000
        )

        let node = HeistReportProjection(plan: plan, result: result).nodes[0]

        XCTAssertEqual(node.status, .passed)
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].wait_for_cases.else_body[0]"])
        XCTAssertEqual(node.children.first?.status, .warned)
    }

    func testForEachSuccessGroupsChildrenByIteration() throws {
        let forEach = try ForEachElementStep(
            matching: ElementPredicate(label: "Delete"),
            limit: 20,
            parameter: "target",
            body: [try actionStep(command: .activate(.ref("target")))]
        )
        let plan = HeistPlan(body: [.forEachElement(forEach)])
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .forEach,
                    message: "for_each completed 2 iteration(s) from 2 matched element(s)",
                    durationMs: 20,
                    forEachResult: HeistForEachResult(matchedCount: 2, limit: 20, iterationCount: 2),
                    childResults: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 5
                        ),
                        HeistExecutionStepResult(
                            index: 1,
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 6
                        ),
                    ]
                ),
            ],
            totalTimingMs: 20
        )

        let node = HeistReportProjection(plan: plan, result: result).nodes[0]

        XCTAssertEqual(node.kind, .forEachElement)
        XCTAssertEqual(node.children.map(\.path), [
            "$.body[0].for_each_element.iterations[0]",
            "$.body[0].for_each_element.iterations[1]",
        ])
        XCTAssertEqual(node.children.flatMap { $0.children.map(\.path) }, [
            "$.body[0].for_each_element.iterations[0].body[0]",
            "$.body[0].for_each_element.iterations[1].body[0]",
        ])
    }

    func testForEachBodyFailureReportsIterationFailureInStructuredNodes() throws {
        let forEach = try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [try actionStep(command: .typeText(text: .ref("item"), target: nil))]
        )
        let plan = HeistPlan(body: [.forEachString(forEach)])
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .forEach,
                    message: "for_each_string stopped after 2 of 2 iteration(s): iteration 1 failed for value \"Eggs\"",
                    durationMs: 30,
                    stopsHeist: true,
                    forEachResult: HeistForEachResult(
                        matchedCount: 2,
                        limit: 2,
                        iterationCount: 2,
                        failureReason: "iteration 1 failed for value \"Eggs\""
                    ),
                    childResults: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .typeText),
                            durationMs: 5
                        ),
                        HeistExecutionStepResult(
                            index: 1,
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
            ],
            totalTimingMs: 30,
            failedIndex: 0
        )

        let projection = HeistReportProjection(plan: plan, result: result)
        let node = projection.nodes[0]

        XCTAssertEqual(node.status, .failed)
        XCTAssertEqual(node.children.map(\.status), [.passed, .failed])
        XCTAssertEqual(node.children[1].children.first?.action?.finalActionResult?.message, "field missing")
        XCTAssertEqual(node.message, "for_each_string stopped after 2 of 2 iteration(s): iteration 1 failed for value \"Eggs\"")
    }

    func testWarnAndFailProjectAsStructuralNodes() {
        let plan = HeistPlan(body: [
            .warn(WarnStep(message: "Heads up")),
            .fail(FailStep(message: "Stop here")),
        ])
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .warn,
                    message: "Heads up",
                    durationMs: 1
                ),
                HeistExecutionStepResult(
                    index: 1,
                    kind: .fail,
                    message: "Stop here",
                    durationMs: 1,
                    stopsHeist: true
                ),
            ],
            totalTimingMs: 2,
            failedIndex: 1
        )

        let projection = HeistReportProjection(plan: plan, result: result)

        XCTAssertEqual(projection.nodes.map(\.kind), [.warn, .fail])
        XCTAssertEqual(projection.nodes.map(\.status), [.warned, .failed])
    }

    func testInlineHeistProjectsChildBodyPaths() throws {
        let inlinePlan = HeistPlan(
            name: "checkout",
            body: [try actionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Checkout")))))]
        )
        let plan = HeistPlan(body: [.heist(inlinePlan)])
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .heist,
                    durationMs: 5,
                    childResults: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 5
                        ),
                    ]
                ),
            ],
            totalTimingMs: 5
        )

        let node = HeistReportProjection(plan: plan, result: result).nodes[0]

        XCTAssertEqual(node.kind, .heist)
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].heist.body[0]"])
        XCTAssertEqual(node.children.first?.action?.commandName, "activate")
    }

    func testInvokeProjectsDefinitionBodyPaths() throws {
        let definition = HeistPlan(
            name: "submit",
            body: [try actionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Submit")))))]
        )
        let plan = HeistPlan(
            definitions: [definition],
            body: [.invoke(HeistInvocationStep(path: ["submit"]))]
        )
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .invoke,
                    durationMs: 5,
                    childResults: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 5
                        ),
                    ]
                ),
            ],
            totalTimingMs: 5
        )

        let node = HeistReportProjection(plan: plan, result: result).nodes[0]

        XCTAssertEqual(node.kind, .invoke)
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].invoke.body[0]"])
        XCTAssertEqual(node.children.first?.action?.commandName, "activate")
    }

    private func actionStep(
        command: HeistActionCommand = .activate(.target(.predicate(ElementPredicate(label: "Button")))),
        expectation: WaitStep? = nil
    ) throws -> HeistStep {
        .action(try ActionStep(command: command, expectation: expectation))
    }

    private func caseMatch(
        _ predicate: AccessibilityPredicate,
        met: Bool
    ) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicate,
            result: ExpectationResult(met: met, predicate: predicate)
        )
    }
}

final class HeistReportTreeProjectionTests: XCTestCase {

    func testSelectedStructuralChildrenStayInReportTree() throws {
        let elseStep = try actionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Fallback")))))
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Home")))
        let conditional = try ConditionalStep(
            cases: [PredicateCase(predicate: predicate, body: [try actionStep()])],
            elseBody: [elseStep]
        )
        let plan = HeistPlan(body: [.conditional(conditional)])
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .conditional,
                    durationMs: 3,
                    caseSelection: HeistCaseSelectionResult(
                        cases: [caseMatch(predicate, met: false)],
                        selectedCaseIndex: nil,
                        elapsedMs: 1,
                        elseRan: true
                    ),
                    childResults: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .activate),
                            durationMs: 2
                        ),
                    ]
                ),
            ],
            totalTimingMs: 3
        )

        let projection = HeistReportProjection(plan: plan, result: result)

        XCTAssertEqual(projection.nodes.first?.children.first?.path, "$.body[0].conditional.else_body[0]")
        XCTAssertEqual(projection.nodes.first?.kind, .conditional)
        XCTAssertEqual(projection.nodes.first?.children.first?.action?.commandName, "activate")
    }

    func testForEachBodyResultsStayNestedUnderLoopNode() throws {
        let forEach = try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [try actionStep(command: .typeText(text: .ref("item"), target: nil))]
        )
        let plan = HeistPlan(body: [.forEachString(forEach)])
        let result = HeistExecutionResult(steps: [
                HeistExecutionStepResult(
                    index: 0,
                    kind: .forEach,
                    message: "for_each_string stopped after 2 of 2 iteration(s): iteration 1 failed for value \"Eggs\"",
                    durationMs: 30,
                    stopsHeist: true,
                    forEachResult: HeistForEachResult(
                        matchedCount: 2,
                        limit: 2,
                        iterationCount: 2,
                        failureReason: "iteration 1 failed for value \"Eggs\""
                    ),
                    childResults: [
                        HeistExecutionStepResult(
                            index: 0,
                            kind: .action,
                            actionResult: ActionResult(success: true, method: .typeText),
                            durationMs: 5
                        ),
                        HeistExecutionStepResult(
                            index: 1,
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
            ],
            totalTimingMs: 30,
            failedIndex: 0
        )

        let projection = HeistReportProjection(plan: plan, result: result)

        let node = try XCTUnwrap(projection.nodes.first)
        XCTAssertEqual(node.kind, .forEachString)
        XCTAssertEqual(node.status, .failed)
        XCTAssertEqual(node.message, "for_each_string stopped after 2 of 2 iteration(s): iteration 1 failed for value \"Eggs\"")
        XCTAssertEqual(node.children.map(\.path), [
            "$.body[0].for_each_string.iterations[0]",
            "$.body[0].for_each_string.iterations[1]",
        ])
        XCTAssertEqual(node.children[1].children.first?.action?.commandName, "typeText")
    }

    private func actionStep(
        command: HeistActionCommand = .activate(.target(.predicate(ElementPredicate(label: "Button"))))
    ) throws -> HeistStep {
        .action(try ActionStep(command: command))
    }

    private func caseMatch(
        _ predicate: AccessibilityPredicate,
        met: Bool
    ) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicate,
            result: ExpectationResult(met: met, predicate: predicate)
        )
    }
}
