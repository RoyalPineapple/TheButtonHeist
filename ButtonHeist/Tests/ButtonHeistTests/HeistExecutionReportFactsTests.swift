import ButtonHeistTestSupport
import Foundation
import XCTest
import ThePlans
@_spi(ButtonHeistInternals) @testable import ButtonHeist
import TheScore

/// The heist execution tree is the report structure. These tests lock the
/// report facts derived directly from the canonical receipt tree.
final class HeistExecutionReportFactsTests: XCTestCase {

    func testActionWithExpectationReportsActionAndExpectation() {
        let expectationPredicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Submit"))),
                    actionResult: ActionResult.success(method: .activate, evidence: .none),
                    expectationActionResult: ActionResult.success(method: .wait, evidence: .none),
                    expectation: ExpectationResult(met: true, predicate: expectationPredicate)
                ),
            ],
            durationMs: 5
        )

        XCTAssertEqual(result.expectationsChecked, 1)
        XCTAssertEqual(result.expectationsMet, 1)
        XCTAssertEqual(result.steps.map(\.path), ["$.body[0]"])
        XCTAssertEqual(result.steps.first?.reportFacts.kind, .action)
        XCTAssertEqual(result.steps.first?.reportFacts.command, .activate)
        XCTAssertEqual(result.dispatchedActionResults.map(\.method), [.activate])
        XCTAssertEqual(result.reportedActionResults.map(\.method), [.wait])
        XCTAssertEqual(result.executedTopLevelStepCount, 1)
        XCTAssertEqual(result.executedNodeCount, 1)
        XCTAssertEqual(result.outputReceiptNodes.map(\.path), ["$.body[0]"])
    }

    func testEvidenceRollupUsesOneOrderedNodeShapeForSummaryAndActions() {
        let actionWarning = HeistActionWarning.activationWeakAffordance(
            evidence: #"label="Checkout" traits=[staticText] actions=[activate]"#
        )
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    path: "$.body[0]",
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Checkout"))),
                    actionResult: ActionResult.success(
                        method: .activate,
                        evidence: ActionResultSuccessEvidence(
                            observation: .none,
                            warning: actionWarning
                        )
                    )
                ),
                waitStep(
                    path: "$.body[1]",
                    actionResult: ActionResult.success(method: .wait, evidence: .none),
                    expectation: ExpectationResult(
                        met: true,
                        predicate: .exists(.label("Ready"))
                    )
                ),
                warnStep(path: "$.body[2]", message: "explicit warning"),
            ],
            durationMs: 42
        )

        let rollup = result.evidenceRollup

        XCTAssertEqual(rollup.events.map(eventDescription), [
            "visit:$.body[0]",
            "dispatch:$.body[0]:activate",
            "report:$.body[0]:activate",
            "trace:$.body[0]:activate",
            "visit:$.body[1]",
            "trace:$.body[1]:wait",
            "expectationChecked:$.body[1]:true",
            "expectationMet:$.body[1]",
            "visit:$.body[2]",
        ])
        XCTAssertEqual(rollup.outputReceiptNodes.map(\.path), ["$.body[0]", "$.body[1]", "$.body[2]"])
        XCTAssertEqual(rollup.summary.executedTopLevelStepCount, 3)
        XCTAssertEqual(rollup.summary.executedNodeCount, 3)
        XCTAssertEqual(rollup.summary.expectationsChecked, 1)
        XCTAssertEqual(rollup.summary.expectationsMet, 1)
        XCTAssertEqual(rollup.actions.dispatchedResults.map(\.method), [.activate])
        XCTAssertEqual(rollup.actions.traceResultsInExecutionOrder.map(\.method), [.activate, .wait])
        XCTAssertEqual(rollup.actions.dispatchedResults.first?.warning, actionWarning)
        XCTAssertEqual(rollup.warnings, [
            HeistExecutionWarning(path: "$.body[2]", message: "explicit warning"),
        ])
        XCTAssertEqual(result.warnings, [
            HeistExecutionWarning(path: "$.body[2]", message: "explicit warning"),
        ])
    }

    func testSummaryCountsTypedRootNodesInsteadOfParsingPaths() {
        let result = HeistExecutionResult(
            steps: [
                .passed(
                    path: "root-a",
                    kind: .heist,
                    durationMs: 1,
                    children: [warnStep(path: "$.body[0]", message: "nested")]
                ),
                .passed(path: "root-b", kind: .heist, durationMs: 1),
                .skipped(path: "$.body[1]", kind: .warn),
            ],
            durationMs: 2
        )

        XCTAssertEqual(result.executedTopLevelStepCount, 2)
        XCTAssertEqual(result.executedNodeCount, 3)
        XCTAssertEqual(result.outputReceiptNodes.map(\.path), [
            "root-a",
            "$.body[0]",
            "root-b",
            "$.body[1]",
        ])
    }

    func testReportProjectionConsumesScoreEvidenceNodesForTreeAndOutputShapes() throws {
        let result = forEachStringSuccessResult()
        let rollup = result.evidenceRollup
        let projection = HeistReportProjection(result: result, accessibilityTrace: nil, profile: .mcp)

        XCTAssertEqual(projection.nodes.map(\.path), rollup.rootNodes.map(\.step.path))
        XCTAssertEqual(projection.outputNodes.map(\.path), rollup.nodes.map(\.step.path))
        XCTAssertEqual(projection.summary.outputReceiptNodeCount, rollup.summary.outputReceiptNodeCount)

        let projectedRoot = try XCTUnwrap(projection.nodes.first)
        let rollupRoot = try XCTUnwrap(rollup.rootNodes.first)
        XCTAssertEqual(projectedRoot.children.map(\.path), rollupRoot.children.map(\.step.path))
    }

    func testReportProjectionFinalScreenIdOriginatesFromScoreSummaryFacts() {
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(elementCount: 1),
            after: makeReceiptTestInterface(elementCount: 2),
            beforeScreenId: "home",
            afterScreenId: "checkout"
        )
        let finalTrace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(elementCount: 2),
            after: makeReceiptTestInterface(elementCount: 3),
            beforeScreenId: "checkout",
            afterScreenId: "confirmation"
        )
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Checkout"))),
                    actionResult: ActionResult.success(
                        method: .activate,
                        evidence: ActionResultSuccessEvidence(observation: .trace(trace))
                    )
                ),
                actionStep(
                    path: "$.body[1]",
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Confirm"))),
                    actionResult: ActionResult.success(
                        method: .activate,
                        evidence: ActionResultSuccessEvidence(observation: .trace(finalTrace))
                    )
                ),
            ],
            durationMs: 12
        )

        let summary = result.evidenceRollup.summary
        let projection = HeistReportProjection(result: result, accessibilityTrace: nil, profile: .mcp)

        XCTAssertEqual(result.evidenceRollup.events.compactMap { event in
            guard case .finalScreen(let path, let screenId) = event else { return nil }
            return "\(path):\(screenId)"
        }, [
            "$.body[0]:checkout",
            "$.body[1]:confirmation",
        ])
        XCTAssertEqual(summary.finalScreenId, "confirmation")
        XCTAssertEqual(projection.summary.finalScreenId, summary.finalScreenId)
    }

    func testActionExpectationUsesTypedResultMeaningsAcrossReportFacts() throws {
        let predicate = AccessibilityPredicate<RootContext>.changed(.screen())
        let dispatchTrace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(elementCount: 1),
            after: makeReceiptTestInterface(elementCount: 2),
            beforeScreenId: "start",
            afterScreenId: "dispatch"
        )
        let expectationTrace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(elementCount: 2),
            after: makeReceiptTestInterface(elementCount: 3),
            beforeScreenId: "dispatch",
            afterScreenId: "settled"
        )
        let result = HeistExecutionResult(
            steps: [
                .failed(
                    path: "$.body[0]",
                    receiptKind: .action,
                    durationMs: 5,
                    intent: .action(command: .activate(.predicate(ElementPredicateTemplate(label: "Pay")))),
                    evidence: .expectation(
                        command: .activate(.predicate(ElementPredicateTemplate(label: "Pay"))),
                        dispatchResult: ActionResult.success(
                            method: .activate,
                            evidence: ActionResultSuccessEvidence(observation: .trace(dispatchTrace))
                        ),
                        expectationResult: ActionResult.failure(
                            method: .wait,
                            errorKind: .timeout,
                            message: "timed out waiting for checkout",
                            evidence: ActionResultFailureEvidence(observation: .trace(expectationTrace))
                        ),
                        expectation: ExpectationResult(
                            met: false,
                            predicate: predicate,
                            actual: "timed out waiting for checkout"
                        )
                    ),
                    failure: HeistFailureDetail(
                        category: .expectation,
                        contract: "action expectation is met",
                        observed: "timed out waiting for checkout",
                        expected: predicate.description
                    )
                ),
            ],
            durationMs: 5,
            abortedAtPath: "$.body[0]"
        )

        let node = try XCTUnwrap(result.steps.first)
        guard case .action(let actionEvidence)? = node.evidence else {
            return XCTFail("Expected action evidence")
        }
        let reportFacts = node.reportFacts
        let reportResults = reportFacts.results
        let projection = HeistReportProjection(result: result, accessibilityTrace: nil, profile: .mcp)
        let projectedNode = try XCTUnwrap(projection.outputNodes.first)
        guard case .action(let projectedAction)? = projectedNode.evidence else {
            return XCTFail("Expected projected action evidence")
        }

        XCTAssertEqual(actionEvidence.dispatchResult?.method, .activate)
        XCTAssertEqual(actionEvidence.expectationResult?.method, .wait)
        XCTAssertEqual(actionEvidence.reportedResult?.method, .wait)
        XCTAssertEqual(actionEvidence.reportedResult?.accessibilityTrace?.endpointScreenId, "settled")
        XCTAssertEqual(reportResults, .action(actionEvidence))
        XCTAssertEqual(reportFacts.results.dispatchedActionResult, reportResults.dispatchedActionResult)
        XCTAssertEqual(reportFacts.results.actionResult, reportResults.actionResult)
        XCTAssertEqual(reportFacts.results.traceEvidenceResult, reportResults.traceEvidenceResult)
        XCTAssertEqual(reportFacts.results.expectation, reportResults.expectation)
        XCTAssertEqual(reportFacts.results.actionErrorKind, reportResults.actionErrorKind)
        XCTAssertEqual(reportFacts.results.dispatchedActionResult?.method, .activate)
        XCTAssertEqual(reportFacts.results.actionResult?.outcome.errorKind, .timeout)
        XCTAssertEqual(reportFacts.results.traceEvidenceResult?.accessibilityTrace?.endpointScreenId, "settled")
        XCTAssertEqual(result.dispatchedActionResults.map(\.method), [.activate])
        XCTAssertEqual(result.reportedActionResults.map(\.method), [.wait])
        XCTAssertEqual(result.traceResultsInExecutionOrder.map(\.method), [.wait])
        XCTAssertEqual(result.evidenceRollup.summary.finalScreenId, "settled")
        XCTAssertEqual(projection.summary.finalScreenId, "settled")
        XCTAssertEqual(projectedNode.actionErrorKind, .timeout)
        guard case .expectation(_, let dispatchResult, let expectationResult, _) = projectedAction else {
            return XCTFail("Expected projected action expectation evidence")
        }
        XCTAssertEqual(dispatchResult.actionMethod.rawValue, "activate")
        XCTAssertEqual(dispatchResult.result.method, .activate)
        XCTAssertEqual(expectationResult.actionMethod.rawValue, "wait")
        XCTAssertEqual(expectationResult.result.method, .wait)
    }

    func testReportProjectionUsesCanonicalActionEvidenceDelta() throws {
        let predicate = AccessibilityPredicate<RootContext>.changed(.screen())
        let dispatchTrace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(elementCount: 1),
            after: makeReceiptTestInterface(elementCount: 2),
            beforeScreenId: "start",
            afterScreenId: "dispatch"
        )
        let expectationTrace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(elementCount: 2),
            after: makeReceiptTestInterface(elementCount: 3),
            beforeScreenId: "dispatch",
            afterScreenId: "settled"
        )
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Pay")))
        let result = HeistExecutionResult(
            steps: [
                .failed(
                    path: "$.body[0]",
                    receiptKind: .action,
                    durationMs: 5,
                    intent: .action(command: command),
                    evidence: .expectation(
                        command: command,
                        dispatchResult: ActionResult.success(
                            method: .activate,
                            evidence: ActionResultSuccessEvidence(observation: .trace(dispatchTrace))
                        ),
                        expectationResult: ActionResult.failure(
                            method: .wait,
                            errorKind: .timeout,
                            message: "timed out waiting for checkout",
                            evidence: ActionResultFailureEvidence(observation: .trace(expectationTrace))
                        ),
                        expectation: ExpectationResult(
                            met: false,
                            predicate: predicate,
                            actual: "timed out"
                        )
                    ),
                    failure: HeistFailureDetail(
                        category: .expectation,
                        contract: "action expectation is met",
                        observed: "timed out waiting for checkout",
                        expected: predicate.description
                    )
                ),
            ],
            durationMs: 5,
            abortedAtPath: "$.body[0]"
        )
        let reportFacts = try XCTUnwrap(result.evidenceRollup.nodes.first?.reportFacts)
        let projection = HeistReportProjection(result: result, accessibilityTrace: nil, profile: .mcp)
        let reportNode = try XCTUnwrap(projection.outputNodes.first)

        XCTAssertEqual(reportNode.status, reportFacts.status)
        XCTAssertEqual(reportNode.message, reportFacts.message)
        XCTAssertEqual(reportNode.failureMessage, reportFacts.failureMessage)
        guard case .action(let actionEvidence)? = reportNode.evidence,
              case .expectation(_, _, let expectationResult, _) = actionEvidence else {
            return XCTFail("Expected projected action expectation evidence")
        }
        XCTAssertEqual(expectationResult.result.accessibilityTrace?.endpointScreenId, "settled")
        XCTAssertEqual(reportNode.traceDelta?.kind, expectationResult.delta?.kind)
        XCTAssertEqual(reportNode.actionErrorKind, reportFacts.results.actionErrorKind)
    }

    func testActionEvidenceDerivesWarningAndRejectsLegacyReceiptWarning() throws {
        let warning = HeistActionWarning.activationWeakAffordance(
            evidence: #"label="Checkout" traits=[staticText] actions=[activate]"#
        )
        let dispatchResult = ActionResult.success(
            method: .activate,
            evidence: ActionResultSuccessEvidence(observation: .none, warning: warning)
        )
        let dispatch = HeistActionEvidence.dispatch(
            command: .activate(.predicate(ElementPredicateTemplate(label: "Checkout"))),
            dispatchResult: dispatchResult
        )
        let encoded = try JSONEncoder().encode(dispatch)
        let decoded = try JSONDecoder().decode(HeistActionEvidence.self, from: encoded)

        XCTAssertEqual(decoded, dispatch)
        XCTAssertEqual(decoded.warning, warning)

        let expectation = HeistActionEvidence.expectation(
            command: .activate(.predicate(ElementPredicateTemplate(label: "Checkout"))),
            dispatchResult: dispatchResult,
            expectationResult: .success(method: .wait, evidence: .none),
            expectation: ExpectationResult(met: true, predicate: .changed(.screen()))
        )
        for receipt in [dispatch, expectation] {
            var legacyReceipt = try XCTUnwrap(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(receipt)) as? [String: Any]
            )
            legacyReceipt["warning"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(warning))
            XCTAssertThrowsError(try JSONDecoder().decode(
                HeistActionEvidence.self,
                from: try JSONSerialization.data(withJSONObject: legacyReceipt)
            ))
        }
    }

    func testReportFactsUseExecutionTreeInsteadOfPlanSiblingRematch() {
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    path: "$.body[9]",
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Delete"))),
                    actionResult: ActionResult.success(method: .activate, evidence: .none)
                ),
            ],
            durationMs: 5
        )

        XCTAssertEqual(result.steps.map(\.path), ["$.body[9]"])
        XCTAssertEqual(result.steps.first?.reportFacts.kind, .action)
        XCTAssertEqual(result.steps.first?.reportFacts.command, .activate)
        XCTAssertEqual(result.steps.first?.reportFacts.target, .predicate(ElementPredicateTemplate(label: "Delete")))
    }

    func testReportFactsCarryStepStoryForProjectionAdapters() {
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Delete"))),
                    actionResult: ActionResult.failure(
                        method: .activate,
                        errorKind: .elementNotFound,
                        message: "Delete not found", evidence: .none),
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

        let summary = result.evidenceRollup.summary
        let report = result.steps[0].reportFacts

        XCTAssertEqual(summary.executedTopLevelStepCount, 1)
        XCTAssertEqual(summary.executedNodeCount, 1)
        XCTAssertEqual(summary.outputReceiptNodeCount, 1)
        XCTAssertEqual(summary.abortedAtPath, "$.body[0]")
        XCTAssertEqual(report.path, "$.body[0]")
        XCTAssertEqual(report.kind, .action)
        XCTAssertNil(report.invocationDisplayName)
        XCTAssertEqual(report.command, .activate)
        XCTAssertEqual(report.target, .predicate(ElementPredicateTemplate(label: "Delete")))
        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.message, "Delete not found")
        XCTAssertEqual(report.failureMessage, "Delete not found")
        XCTAssertEqual(report.failureCategory, .targetResolution)
        XCTAssertEqual(report.results.actionErrorKind, .elementNotFound)
    }

    func testAbortedResultContainsOnlyExecutedSteps() {
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    actionResult: ActionResult.failure(
                        method: .activate,
                        errorKind: .actionFailed,
                        message: "Delete failed", evidence: .none),
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
        XCTAssertEqual(result.steps.map(\.reportFacts.status), [.failed])
        XCTAssertEqual(result.expectationsChecked, 0)
        XCTAssertEqual(result.expectationsMet, 0)
        XCTAssertEqual(result.steps.first?.reportFacts.results.actionResult?.message, "Delete failed")
    }

    func testWaitReportsWaitEvidenceWithoutDispatchedActionResult() {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
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
        XCTAssertEqual(node.reportFacts.kind, .wait)
        XCTAssertEqual(node.reportFacts.status, .passed)
        XCTAssertEqual(node.reportFacts.results.expectation?.met, true)
        XCTAssertEqual(node.reportFacts.results.actionResult?.method, .wait)
        XCTAssertEqual(result.dispatchedActionResults, [])
        XCTAssertEqual(result.reportedActionResults, [])
    }

    func testActionAndWaitSurfaceBothTraceDeltas() {
        let actionTrace = AccessibilityTrace.elementsChangedForTests(elementCount: 5, edits: ElementEdits())
        let waitTrace = AccessibilityTrace.elementsChangedForTests(elementCount: 3, edits: ElementEdits())
        let result = HeistExecutionResult(
            steps: [
                actionStep(
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Submit"))),
                    actionResult: ActionResult.success(
                        method: .activate,
                        evidence: ActionResultSuccessEvidence(observation: .trace(actionTrace))
                    )
                ),
                waitStep(
                    path: "$.body[1]",
                    actionResult: ActionResult.success(
                        method: .wait,
                        evidence: ActionResultSuccessEvidence(observation: .trace(waitTrace))
                    )
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
            actionResult: ActionResult.failure(
                method: .activate,
                errorKind: .actionFailed,
                message: "boom", evidence: .none),
            failure: HeistFailureDetail(
                category: .action,
                contract: "action dispatch succeeds",
                observed: "boom"
            )
        )
        let result = HeistExecutionResult(
            steps: [
                .childAborted(
                    path: "$.body[0]",
                    receiptKind: .heist,
                    durationMs: 5,
                    intent: .heist(name: "Wrapper"),
                    evidence: .heist(
                        name: "heist Wrapper",
                        childFailedPath: "$.body[0].heist.body[0]"
                    ),
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
        XCTAssertEqual(result.evidenceRollup.events.map(eventDescription).filter {
            $0.hasPrefix("firstFailure:")
        }, [
            "firstFailure:$.body[0].heist.body[0]:action",
        ])
        XCTAssertEqual(result.failedStepPath, "$.body[0].heist.body[0]")
        XCTAssertEqual(result.failedStepKind, .action)
        XCTAssertEqual(result.steps.first?.abortedAtChildPath, "$.body[0].heist.body[0]")
        XCTAssertEqual(result.executedTopLevelStepCount, 1)
        XCTAssertEqual(result.executedNodeCount, 2)
        XCTAssertEqual(result.outputReceiptNodes.count, 2)
    }

    func testReportFailureFactsDeriveFromTypedOutcome() {
        let predicate = AccessibilityPredicate<RootContext>.changed(.screen())
        let failure = HeistFailureDetail(
            category: .expectation,
            contract: "action expectation is met",
            observed: "screen did not change",
            expected: predicate.description
        )
        let result = HeistExecutionResult(
            steps: [
                .failed(
                    path: "$.body[0]",
                    receiptKind: .action,
                    durationMs: 5,
                    intent: .action(command: .activate(.predicate(ElementPredicateTemplate(label: "Pay")))),
                    evidence: .expectation(
                        command: .activate(.predicate(ElementPredicateTemplate(label: "Pay"))),
                        dispatchResult: ActionResult.success(method: .activate, evidence: .none),
                        expectationResult: ActionResult.failure(
                            method: .wait,
                            errorKind: .timeout,
                            message: "screen did not change",
                            evidence: .none
                        ),
                        expectation: ExpectationResult(
                            met: false,
                            predicate: predicate,
                            actual: "screen did not change"
                        )
                    ),
                    failure: failure
                ),
            ],
            durationMs: 5,
            abortedAtPath: "$.body[0]"
        )

        let node = result.steps[0]
        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(result.failedStepPath, "$.body[0]")
        XCTAssertEqual(node.reportFacts.status, .failed)
        XCTAssertEqual(node.reportFacts.message, "screen did not change")
        XCTAssertEqual(node.reportFacts.failureMessage, "screen did not change")
        XCTAssertEqual(node.reportFacts.results.actionResult?.outcome.isSuccess, false)
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
                                predicate: .exists(.label("Selected")),
                                met: true
                            ),
                        ],
                        outcome: .matchedCase(index: 0),
                        elapsedMs: 1
                    ),
                    children: [
                        actionStep(
                            path: "$.body[0].conditional.cases[0].body[0]",
                            actionResult: ActionResult.success(method: .activate, evidence: .none)
                        ),
                    ]
                ),
            ],
            durationMs: 8
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportFacts.kind, .conditional)
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].conditional.cases[0].body[0]"])
        XCTAssertEqual(node.children.first?.reportFacts.command, .activate)
    }

    func testWaitForTimeoutWithoutElseReportsWaitFailure() {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let failure = HeistFailureDetail(
            category: .wait,
            contract: "wait predicate is met before timeout",
            observed: "timed out after 2s",
            expected: predicate.description
        )
        let result = HeistExecutionResult(
            steps: [
                waitStep(
                    actionResult: ActionResult.failure(method: .wait, errorKind: .timeout, message: "timed out after 2s", evidence: .none),
                    expectation: ExpectationResult(met: false, predicate: predicate, actual: "timed out after 2s"),
                    failure: failure
                ),
            ],
            durationMs: 2000,
            abortedAtPath: "$.body[0]"
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportFacts.kind, .wait)
        XCTAssertEqual(node.reportFacts.status, .failed)
        XCTAssertEqual(node.children.count, 0)
        XCTAssertEqual(node.reportFacts.results.expectation?.met, false)
    }

    func testWaitForTimeoutWithElseReportsElseChildrenAsHandled() {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let expectation = ExpectationResult(met: false, predicate: predicate, actual: "timed out after 2s")
        guard let handledElseCheck = HeistWaitEvidence.UnmatchedCheck(
            actionResult: ActionResult.failure(method: .wait, errorKind: .timeout, message: "timed out after 2s", evidence: .none),
            expectation: expectation
        ) else {
            preconditionFailure("Handled-else wait fixture requires unmatched wait evidence")
        }
        let result = HeistExecutionResult(
            steps: [
                .passed(
                    path: "$.body[0]",
                    receiptKind: .wait,
                    durationMs: 2000,
                    intent: .wait(predicate: predicate, timeout: 2),
                    evidence: .handledElse(
                        handledElseCheck
                    ),
                    children: [
                        warnStep(path: "$.body[0].wait.else_body[0]", message: "No result"),
                    ]
                ),
            ],
            durationMs: 2000
        )

        let node = result.steps[0]
        XCTAssertEqual(node.reportFacts.status, .passed)
        XCTAssertEqual(node.children.map(\.path), ["$.body[0].wait.else_body[0]"])
        XCTAssertEqual(node.children.first?.reportFacts.status, .passed)
        XCTAssertEqual(result.warnings.map(\.path), ["$.body[0].wait.else_body[0]"])
    }

    func testForEachBodyFailureReportsIterationFailureInStructuredNodes() {
        let result = forEachStringFailureResult()
        let node = result.steps[0]

        XCTAssertEqual(result.abortedAtPath, "$.body[0].for_each_string.iterations[1].body[0]")
        XCTAssertEqual(node.reportFacts.status, .failed)
        XCTAssertEqual(node.abortedAtChildPath, "$.body[0].for_each_string.iterations[1].body[0]")
        XCTAssertEqual(node.children.map(\.reportFacts.status), [.passed, .failed])
        XCTAssertEqual(node.children[1].abortedAtChildPath, "$.body[0].for_each_string.iterations[1].body[0]")
        XCTAssertEqual(node.children[1].children.first?.reportFacts.results.actionResult?.message, "field missing")
        XCTAssertEqual(node.reportFacts.message, "iteration 1 failed for value \"Eggs\"")
        XCTAssertEqual(result.executedTopLevelStepCount, 1)
        XCTAssertEqual(result.executedNodeCount, 5)
        XCTAssertEqual(result.outputReceiptNodes.count, 5)
    }

    func testForEachMultipleIterationsSurfacesReceiptTreeInOutputOrder() {
        let result = forEachStringSuccessResult()
        let node = result.steps[0]

        XCTAssertEqual(node.reportFacts.status, .passed)
        XCTAssertEqual(node.children.map(\.reportFacts.status), [.passed, .passed])
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
                .failed(
                    path: "$.body[1]",
                    kind: .fail,
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

        XCTAssertEqual(result.steps.map(\.reportFacts.kind), [.warn, .fail])
        XCTAssertEqual(result.steps.map(\.reportFacts.status), [.passed, .failed])
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
            actionResult: ActionResult.failure(
                method: .activate,
                errorKind: .actionFailed,
                message: "Add to Cart not found", evidence: .none),
            failure: HeistFailureDetail(
                category: .action,
                contract: "action dispatch succeeds",
                observed: "Add to Cart not found"
            )
        )
        let result = HeistExecutionResult(
            steps: [
                .childAborted(
                    path: "$.body[0]",
                    receiptKind: .invocation,
                    durationMs: 5,
                    intent: .invoke(
                        path: HeistInvocationPath.preconditionValidated(dottedName: "LibraryScreen.addToCart"),
                        argument: .string(.literal("Milk"))
                    ),
                    evidence: .invocation(
                        invocation: invocation,
                        name: "LibraryScreen.addToCart",
                        argument: "Milk",
                        outcome: .childFailed(path: child.path)
                    ),
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
        XCTAssertEqual(node.reportFacts.kind, .invoke)
        XCTAssertEqual(node.reportFacts.capabilityName, "LibraryScreen.addToCart")
        XCTAssertEqual(node.reportFacts.invocationDisplayName, "RunHeist(\"LibraryScreen.addToCart\", \"Milk\")")
        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(node.reportFacts.status, .failed)
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
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Delete"))),
                    actionResult: ActionResult.failure(
                        method: .activate,
                        errorKind: .elementNotFound,
                        message: "Delete not found", evidence: .none),
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

    func testJUnitWrapperFailureDerivesFromReceiptStatusWhenMessageSuppressed() async {
        let childPath = "$.body[0].heist.body[0]"
        let child = actionStep(
            path: childPath,
            actionResult: ActionResult.failure(
                method: .activate,
                errorKind: .actionFailed,
                message: "Save failed",
                evidence: .none
            ),
            failure: HeistFailureDetail(
                category: .action,
                contract: "action dispatch succeeds",
                observed: "Save failed"
            )
        )
        let result = HeistExecutionResult(
            steps: [
                .childAborted(
                    path: "$.body[0]",
                    receiptKind: .heist,
                    durationMs: 5,
                    intent: .heist(name: "Wrapper"),
                    evidence: .heist(
                        name: "heist Wrapper",
                        childFailedPath: childPath
                    ),
                    failure: HeistFailureDetail(
                        category: .invocation,
                        contract: "child execution completes without failure",
                        observed: "child failed at \(childPath)"
                    ),
                    abortedAtChildPath: childPath,
                    children: [child]
                ),
            ],
            durationMs: 5,
            abortedAtPath: childPath
        )
        let wrapper = result.outputReceiptNodes[0]
        XCTAssertEqual(wrapper.reportFacts.status, .failed)
        XCTAssertNil(wrapper.reportFacts.failureMessage)

        let rows = await Task { @ButtonHeistActor in
            TheFence(configuration: .init()).junitSteps(result: result)
        }.value

        guard case .failed(let message, let errorKind) = rows.first?.outcome else {
            return XCTFail("Expected wrapper JUnit row to fail, got \(String(describing: rows.first?.outcome))")
        }
        XCTAssertTrue(message.hasPrefix("child failed at \(childPath)"), message)
        XCTAssertEqual(errorKind, .commandError)
    }

    func testJUnitExpectationFailureUsesExpectationReceiptFact() async {
        let predicate = AccessibilityPredicate<RootContext>.changed(.screen())
        let result = HeistExecutionResult(
            steps: [
                .failed(
                    path: "$.body[0]",
                    receiptKind: .action,
                    durationMs: 5,
                    intent: .action(command: .activate(.predicate(ElementPredicateTemplate(label: "Pay")))),
                    evidence: .expectation(
                        command: .activate(.predicate(ElementPredicateTemplate(label: "Pay"))),
                        dispatchResult: ActionResult.success(method: .activate, evidence: .none),
                        expectationResult: ActionResult.failure(
                            method: .wait,
                            errorKind: .timeout,
                            message: "elementsChanged",
                            evidence: .none
                        ),
                        expectation: ExpectationResult(
                            met: false,
                            predicate: predicate,
                            actual: "elementsChanged"
                        )
                    ),
                    failure: HeistFailureDetail(
                        category: .expectation,
                        contract: "action expectation is met",
                        observed: "elementsChanged",
                        expected: predicate.description
                    )
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
        XCTAssertEqual(errorKind, .action(.timeout))
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
                .failed(
                    path: "$.body[0]",
                    kind: .fail,
                    durationMs: 1,
                    intent: .fail(message: "stop"),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "Fail(...) aborts the heist",
                        observed: "stop"
                    )
                ),
                .passed(
                    path: "$.body[0].failure.actions[0]",
                    receiptKind: .action,
                    durationMs: 1,
                    intent: .action(command: .takeScreenshot),
                    evidence: .dispatch(
                        command: .takeScreenshot,
                        dispatchResult: ActionResult.success(payload: .screenshot(screenshot), evidence: .none)
                    )
                ),
            ],
            durationMs: 2,
            abortedAtPath: "$.body[0]"
        )
        let rows = await TheFence(configuration: .init()).junitSteps(result: result)

        guard case .failed(let message, let errorKind) = rows.first?.outcome else {
            return XCTFail("Expected failed JUnit row, got \(String(describing: rows.first?.outcome))")
        }
        XCTAssertEqual(errorKind, HeistJUnitReport.ReportErrorKind.commandError)
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
                .failed(
                    path: "$.body[1]",
                    kind: .fail,
                    durationMs: 1,
                    intent: .fail(message: "stop"),
                    failure: HeistFailureDetail(
                        category: .explicitFailure,
                        contract: "explicit heist failure",
                        observed: "stop"
                    )
                ),
                .skipped(
                    path: "$.body[2]",
                    kind: .action,
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
        XCTAssertEqual(skipped.reportFacts.results, .none)
        XCTAssertNil(skipped.reportFacts.results.actionResult)
        XCTAssertNil(skipped.reportFacts.results.expectation)
    }

    func testPublicHeistEvidenceProjectionEncodesExactlyOneVariantPerEvidenceCase() throws {
        let plan = try evidenceProjectionPlan()
        for testCase in evidenceProjectionCases() {
            let response = FenceResponse.heistExecution(
                plan: plan,
                result: HeistExecutionResult(steps: [testCase.step], durationMs: testCase.step.durationMs)
            )
            let report = try publicHeistReportJSON(response)
            let reportNode = try XCTUnwrap(try report.array("nodes").first, testCase.name)
            let evidence = try reportNode.object("evidence")

            XCTAssertEqual(try evidenceVariantKeys(evidence), Set([testCase.expectedKey]), testCase.name)
            try testCase.assertEvidence(evidence)
        }
    }

    // MARK: - Fixtures

    private func eventDescription(_ event: HeistExecutionEvidenceEvent) -> String {
        switch event {
        case .nodeVisited(let node):
            return "visit:\(node.step.path)"
        case .dispatchedActionResult(let path, let result):
            return "dispatch:\(path):\(result.method.rawValue)"
        case .reportedActionResult(let path, let result):
            return "report:\(path):\(result.method.rawValue)"
        case .traceResult(let path, let result):
            return "trace:\(path):\(result.method.rawValue)"
        case .expectationChecked(let path, let expectation):
            return "expectationChecked:\(path):\(expectation.met)"
        case .expectationMet(let path, _):
            return "expectationMet:\(path)"
        case .firstFailure(let step):
            return "firstFailure:\(step.path):\(step.kind.rawValue)"
        case .finalScreen(let path, let screenId):
            return "finalScreen:\(path):\(screenId)"
        }
    }

    private typealias EvidenceProjectionCase = (
        name: String,
        step: HeistExecutionStepResult,
        expectedKey: String,
        assertEvidence: (JSONProbe) throws -> Void
    )

    private func evidenceVariantKeys(_ evidence: JSONProbe) throws -> Set<String> {
        guard case .object(let object) = try evidence.decode(JSONValue.self) else {
            XCTFail("Expected evidence object")
            return []
        }
        return Set(object.keys)
    }

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
            try HeistStep.action(ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: "Button"))))),
        ])
    }

    private func evidenceProjectionPredicate() -> AccessibilityPredicate<RootContext> {
        .exists(.label("Ready"))
    }

    private func actionEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "action",
            step: actionStep(
                command: .activate(.predicate(ElementPredicateTemplate(label: "Button"))),
                actionResult: ActionResult.success(
                    method: .activate,
                    evidence: ActionResultSuccessEvidence(
                        observation: .none,
                        warning: .activationWeakAffordance(
                            evidence: #"label="Button" traits=[staticText] actions=[activate]"#
                        )
                    )
                )
            ),
            expectedKey: "action",
            assertEvidence: { evidence in
                let action = try evidence.object("action")
                XCTAssertEqual(try action.string("commandName"), "activate")
                let result = try action.object("result")
                let warning = try result.object("warning")
                XCTAssertEqual(try warning.string("code"), "activation_weak_affordance_evidence")
                try action.assertMissing("warning")
                try evidence.assertMissing("warning")
            }
        )
    }

    private func waitEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "wait",
            step: waitStep(
                actionResult: ActionResult.success(method: .wait, evidence: .none),
                expectation: ExpectationResult(met: true, predicate: evidenceProjectionPredicate())
            ),
            expectedKey: "wait",
            assertEvidence: { evidence in
                let wait = try evidence.object("wait")
                XCTAssertEqual(try wait.object("result").string("method"), "wait")
                XCTAssertEqual(try wait.object("expectation").bool("met"), true)
                try wait.assertMissing("warning")
            }
        )
    }

    private func caseSelectionEvidenceProjectionCase() -> EvidenceProjectionCase {
        let predicate = AccessibilityPredicate<RootContext>.exists(.label("Ready"))
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
                let caseSelection = try evidence.object("caseSelection")
                XCTAssertEqual(try caseSelection.int("caseCount"), 1)
                XCTAssertEqual(try caseSelection.array("cases").count, 1)
            }
        )
    }

    private func forEachStringEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "forEachString",
            step: .passed(
                path: "$.body[0]",
                receiptKind: .forEachString,
                durationMs: 4,
                intent: .forEachString(parameter: "item", count: 2),
                evidence: HeistForEachStringEvidence(
                    parameter: "item",
                    count: 2,
                    iterationCount: 1,
                    iterationOrdinal: 0,
                    value: "Milk"
                )
            ),
            expectedKey: "forEachString",
            assertEvidence: { evidence in
                let forEachString = try evidence.object("forEachString")
                XCTAssertEqual(try forEachString.string("parameter"), "item")
                XCTAssertEqual(try forEachString.string("value"), "Milk")
            }
        )
    }

    private func forEachElementEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "forEachElement",
            step: .passed(
                path: "$.body[0]",
                receiptKind: .forEachElement,
                durationMs: 5,
                intent: .forEachElement(parameter: "row", matching: ElementPredicate(label: "Row"), limit: 3),
                evidence: HeistForEachElementEvidence(
                    parameter: "row",
                    matching: ElementPredicate(label: "Row"),
                    limit: 3,
                    matchedCount: 2,
                    iterationCount: 2,
                    iterationOrdinal: 1,
                    targetOrdinal: 1,
                    targetSummary: "\"Row\" staticText"
                )
            ),
            expectedKey: "forEachElement",
            assertEvidence: { evidence in
                let forEachElement = try evidence.object("forEachElement")
                XCTAssertEqual(try forEachElement.string("parameter"), "row")
                XCTAssertEqual(try forEachElement.int("matchedCount"), 2)
                XCTAssertEqual(try forEachElement.string("targetSummary"), "\"Row\" staticText")
            }
        )
    }

    private func repeatUntilEvidenceProjectionCase() -> EvidenceProjectionCase {
        let predicate = evidenceProjectionPredicate()
        return (
            name: "repeatUntil",
            step: .passed(
                path: "$.body[0]",
                receiptKind: .repeatUntil,
                durationMs: 6,
                intent: .repeatUntil(predicate: predicate, timeout: 2),
                evidence: HeistRepeatUntilEvidence.predicateMet(
                    predicate: predicate,
                    timeout: 2,
                    iterationCount: 1,
                    expectation: ExpectationResult.Met(predicate: predicate),
                    actionResult: ActionResult.success(method: .wait, evidence: .none),
                    lastObservedSummary: "Ready"
                )
            ),
            expectedKey: "repeatUntil",
            assertEvidence: { evidence in
                let repeatUntil = try evidence.object("repeatUntil")
                XCTAssertEqual(try repeatUntil.double("timeout"), 2.0)
                XCTAssertEqual(try repeatUntil.int("iterationCount"), 1)
                XCTAssertEqual(try repeatUntil.string("lastObservedSummary"), "Ready")
            }
        )
    }

    private func heistInvocationEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "heistInvocation",
            step: .passed(
                path: "$.body[0]",
                receiptKind: .heist,
                durationMs: 7,
                intent: .heist(name: "Nested"),
                evidence: .heist(name: "Nested", childFailedPath: nil)
            ),
            expectedKey: "invocation",
            assertEvidence: { evidence in
                let invocation = try evidence.object("invocation")
                XCTAssertEqual(try invocation.string("name"), "Nested")
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
        let actionResult = ActionResult.success(method: .wait, evidence: .none)
        guard let matchedCheck = HeistWaitEvidence.MatchedCheck(
            actionResult: actionResult,
            expectation: ExpectationResult.Met(predicate: expectation.predicate, actual: expectation.actual)
        ) else {
            preconditionFailure("Matched invocation fixture requires successful wait evidence")
        }
        return (
            name: "invokeInvocation",
            step: .passed(
                path: "$.body[0]",
                receiptKind: .invocation,
                durationMs: 8,
                intent: .invoke(path: HeistInvocationPath.preconditionValidated(dottedName: "LibraryScreen.addToCart"), argument: .string(.literal("Milk"))),
                evidence: .invocation(
                    invocation: invocation,
                    name: "LibraryScreen.addToCart",
                    argument: "Milk",
                    outcome: .completed(
                        expectation: .wait(.matched(
                            matchedCheck,
                            baselineSummary: "before addToCart",
                            finalSummary: "Ready"
                        ))
                    )
                )
            ),
            expectedKey: "invocation",
            assertEvidence: { evidence in
                let invocation = try evidence.object("invocation")
                let expectationEvidence = try invocation.object("expectationEvidence")
                XCTAssertEqual(try invocation.string("capability"), "LibraryScreen.addToCart")
                XCTAssertEqual(try invocation.string("argument"), "Milk")
                XCTAssertEqual(try expectationEvidence.string("outcome"), "matched")
                XCTAssertEqual(try expectationEvidence.object("result").string("method"), "wait")
                XCTAssertEqual(try expectationEvidence.string("baselineSummary"), "before addToCart")
                XCTAssertEqual(try expectationEvidence.string("finalSummary"), "Ready")
            }
        )
    }

    private func warningEvidenceProjectionCase() -> EvidenceProjectionCase {
        (
            name: "warning",
            step: warnStep(message: "Heads up"),
            expectedKey: "warning",
            assertEvidence: { evidence in
                let warning = try evidence.object("warning")
                XCTAssertEqual(try warning.string("path"), "$.body[0]")
                XCTAssertEqual(try warning.string("message"), "Heads up")
            }
        )
    }

    private func actionStep(
        path: String = "$.body[0]",
        command: HeistActionCommand? = .activate(.predicate(ElementPredicateTemplate(label: "Button"))),
        actionResult: ActionResult,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        let evidence: HeistActionEvidence
        if let expectationActionResult, let expectation {
            guard let command else {
                preconditionFailure("Expectation action evidence requires a command")
            }
            evidence = .expectation(
                command: command,
                dispatchResult: actionResult,
                expectationResult: expectationActionResult,
                expectation: expectation
            )
        } else {
            precondition(expectationActionResult == nil && expectation == nil)
            evidence = command.map {
                .dispatch(command: $0, dispatchResult: actionResult)
            } ?? .commandlessDispatch(dispatchResult: actionResult)
        }

        let intent = command.map {
            HeistStepIntent.action(command: $0)
        }
        if let failure {
            return .failed(
                path: path,
                receiptKind: .action,
                durationMs: 5,
                intent: intent,
                evidence: evidence,
                failure: failure
            )
        }
        return .passed(
            path: path,
            receiptKind: .action,
            durationMs: 5,
            intent: intent,
            evidence: evidence
        )
    }

    private func waitStep(
        path: String = "$.body[0]",
        actionResult: ActionResult = ActionResult.success(method: .wait, evidence: .none),
        expectation: ExpectationResult = ExpectationResult(
            met: true,
            predicate: .exists(.label("Done"))
        ),
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        let waitEvidence: HeistWaitEvidence
        if failure == nil {
            guard let metExpectation = ExpectationResult.Met(expectation) else {
                preconditionFailure("Passed wait test fixture requires a met expectation")
            }
            guard let matchedCheck = HeistWaitEvidence.MatchedCheck(
                actionResult: actionResult,
                expectation: metExpectation
            ) else {
                preconditionFailure("Passed wait test fixture requires a successful action result")
            }
            waitEvidence = .matched(matchedCheck)
        } else {
            guard let unmatchedCheck = HeistWaitEvidence.UnmatchedCheck(
                actionResult: actionResult,
                expectation: expectation
            ) else {
                preconditionFailure("Failed wait test fixture requires unmatched wait evidence")
            }
            waitEvidence = .failed(unmatchedCheck)
        }
        let intentPredicate = expectation.predicate
            ?? AccessibilityPredicate<RootContext>.exists(.label("predicate"))
        if let failure {
            return .failed(
                path: path,
                receiptKind: .wait,
                durationMs: 20,
                intent: .wait(predicate: intentPredicate, timeout: 0),
                evidence: waitEvidence,
                failure: failure
            )
        }
        return .passed(
            path: path,
            receiptKind: .wait,
            durationMs: 20,
            intent: .wait(predicate: intentPredicate, timeout: 0),
            evidence: waitEvidence
        )
    }

    private func caseStep(
        kind: HeistExecutionStepKind,
        status: HeistExecutionStepStatus = .passed,
        selection: HeistCaseSelectionResult,
        failure: HeistFailureDetail? = nil,
        children: [HeistExecutionStepResult] = []
    ) -> HeistExecutionStepResult {
        let evidence = HeistCaseSelectionEvidence(selection: selection)
        if let abortedAtChildPath = children.firstFailedStep?.path {
            return .childAborted(
                path: "$.body[0]",
                receiptKind: .conditional,
                durationMs: selection.elapsedMs,
                intent: .conditional,
                evidence: evidence,
                failure: failure ?? HeistFailureDetail(
                    category: .invocation,
                    contract: "selected case body completes without failure",
                    observed: "child failed at \(abortedAtChildPath)"
                ),
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        }
        if status == .failed {
            return .failed(
                path: "$.body[0]",
                receiptKind: .conditional,
                durationMs: selection.elapsedMs,
                intent: .conditional,
                evidence: evidence,
                failure: failure ?? HeistFailureDetail(
                    category: .validation,
                    contract: "conditional branch completes",
                    observed: "conditional failed"
                ),
                children: children
            )
        }
        return .passed(
            path: "$.body[0]",
            receiptKind: .conditional,
            durationMs: selection.elapsedMs,
            intent: .conditional,
            evidence: evidence,
            children: children
        )
    }

    private func warnStep(path: String = "$.body[0]", message: String) -> HeistExecutionStepResult {
        .passed(
            path: path,
            receiptKind: .warning,
            durationMs: 1,
            intent: .warn(message: message),
            evidence: HeistExecutionWarning(path: path, message: message)
        )
    }

    private func forEachStringFailureResult() -> HeistExecutionResult {
        let failedActionPath = "$.body[0].for_each_string.iterations[1].body[0]"
        let firstIteration = HeistExecutionStepResult.passed(
            path: "$.body[0].for_each_string.iterations[0]",
            receiptKind: .forEachStringIteration,
            durationMs: 5,
            intent: .forEachString(parameter: "item", count: 2),
            evidence: HeistForEachStringEvidence(
                parameter: "item",
                count: 2,
                iterationCount: 1,
                iterationOrdinal: 0,
                value: "Milk"
            ),
            children: [
                actionStep(
                    path: "$.body[0].for_each_string.iterations[0].body[0]",
                    command: .typeText(text: .literal("Milk"), target: nil),
                    actionResult: ActionResult.success(method: .typeText, evidence: .none)
                ),
            ]
        )
        let secondIteration = HeistExecutionStepResult.childAborted(
            path: "$.body[0].for_each_string.iterations[1]",
            receiptKind: .forEachStringIteration,
            durationMs: 6,
            intent: .forEachString(parameter: "item", count: 2),
            evidence: HeistForEachStringEvidence(
                parameter: "item",
                count: 2,
                iterationCount: 2,
                iterationOrdinal: 1,
                value: "Eggs",
                failureReason: "child failed at \(failedActionPath)"
            ),
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
                    actionResult: ActionResult.failure(
                        method: .typeText,
                        errorKind: .elementNotFound,
                        message: "field missing", evidence: .none),
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
                .childAborted(
                    path: "$.body[0]",
                    receiptKind: .forEachString,
                    durationMs: 30,
                    intent: .forEachString(parameter: "item", count: 2),
                    evidence: HeistForEachStringEvidence(
                        parameter: "item",
                        count: 2,
                        iterationCount: 2,
                        failureReason: "iteration 1 failed for value \"Eggs\""
                    ),
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
                .passed(
                    path: "$.body[0]",
                    receiptKind: .forEachString,
                    durationMs: 30,
                    intent: .forEachString(parameter: "item", count: 2),
                    evidence: HeistForEachStringEvidence(
                        parameter: "item",
                        count: 2,
                        iterationCount: 2
                    ),
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
        .passed(
            path: "$.body[0].for_each_string.iterations[\(ordinal)]",
            receiptKind: .forEachStringIteration,
            durationMs: 5,
            intent: .forEachString(parameter: "item", count: 2),
            evidence: HeistForEachStringEvidence(
                parameter: "item",
                count: 2,
                iterationCount: ordinal + 1,
                iterationOrdinal: ordinal,
                value: value
            ),
            children: [
                actionStep(
                    path: actionPath,
                    command: .typeText(text: .literal(value), target: nil),
                    actionResult: ActionResult.success(method: .typeText, evidence: .none)
                ),
            ]
        )
    }

    private func caseMatch(
        _ predicate: AccessibilityPredicate<RootContext>,
        met: Bool
    ) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicate,
            met: met
        )
    }
}
