import XCTest
@testable import ButtonHeist
import TheScore

/// The heist execution tree is the report structure. These tests lock the
/// report facts derived directly from the canonical receipt tree.
final class HeistExecutionReportFactsTests: XCTestCase {

    func testActionWithExpectationReportsActionAndExpectation() {
        let expectationPredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    command: .activate(.target(.predicate(ElementPredicate(label: "Submit")))),
                    actionResult: ActionResult(success: true, method: .activate),
                    expectation: ExpectationResult(met: true, predicate: expectationPredicate)
                ),
            ],
            durationMs: 5
        )

        XCTAssertEqual(result.expectationsChecked, 1)
        XCTAssertEqual(result.expectationsMet, 1)
        XCTAssertEqual(result.steps.map(\.path), ["$.body[0]"])
        XCTAssertEqual(result.steps.first?.reportStepName, "action")
        XCTAssertEqual(result.steps.first?.reportCommandName, "activate")
        XCTAssertEqual(result.dispatchedActionResults.map(\.method), [.activate])
        XCTAssertEqual(result.reportedActionResults.map(\.method), [.activate])
        XCTAssertEqual(result.executedTopLevelStepCount, 1)
        XCTAssertEqual(result.executedNodeCount, 1)
        XCTAssertEqual(result.outputReceiptNodes.map(\.path), ["$.body[0]"])
    }

    func testReportFactsUseExecutionTreeInsteadOfPlanSiblingRematch() {
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    path: "$.body[9]",
                    command: .activate(.target(.predicate(ElementPredicate(label: "Delete")))),
                    actionResult: ActionResult(success: true, method: .activate)
                ),
            ],
            durationMs: 5
        )

        XCTAssertEqual(result.steps.map(\.path), ["$.body[9]"])
        XCTAssertEqual(result.steps.first?.reportStepName, "action")
        XCTAssertEqual(result.steps.first?.reportCommandName, "activate")
        XCTAssertEqual(result.steps.first?.reportTarget, .predicate(ElementPredicate(label: "Delete")))
    }

    func testAbortedResultContainsOnlyExecutedSteps() {
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    actionResult: ActionResult(
                        success: false,
                        method: .activate,
                        message: "Delete failed",
                        errorKind: .actionFailed
                    ),
                    failure: HeistFailureDetail(
                        category: .action,
                        contract: "action dispatch succeeds",
                        observed: "Delete failed"
                    )
                ),
            ],
            durationMs: 4,
            abortedAtPath: "$.body[0]"
        )

        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.executedTopLevelStepCount, 1)
        XCTAssertEqual(result.executedNodeCount, 1)
        XCTAssertEqual(result.abortedAtPath, "$.body[0]")
        XCTAssertEqual(result.outputReceiptNodes.count, 1)
        XCTAssertEqual(result.outputReceiptNodes.map(\.path), ["$.body[0]"])
        XCTAssertEqual(result.steps.map(\.reportStatus), [.failed])
        XCTAssertEqual(result.expectationsChecked, 0)
        XCTAssertEqual(result.expectationsMet, 0)
        XCTAssertEqual(result.steps.first?.reportActionResult?.message, "Delete failed")
    }

    func testWaitReportsWaitEvidenceWithoutDispatchedActionResult() {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let result = HeistExecutionResult(
            steps: [
                waitStep(
                    expectation: ExpectationResult(met: true, predicate: predicate)
                ),
            ],
            durationMs: 20
        )

        let node = result.steps[0]
        XCTAssertEqual(node.path, "$.body[0]")
        XCTAssertEqual(node.reportStepName, "wait")
        XCTAssertEqual(node.reportStatus, .passed)
        XCTAssertEqual(node.reportExpectation?.met, true)
        XCTAssertEqual(node.reportActionResult?.method, .wait)
        XCTAssertEqual(result.dispatchedActionResults, [])
        XCTAssertEqual(result.reportedActionResults, [])
    }

    func testActionAndWaitSurfaceBothTraceDeltas() {
        let actionTrace = AccessibilityTrace.projectingForTests(.elementsChanged(.init(elementCount: 5, edits: ElementEdits())))
        let waitTrace = AccessibilityTrace.projectingForTests(.elementsChanged(.init(elementCount: 3, edits: ElementEdits())))
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    command: .activate(.target(.predicate(ElementPredicate(label: "Submit")))),
                    actionResult: ActionResult(success: true, method: .activate, accessibilityTrace: actionTrace)
                ),
                waitStep(
                    path: "$.body[1]",
                    actionResult: ActionResult(success: true, method: .wait, accessibilityTrace: waitTrace)
                ),
            ],
            durationMs: 10
        )

        let traces = result.traceResultsInExecutionOrder
        XCTAssertEqual(traces.map(\.method), [.activate, .wait])
        XCTAssertNotNil(traces[0].accessibilityTrace)
        XCTAssertNotNil(traces[1].accessibilityTrace)
        XCTAssertEqual(result.dispatchedActionResults.map(\.method), [.activate])
    }

    func testResultFailureAndFirstFailedStepDeriveFromTree() {
        let childFailure = actionStep(
            path: "$.body[0].heist.body[0]",
            actionResult: ActionResult(
                success: false,
                method: .activate,
                message: "boom",
                errorKind: .actionFailed
            ),
            failure: HeistFailureDetail(
                category: .action,
                contract: "action dispatch succeeds",
                observed: "boom"
            )
        )
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .heist,
                    status: .failed,
                    durationMs: 5,
                    intent: .heist(name: "Wrapper"),
                    failure: HeistFailureDetail(
                        category: .invocation,
                        contract: "child execution completes without failure",
                        observed: "child failed at $.body[0].heist.body[0]"
                    ),
                    abortedAtChildPath: "$.body[0].heist.body[0]",
                    children: [childFailure]
                ),
            ],
            durationMs: 5,
            abortedAtPath: "$.body[0].heist.body[0]"
        )

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.firstFailedStep?.path, "$.body[0].heist.body[0]")
        XCTAssertEqual(result.failedStepPath, "$.body[0].heist.body[0]")
        XCTAssertEqual(result.failedStepKind, .action)
        XCTAssertEqual(result.steps.first?.abortedAtChildPath, "$.body[0].heist.body[0]")
        XCTAssertEqual(result.executedTopLevelStepCount, 1)
        XCTAssertEqual(result.executedNodeCount, 2)
        XCTAssertEqual(result.outputReceiptNodes.count, 2)
    }

    func testConditionalSelectedCaseKeepsOnlySelectedChildren() {
        let result = HeistExecutionResult(
            steps: [
                caseStep(
                    kind: .conditional,
                    selection: HeistCaseSelectionResult(cases: [], selectedCaseIndex: 0, elapsedMs: 1),
                    children: [
                        actionStep(
                            path: "$.body[0].conditional.cases[0].body[0]",
                            actionResult: ActionResult(success: true, method: .activate)
                        ),
                    ]
                ),
            ],
            durationMs: 8
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStepName, "if")
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].conditional.cases[0].body[0]"])
        XCTAssertEqual(node.children.first?.reportCommandName, "activate")
    }

    func testWaitForTimeoutWithoutElseReportsWaitFailure() {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let failure = HeistFailureDetail(
            category: .wait,
            contract: "wait predicate is met before timeout",
            observed: "timed out after 2s",
            expected: predicate.description
        )
        let result = HeistExecutionResult(
            steps: [
                waitStep(
                    actionResult: ActionResult(success: false, method: .wait, message: "timed out after 2s", errorKind: .timeout),
                    expectation: ExpectationResult(met: false, predicate: predicate, actual: "timed out after 2s"),
                    failure: failure
                ),
            ],
            durationMs: 2000,
            abortedAtPath: "$.body[0]"
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStepName, "wait")
        XCTAssertEqual(node.reportStatus, .failed)
        XCTAssertEqual(node.children.count, 0)
        XCTAssertEqual(node.waitEvidence?.expectation.met, false)
    }

    func testWaitForTimeoutWithElseReportsElseChildrenAsHandled() {
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let expectation = ExpectationResult(met: false, predicate: predicate, actual: "timed out after 2s")
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .wait,
                    status: .passed,
                    durationMs: 2000,
                    intent: .wait(predicate: predicate.description, timeout: 2),
                    evidence: .wait(HeistWaitEvidence(
                        actionResult: ActionResult(success: false, method: .wait, message: "timed out after 2s", errorKind: .timeout),
                        expectation: expectation
                    )),
                    children: [
                        warnStep(path: "$.body[0].wait.else_body[0]", message: "No result"),
                    ]
                ),
            ],
            durationMs: 2000
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStatus, .passed)
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].wait.else_body[0]"])
        XCTAssertEqual(node.children.first?.reportStatus, .passed)
        XCTAssertEqual(result.warnings.map(\.path), ["$.body[0].wait.else_body[0]"])
    }

    func testForEachBodyFailureReportsIterationFailureInStructuredNodes() {
        let result = forEachStringFailureResult()
        let node = result.steps[0]

        XCTAssertEqual(result.abortedAtPath, "$.body[0].for_each_string.iterations[1].body[0]")
        XCTAssertEqual(node.reportStatus, .failed)
        XCTAssertEqual(node.abortedAtChildPath, "$.body[0].for_each_string.iterations[1].body[0]")
        XCTAssertEqual(node.children.map(\.reportStatus), [.passed, .failed])
        XCTAssertEqual(node.children[1].abortedAtChildPath, "$.body[0].for_each_string.iterations[1].body[0]")
        XCTAssertEqual(node.children[1].children.first?.reportActionResult?.message, "field missing")
        XCTAssertEqual(node.forEachStringEvidence?.failureReason, "iteration 1 failed for value \"Eggs\"")
        XCTAssertEqual(result.executedTopLevelStepCount, 1)
        XCTAssertEqual(result.executedNodeCount, 5)
        XCTAssertEqual(result.outputReceiptNodes.count, 5)
    }

    func testForEachMultipleIterationsSurfacesReceiptTreeInOutputOrder() {
        let result = forEachStringSuccessResult()
        let node = result.steps[0]

        XCTAssertEqual(node.reportStatus, .passed)
        XCTAssertEqual(node.children.map(\.reportStatus), [.passed, .passed])
        XCTAssertEqual(result.executedTopLevelStepCount, 1)
        XCTAssertEqual(result.executedNodeCount, 5)
        XCTAssertEqual(result.outputReceiptNodes.map(\.path), [
            "$.body[0]",
            "$.body[0].for_each_string.iterations[0]",
            "$.body[0].for_each_string.iterations[0].body[0]",
            "$.body[0].for_each_string.iterations[1]",
            "$.body[0].for_each_string.iterations[1].body[0]",
        ])
    }

    func testWarnAndFailAreExecutedNodes() {
        let result = HeistExecutionResult(
            steps: [
                warnStep(message: "Heads up"),
                HeistExecutionStepResult(
                    path: "$.body[1]",
                    kind: .fail,
                    status: .failed,
                    durationMs: 1,
                    intent: .fail(message: "Stop here"),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "explicit heist failure",
                        observed: "Stop here"
                    )
                ),
            ],
            durationMs: 2,
            abortedAtPath: "$.body[1]"
        )

        XCTAssertEqual(result.steps.map(\.reportStepName), ["warn", "fail"])
        XCTAssertEqual(result.steps.map(\.reportStatus), [.passed, .failed])
        XCTAssertEqual(result.warnings.map(\.message), ["Heads up"])
        XCTAssertEqual(result.executedTopLevelStepCount, 2)
        XCTAssertEqual(result.executedNodeCount, 2)
        XCTAssertEqual(result.outputReceiptNodes.count, 2)
    }

    func testInvokeNodeCarriesCapabilityFrameAndArgument() {
        let invocation = HeistInvocationStep(
            path: ["LibraryScreen", "addToCart"],
            argument: .string(.literal("Milk"))
        )
        let child = actionStep(
            path: "$.body[0].invoke.body[0]",
            actionResult: ActionResult(
                success: false,
                method: .activate,
                message: "Add to Cart not found",
                errorKind: .actionFailed
            ),
            failure: HeistFailureDetail(
                category: .action,
                contract: "action dispatch succeeds",
                observed: "Add to Cart not found"
            )
        )
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .invoke,
                    status: .failed,
                    durationMs: 5,
                    intent: .invoke(path: "LibraryScreen.addToCart", argument: "Milk"),
                    evidence: .invocation(HeistInvocationEvidence(
                        invocation: invocation,
                        name: "LibraryScreen.addToCart",
                        argument: "Milk",
                        childFailedPath: child.path
                    )),
                    failure: HeistFailureDetail(
                        category: .invocation,
                        contract: "child execution completes without failure",
                        observed: "child failed at \(child.path)"
                    ),
                    abortedAtChildPath: child.path,
                    children: [child]
                ),
            ],
            durationMs: 5,
            abortedAtPath: child.path
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportStepName, "invoke")
        XCTAssertEqual(node.invocationEvidence?.invocation?.capabilityName, "LibraryScreen.addToCart")
        XCTAssertEqual(node.reportDisplayName, "RunHeist(\"LibraryScreen.addToCart\", \"Milk\")")
        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(node.reportStatus, .failed)
        XCTAssertEqual(result.failedStepPath, child.path)
        XCTAssertEqual(result.failedStepKind, .action)
    }

    func testJUnitUsesOutputReceiptNodes() async {
        let result = forEachStringSuccessResult()
        let rows = await Task { @ButtonHeistActor in
            TheFence(configuration: .init()).junitSteps(result: result)
        }.value

        XCTAssertEqual(result.executedTopLevelStepCount, 1)
        XCTAssertEqual(result.executedNodeCount, 5)
        XCTAssertEqual(rows.count, result.outputReceiptNodes.count)
        XCTAssertEqual(rows.map(\.command), [
            "for_each_string",
            "for_each_iteration",
            "typeText",
            "for_each_iteration",
            "typeText",
        ])
    }

    func testSkippedReceiptNodesDoNotContributeRuntimeEvidence() {
        let result = HeistExecutionResult(
            steps: [
                warnStep(message: "before"),
                HeistExecutionStepResult(
                    path: "$.body[1]",
                    kind: .fail,
                    status: .failed,
                    durationMs: 1,
                    intent: .fail(message: "stop"),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "explicit heist failure",
                        observed: "stop"
                    )
                ),
                HeistExecutionStepResult(
                    path: "$.body[2]",
                    kind: .action,
                    status: .skipped,
                    durationMs: 0
                ),
            ],
            durationMs: 2,
            abortedAtPath: "$.body[1]"
        )

        let skipped = result.steps[2]
        XCTAssertEqual(result.failedStepPath, "$.body[1]")
        XCTAssertEqual(result.failedStepKind, .fail)
        XCTAssertEqual(result.executedTopLevelStepCount, 2)
        XCTAssertEqual(result.executedNodeCount, 2)
        XCTAssertEqual(result.outputReceiptNodes.map(\.status), [.passed, .failed, .skipped])
        XCTAssertNil(skipped.intent)
        XCTAssertNil(skipped.evidence)
        XCTAssertNil(skipped.failure)
        XCTAssertNil(skipped.reportActionResult)
        XCTAssertNil(skipped.reportExpectation)
    }

    // MARK: - Fixtures

    private func actionStep(
        path: String = "$.body[0]",
        command: HeistActionCommand? = .activate(.target(.predicate(ElementPredicate(label: "Button")))),
        actionResult: ActionResult,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .action,
            status: failure == nil ? .passed : .failed,
            durationMs: 5,
            intent: command.map {
                .action(command: $0.wireType.rawValue, target: $0.reportTarget.map(String.init(describing:)))
            },
            evidence: .action(HeistActionEvidence(
                command: command,
                actionResult: actionResult,
                expectationActionResult: expectationActionResult,
                expectation: expectation
            )),
            failure: failure
        )
    }

    private func waitStep(
        path: String = "$.body[0]",
        actionResult: ActionResult = ActionResult(success: true, method: .wait),
        expectation: ExpectationResult = ExpectationResult(
            met: true,
            predicate: .state(.present(ElementPredicate(label: "Done")))
        ),
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .wait,
            status: failure == nil ? .passed : .failed,
            durationMs: 20,
            intent: .wait(predicate: expectation.predicate?.description ?? "predicate", timeout: 0),
            evidence: .wait(HeistWaitEvidence(actionResult: actionResult, expectation: expectation)),
            failure: failure
        )
    }

    private func caseStep(
        kind: HeistExecutionStepKind,
        status: HeistExecutionStepStatus = .passed,
        selection: HeistCaseSelectionResult,
        failure: HeistFailureDetail? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: "$.body[0]",
            kind: kind,
            status: status,
            durationMs: selection.elapsedMs,
            intent: .conditional,
            evidence: .caseSelection(HeistCaseSelectionEvidence(selection: selection)),
            failure: failure,
            abortedAtChildPath: children.firstFailedStep?.path,
            children: children
        )
    }

    private func warnStep(path: String = "$.body[0]", message: String) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .warn,
            status: .passed,
            durationMs: 1,
            intent: .warn(message: message),
            evidence: .warning(HeistExecutionWarning(path: path, message: message))
        )
    }

    private func forEachStringFailureResult() -> HeistExecutionResult {
        let failedActionPath = "$.body[0].for_each_string.iterations[1].body[0]"
        let firstIteration = HeistExecutionStepResult(
            path: "$.body[0].for_each_string.iterations[0]",
            kind: .forEachIteration,
            status: .passed,
            durationMs: 5,
            intent: .forEachString(parameter: "item", count: 2),
            evidence: .forEachString(HeistForEachStringEvidence(
                parameter: "item",
                count: 2,
                iterationCount: 1,
                iterationOrdinal: 0,
                value: "Milk"
            )),
            children: [
                actionStep(
                    path: "$.body[0].for_each_string.iterations[0].body[0]",
                    command: .typeText(text: .literal("Milk"), target: nil),
                    actionResult: ActionResult(success: true, method: .typeText)
                ),
            ]
        )
        let secondIteration = HeistExecutionStepResult(
            path: "$.body[0].for_each_string.iterations[1]",
            kind: .forEachIteration,
            status: .failed,
            durationMs: 6,
            intent: .forEachString(parameter: "item", count: 2),
            evidence: .forEachString(HeistForEachStringEvidence(
                parameter: "item",
                count: 2,
                iterationCount: 2,
                iterationOrdinal: 1,
                value: "Eggs",
                failureReason: "child failed at \(failedActionPath)"
            )),
            failure: HeistFailureDetail(
                category: .loop,
                contract: "child execution completes without failure",
                observed: "child failed at \(failedActionPath)"
            ),
            abortedAtChildPath: failedActionPath,
            children: [
                actionStep(
                    path: failedActionPath,
                    command: .typeText(text: .literal("Eggs"), target: nil),
                    actionResult: ActionResult(
                        success: false,
                        method: .typeText,
                        message: "field missing",
                        errorKind: .elementNotFound
                    ),
                    failure: HeistFailureDetail(
                        category: .targetResolution,
                        contract: "action dispatch succeeds",
                        observed: "field missing"
                    )
                ),
            ]
        )
        return HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .forEachString,
                    status: .failed,
                    durationMs: 30,
                    intent: .forEachString(parameter: "item", count: 2),
                    evidence: .forEachString(HeistForEachStringEvidence(
                        parameter: "item",
                        count: 2,
                        iterationCount: 2,
                        failureReason: "iteration 1 failed for value \"Eggs\""
                    )),
                    failure: HeistFailureDetail(
                        category: .loop,
                        contract: "for_each_string completes all values",
                        observed: "iteration 1 failed for value \"Eggs\"",
                        expected: "2 value(s)"
                    ),
                    abortedAtChildPath: failedActionPath,
                    children: [firstIteration, secondIteration]
                ),
            ],
            durationMs: 30,
            abortedAtPath: failedActionPath
        )
    }

    private func forEachStringSuccessResult() -> HeistExecutionResult {
        let firstIteration = forEachStringIterationStep(
            ordinal: 0,
            value: "Milk",
            actionPath: "$.body[0].for_each_string.iterations[0].body[0]"
        )
        let secondIteration = forEachStringIterationStep(
            ordinal: 1,
            value: "Eggs",
            actionPath: "$.body[0].for_each_string.iterations[1].body[0]"
        )
        return HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .forEachString,
                    status: .passed,
                    durationMs: 30,
                    intent: .forEachString(parameter: "item", count: 2),
                    evidence: .forEachString(HeistForEachStringEvidence(
                        parameter: "item",
                        count: 2,
                        iterationCount: 2
                    )),
                    children: [firstIteration, secondIteration]
                ),
            ],
            durationMs: 30
        )
    }

    private func forEachStringIterationStep(
        ordinal: Int,
        value: String,
        actionPath: String
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: "$.body[0].for_each_string.iterations[\(ordinal)]",
            kind: .forEachIteration,
            status: .passed,
            durationMs: 5,
            intent: .forEachString(parameter: "item", count: 2),
            evidence: .forEachString(HeistForEachStringEvidence(
                parameter: "item",
                count: 2,
                iterationCount: ordinal + 1,
                iterationOrdinal: ordinal,
                value: value
            )),
            children: [
                actionStep(
                    path: actionPath,
                    command: .typeText(text: .literal(value), target: nil),
                    actionResult: ActionResult(success: true, method: .typeText)
                ),
            ]
        )
    }

    private func caseMatch(_ predicate: AccessibilityPredicate, met: Bool) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicate,
            result: ExpectationResult(met: met, predicate: predicate)
        )
    }
}
