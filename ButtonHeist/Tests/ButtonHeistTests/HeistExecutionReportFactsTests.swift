import Foundation
import XCTest
import ThePlans
@_spi(ButtonHeistInternals) @testable import ButtonHeist
import TheScore

/// The heist execution tree is the report structure. These tests lock the
/// report facts derived directly from the canonical receipt tree.
final class HeistExecutionReportFactsTests: XCTestCase {

    func testActionWithExpectationReportsActionAndExpectation() {
        let expectationPredicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
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

    func testReportFactsCarryStepStoryForProjectionAdapters() {
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    command: .activate(.target(.predicate(ElementPredicate(label: "Delete")))),
                    actionResult: ActionResult(
                        success: false,
                        method: .activate,
                        message: "Delete not found",
                        errorKind: .elementNotFound
                    ),
                    failure: HeistFailureDetail(
                        category: .targetResolution,
                        contract: "action dispatch succeeds",
                        observed: "Delete not found"
                    )
                ),
            ],
            durationMs: 5,
            abortedAtPath: "$.body[0]"
        )

        let summary = HeistExecutionReportSummaryFacts(result: result)
        let report = result.steps[0].reportFacts

        XCTAssertEqual(summary.executedTopLevelStepCount, 1)
        XCTAssertEqual(summary.executedNodeCount, 1)
        XCTAssertEqual(summary.outputReceiptNodeCount, 1)
        XCTAssertEqual(summary.abortedAtPath, "$.body[0]")
        XCTAssertEqual(report.path, "$.body[0]")
        XCTAssertEqual(report.kind, "action")
        XCTAssertEqual(report.displayName, "activate")
        XCTAssertEqual(report.commandName, "activate")
        XCTAssertEqual(report.target, .predicate(ElementPredicate(label: "Delete")))
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.message, "Delete not found")
        XCTAssertEqual(report.failureMessage, "Delete not found")
        XCTAssertEqual(report.failureCategory, .targetResolution)
        XCTAssertEqual(report.actionErrorKind, .elementNotFound)
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
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
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

    func testReportFailureFactsDeriveFromTypedOutcome() {
        let predicate = AccessibilityPredicate.change(.screen())
        let failure = HeistFailureDetail(
            category: .expectation,
            contract: "action expectation is met",
            observed: "screen did not change",
            expected: predicate.description
        )
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .action,
                    status: .failed,
                    durationMs: 5,
                    intent: .action(command: "activate", target: "label=Pay"),
                    evidence: .action(HeistActionEvidence(
                        command: .activate(.target(.predicate(ElementPredicate(label: "Pay")))),
                        actionResult: ActionResult(success: true, method: .activate),
                        expectation: ExpectationResult(
                            met: false,
                            predicate: predicate,
                            actual: "screen did not change"
                        )
                    )),
                    failure: failure
                ),
            ],
            durationMs: 5,
            abortedAtPath: "$.body[0]"
        )

        let node = result.steps[0]
        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.failedStepPath, "$.body[0]")
        XCTAssertEqual(node.reportStatus, .failed)
        XCTAssertEqual(node.reportMessage, "screen did not change")
        XCTAssertEqual(node.reportFailureMessage, "screen did not change")
        XCTAssertEqual(node.reportActionResult?.success, true)
        guard case .failed(let outcome) = node.outcome else {
            return XCTFail("Expected failed typed outcome")
        }
        XCTAssertEqual(outcome.failure, failure)
    }

    func testConditionalSelectedCaseKeepsOnlySelectedChildren() {
        let result = HeistExecutionResult(
            steps: [
                caseStep(
                    kind: .conditional,
                    selection: HeistCaseSelectionResult(
                        cases: [
                            HeistCaseMatchResult(
                                predicate: .state(.exists(ElementPredicate(label: "Selected"))),
                                result: ExpectationResult(
                                    met: true,
                                    predicate: .state(.exists(ElementPredicate(label: "Selected")))
                                )
                            ),
                        ],
                        outcome: .matchedCase(index: 0),
                        elapsedMs: 1
                    ),
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
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
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
        let predicate = AccessibilityPredicate.state(.exists(ElementPredicate(label: "Done")))
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
                        outcome: .handledElse,
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

    func testJUnitActionFailureDerivesFromReceiptFacts() async {
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    command: .activate(.target(.predicate(ElementPredicate(label: "Delete")))),
                    actionResult: ActionResult(
                        success: false,
                        method: .activate,
                        message: "Delete not found",
                        errorKind: .elementNotFound
                    ),
                    failure: HeistFailureDetail(
                        category: .targetResolution,
                        contract: "activate command succeeds",
                        observed: "Delete not found"
                    )
                ),
            ],
            durationMs: 2,
            abortedAtPath: "$.body[0]"
        )
        let rows = await Task { @ButtonHeistActor in
            TheFence(configuration: .init()).junitSteps(result: result)
        }.value

        guard case .failed(let message, let errorKind) = rows.first?.outcome else {
            return XCTFail("Expected failed JUnit row, got \(String(describing: rows.first?.outcome))")
        }
        XCTAssertTrue(message.hasPrefix("Delete not found"), message)
        XCTAssertTrue(message.contains("code: request.element_not_found"), message)
        XCTAssertTrue(message.contains("kind: request"), message)
        XCTAssertTrue(message.contains("phase: request"), message)
        XCTAssertTrue(message.contains("retryable: false"), message)
        XCTAssertEqual(errorKind, .action(.elementNotFound))
    }

    func testJUnitExpectationFailureUsesExpectationReceiptFact() async {
        let predicate = AccessibilityPredicate.change(.screen())
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .action,
                    status: .failed,
                    durationMs: 5,
                    intent: .action(command: "activate", target: "label=Pay"),
                    evidence: .action(HeistActionEvidence(
                        command: .activate(.target(.predicate(ElementPredicate(label: "Pay")))),
                        actionResult: ActionResult(success: true, method: .activate),
                        expectation: ExpectationResult(
                            met: false,
                            predicate: predicate,
                            actual: "elementsChanged"
                        )
                    ))
                ),
            ],
            durationMs: 5,
            abortedAtPath: "$.body[0]"
        )
        let rows = await Task { @ButtonHeistActor in
            TheFence(configuration: .init()).junitSteps(result: result)
        }.value

        guard case .failed(let message, let errorKind) = rows.first?.outcome else {
            return XCTFail("Expected failed JUnit row, got \(String(describing: rows.first?.outcome))")
        }
        XCTAssertTrue(message.hasPrefix("elementsChanged"), message)
        XCTAssertTrue(message.contains("code: request.action_failed"), message)
        XCTAssertTrue(message.contains("kind: request"), message)
        XCTAssertTrue(message.contains("phase: request"), message)
        XCTAssertTrue(message.contains("retryable: false"), message)
        XCTAssertNil(errorKind)
    }

    func testJUnitFailureIncludesFailureScreenshotInterfaceDump() async {
        let elements = (0..<21).map { index in
            makeReceiptTestElement(
                label: index == 0 ? "No results found" : "Element \(index)",
                identifier: index == 0 ? "empty_state" : nil
            )
        }
        let interface = makeReceiptTestInterface(elements)
        let screenshot = ScreenPayload(
            pngData: "png",
            width: 42,
            height: 24,
            timestamp: Date(timeIntervalSince1970: 0),
            interface: interface
        )
        let result = HeistExecutionResult(
            steps: [
                HeistExecutionStepResult(
                    path: "$.body[0]",
                    kind: .fail,
                    status: .failed,
                    durationMs: 1,
                    intent: .fail(message: "stop"),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "Fail(...) aborts the heist",
                        observed: "stop"
                    )
                ),
                HeistExecutionStepResult(
                    path: "$.body[0].failure.actions[0]",
                    kind: .action,
                    status: .passed,
                    durationMs: 1,
                    intent: .action(command: "takeScreenshot", target: nil),
                    evidence: .action(HeistActionEvidence(
                        command: .takeScreenshot,
                        actionResult: ActionResult(
                            success: true,
                            method: .takeScreenshot,
                            payload: .screenshot(screenshot)
                        )
                    ))
                ),
            ],
            durationMs: 2,
            abortedAtPath: "$.body[0]"
        )
        let rows = await Task { @ButtonHeistActor in
            TheFence(configuration: .init()).junitSteps(result: result)
        }.value

        guard case .failed(let message, let errorKind) = rows.first?.outcome else {
            return XCTFail("Expected failed JUnit row, got \(String(describing: rows.first?.outcome))")
        }
        XCTAssertEqual(errorKind, .commandError)
        XCTAssertTrue(message.contains("stop"), message)
        XCTAssertTrue(
            message.contains("failure screenshot: 42x24 receipt=$.body[0].failure.actions[0] interface=21 elements"),
            message
        )
        XCTAssertTrue(message.contains("failure interface: 21 elements"), message)
        XCTAssertTrue(message.contains("[0] \"No results found\" staticText id=\"empty_state\""), message)
        XCTAssertTrue(message.contains("frame=(0,0,100,44) activation=(50,22)"), message)
        XCTAssertTrue(message.contains("... and 1 more"), message)
        XCTAssertEqual(result.failureScreenshotPayload, screenshot)
        XCTAssertEqual(result.failureDiagnosticInterface?.projectedElements.count, 21)
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

    func testPublicHeistEvidenceProjectionEncodesExactlyOneVariantPerEvidenceCase() throws {
        let plan = try evidenceProjectionPlan()
        for testCase in evidenceProjectionCases() {
            let projection = HeistReportNodeProjection(step: testCase.step, profile: .mcp)
            XCTAssertEqual(projectedEvidenceKey(projection.evidence), testCase.expectedKey, testCase.name)

            let response = FenceResponse.heistExecution(
                plan: plan,
                result: HeistExecutionResult(steps: [testCase.step], durationMs: testCase.step.durationMs)
            )
            let report = try publicHeistReportResponseDTO(response).report
            let node = try XCTUnwrap(report.nodes.first, testCase.name)
            let evidence = try XCTUnwrap(node.evidence, testCase.name)

            XCTAssertEqual(evidence.encodedVariantKeys, Set([testCase.expectedKey]), testCase.name)
            try testCase.assertEvidence(evidence)
        }
    }

    // MARK: - Fixtures

    private typealias EvidenceProjectionCase = (
        name: String,
        step: HeistExecutionStepResult,
        expectedKey: String,
        assertEvidence: (PublicHeistReportEvidenceDTO) throws -> Void
    )

    private func evidenceProjectionCases() -> [EvidenceProjectionCase] {
        [
            actionEvidenceProjectionCase(),
            waitEvidenceProjectionCase(),
            caseSelectionEvidenceProjectionCase(),
            forEachStringEvidenceProjectionCase(),
            forEachElementEvidenceProjectionCase(),
            repeatUntilEvidenceProjectionCase(),
            heistInvocationEvidenceProjectionCase(),
            invokeInvocationEvidenceProjectionCase(),
            warningEvidenceProjectionCase(),
        ]
    }

    private func evidenceProjectionPlan() throws -> HeistPlan {
        try HeistPlan(body: [
            try HeistStep.action(ActionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Button")))))),
        ])
    }

    private func evidenceProjectionPredicate() -> AccessibilityPredicate {
        .state(.exists(ElementPredicate(label: "Ready")))
    }

    private func actionEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "action",
            step: actionStep(
                command: .activate(.target(.predicate(ElementPredicate(label: "Button")))),
                actionResult: ActionResult(success: true, method: .activate)
            ),
            expectedKey: "action",
            assertEvidence: { evidence in
                let action = try XCTUnwrap(evidence.action)
                XCTAssertEqual(action.commandName, "activate")
                XCTAssertNotNil(action.result)
            }
        )
    }

    private func waitEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "wait",
            step: waitStep(
                actionResult: ActionResult(success: true, method: .wait),
                expectation: ExpectationResult(met: true, predicate: evidenceProjectionPredicate()),
                warning: HeistPredicateWarning(
                    code: "transition_not_observed_final_state_satisfied",
                    predicate: ".disappeared(.label(\"Loading\"))",
                    message: "Loading was already absent when the wait began"
                )
            ),
            expectedKey: "wait",
            assertEvidence: { evidence in
                let wait = try XCTUnwrap(evidence.wait)
                XCTAssertEqual(wait.result.method, "wait")
                XCTAssertEqual(wait.expectation.met, true)
                XCTAssertEqual(wait.warning?.code, "transition_not_observed_final_state_satisfied")
            }
        )
    }

    private func caseSelectionEvidenceProjectionCase() -> EvidenceProjectionCase {
        let predicate = evidenceProjectionPredicate()
        return (
            name: "caseSelection",
            step: caseStep(
                kind: .conditional,
                selection: HeistCaseSelectionResult(
                    cases: [caseMatch(predicate, met: true)],
                    outcome: .matchedCase(index: 0),
                    elapsedMs: 3
                )
            ),
            expectedKey: "caseSelection",
            assertEvidence: { evidence in
                let caseSelection = try XCTUnwrap(evidence.caseSelection)
                XCTAssertEqual(caseSelection.caseCount, 1)
                let cases = try XCTUnwrap(caseSelection.cases)
                XCTAssertEqual(cases.count, 1)
            }
        )
    }

    private func forEachStringEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "forEachString",
            step: HeistExecutionStepResult(
                path: "$.body[0]",
                kind: .forEachString,
                status: .passed,
                durationMs: 4,
                intent: .forEachString(parameter: "item", count: 2),
                evidence: .forEachString(HeistForEachStringEvidence(
                    parameter: "item",
                    count: 2,
                    iterationCount: 1,
                    value: "Milk"
                ))
            ),
            expectedKey: "forEachString",
            assertEvidence: { evidence in
                let forEachString = try XCTUnwrap(evidence.forEachString)
                XCTAssertEqual(forEachString.parameter, "item")
                XCTAssertEqual(forEachString.value, "Milk")
            }
        )
    }

    private func forEachElementEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "forEachElement",
            step: HeistExecutionStepResult(
                path: "$.body[0]",
                kind: .forEachElement,
                status: .passed,
                durationMs: 5,
                intent: .forEachElement(parameter: "row", matching: "label=Row", limit: 3),
                evidence: .forEachElement(HeistForEachElementEvidence(
                    parameter: "row",
                    matching: ElementPredicate(label: "Row"),
                    limit: 3,
                    matchedCount: 2,
                    iterationCount: 2,
                    targetOrdinal: 1,
                    targetSummary: "\"Row\" staticText"
                ))
            ),
            expectedKey: "forEachElement",
            assertEvidence: { evidence in
                let forEachElement = try XCTUnwrap(evidence.forEachElement)
                XCTAssertEqual(forEachElement.parameter, "row")
                XCTAssertEqual(forEachElement.matchedCount, 2)
                XCTAssertEqual(forEachElement.targetSummary, "\"Row\" staticText")
            }
        )
    }

    private func repeatUntilEvidenceProjectionCase() -> EvidenceProjectionCase {
        let predicate = evidenceProjectionPredicate()
        return (
            name: "repeatUntil",
            step: HeistExecutionStepResult(
                path: "$.body[0]",
                kind: .repeatUntil,
                status: .passed,
                durationMs: 6,
                intent: .repeatUntil(predicate: predicate.description, timeout: 2),
                evidence: .repeatUntil(HeistRepeatUntilEvidence(
                    outcome: .matched,
                    predicate: predicate,
                    timeout: 2,
                    iterationCount: 1,
                    expectation: ExpectationResult(met: true, predicate: predicate),
                    actionResult: ActionResult(success: true, method: .wait),
                    lastObservedSummary: "Ready"
                ))
            ),
            expectedKey: "repeatUntil",
            assertEvidence: { evidence in
                let repeatUntil = try XCTUnwrap(evidence.repeatUntil)
                XCTAssertEqual(repeatUntil.timeout, 2.0)
                XCTAssertEqual(repeatUntil.iterationCount, 1)
                XCTAssertEqual(repeatUntil.lastObservedSummary, "Ready")
            }
        )
    }

    private func heistInvocationEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "heistInvocation",
            step: HeistExecutionStepResult(
                path: "$.body[0]",
                kind: .heist,
                status: .passed,
                durationMs: 7,
                intent: .heist(name: "Nested"),
                evidence: .invocation(HeistInvocationEvidence(name: "Nested"))
            ),
            expectedKey: "invocation",
            assertEvidence: { evidence in
                let invocation = try XCTUnwrap(evidence.invocation)
                XCTAssertEqual(invocation.name, "Nested")
            }
        )
    }

    private func invokeInvocationEvidenceProjectionCase() -> EvidenceProjectionCase {
        let invocation = HeistInvocationStep(
            path: ["LibraryScreen", "addToCart"],
            argument: .string(.literal("Milk"))
        )
        let predicate = evidenceProjectionPredicate()
        let expectation = ExpectationResult(met: true, predicate: predicate, actual: "Ready")
        return (
            name: "invokeInvocation",
            step: HeistExecutionStepResult(
                path: "$.body[0]",
                kind: .invoke,
                status: .passed,
                durationMs: 8,
                intent: .invoke(path: "LibraryScreen.addToCart", argument: "Milk"),
                evidence: .invocation(HeistInvocationEvidence(
                    invocation: invocation,
                    name: "LibraryScreen.addToCart",
                    argument: "Milk",
                    expectationActionResult: ActionResult(success: true, method: .wait),
                    expectation: expectation,
                    expectationEvidence: HeistWaitEvidence(
                        outcome: .matched,
                        actionResult: ActionResult(success: true, method: .wait),
                        expectation: expectation,
                        baselineSummary: "before addToCart",
                        finalSummary: "Ready"
                    )
                ))
            ),
            expectedKey: "invocation",
            assertEvidence: { evidence in
                let invocation = try XCTUnwrap(evidence.invocation)
                XCTAssertEqual(invocation.capability, "LibraryScreen.addToCart")
                XCTAssertEqual(invocation.argument, "Milk")
                XCTAssertEqual(invocation.expectationEvidence?.outcome, "matched")
                XCTAssertEqual(invocation.expectationEvidence?.result.method, "wait")
                XCTAssertEqual(invocation.expectationEvidence?.baselineSummary, "before addToCart")
                XCTAssertEqual(invocation.expectationEvidence?.finalSummary, "Ready")
            }
        )
    }

    private func warningEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "warning",
            step: warnStep(message: "Heads up"),
            expectedKey: "warning",
            assertEvidence: { evidence in
                let warning = try XCTUnwrap(evidence.warning)
                XCTAssertEqual(warning.path, "$.body[0]")
                XCTAssertEqual(warning.message, "Heads up")
            }
        )
    }

    private func projectedEvidenceKey(_ evidence: HeistReportEvidenceProjection?) -> String? {
        guard let evidence else { return nil }
        switch evidence {
        case .action:
            return "action"
        case .wait:
            return "wait"
        case .caseSelection:
            return "caseSelection"
        case .forEachString:
            return "forEachString"
        case .forEachElement:
            return "forEachElement"
        case .repeatUntil:
            return "repeatUntil"
        case .invocation:
            return "invocation"
        case .warning:
            return "warning"
        }
    }

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
            predicate: .state(.exists(ElementPredicate(label: "Done")))
        ),
        warning: HeistPredicateWarning? = nil,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .wait,
            status: failure == nil ? .passed : .failed,
            durationMs: 20,
            intent: .wait(predicate: expectation.predicate?.description ?? "predicate", timeout: 0),
            evidence: .wait(HeistWaitEvidence(
                outcome: failure == nil ? .matched : .failed,
                actionResult: actionResult,
                expectation: expectation,
                warning: warning
            )),
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
