import XCTest
import ThePlans
import AccessibilitySnapshotModel
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

    func testActionFailureWinsOverAttachedExpectationResult() {
        let expectation = ExpectationResult(
            met: false,
            predicate: .state(.present(ElementPredicate(label: "Done"))),
            actual: "not evaluated"
        )
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult(
                success: false,
                method: .activate,
                message: "button disabled",
                errorKind: .elementNotFound
            ),
            expectation: expectation
        )

        let json = publicJSONObject(response)

        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["errorClass"] as? String, "elementNotFound")
        XCTAssertNil(json["expectation"])
        XCTAssertEqual(response.compactFormatted(), "activate: error[elementNotFound]: button disabled")
        XCTAssertEqual(response.humanFormatted(), "Error: button disabled")
        XCTAssertTrue(response.isFailure)
    }

    func testActionFailureCodeAndClassAgreeAcrossPublicFormats() {
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult(
                success: false,
                method: .activate,
                message: "Could not access accessibility tree: no traversable app windows",
                errorKind: .actionFailed
            )
        )

        let json = publicJSONObject(response)
        let compact = response.compactFormatted()

        XCTAssertEqual(json["status"] as? String, "error")
        XCTAssertEqual(json["errorClass"] as? String, "actionFailed")
        XCTAssertEqual(json["errorCode"] as? String, "request.accessibility_tree_unavailable")
        XCTAssertTrue(compact.contains("error[request.accessibility_tree_unavailable]"), compact)
    }

    func testExpectationFailureStatusAndHintAgreeAcrossJSONAndCompact() {
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult(success: true, method: .activate),
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.screen()),
                actual: "elementsChanged"
            )
        )

        let json = publicJSONObject(response)
        let expectation = json["expectation"] as? [String: Any]
        let compact = response.compactFormatted()

        XCTAssertEqual(json["status"] as? String, "expectation_failed")
        XCTAssertNil(json["errorClass"])
        XCTAssertEqual(expectation?["met"] as? Bool, false)
        XCTAssertEqual(expectation?["actual"] as? String, "elementsChanged")
        XCTAssertTrue(compact.contains("[expectation FAILED: got elementsChanged]"), compact)
        XCTAssertTrue(compact.contains("screen_changed requires a screen-level transition"), compact)
        XCTAssertTrue(response.isFailure)
    }

    func testActivateNoChangeExpectationFailureExplainsSemanticActivationPath() {
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult(success: true, method: .activate),
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.elements),
                actual: "noChange"
            )
        )

        let json = publicJSONObject(response)
        let expectation = json["expectation"] as? [String: Any]
        let compact = response.compactFormatted()
        let human = response.humanFormatted()

        XCTAssertEqual(json["status"] as? String, "expectation_failed")
        XCTAssertEqual(expectation?["actual"] as? String, "noChange")
        XCTAssertTrue(
            (expectation?["hint"] as? String)?.contains("accessibilityActivate()") == true,
            "\(String(describing: expectation?["hint"]))"
        )
        XCTAssertTrue(compact.contains("[expectation FAILED: got noChange]"), compact)
        XCTAssertTrue(compact.contains("does not send activation-point tap dispatch"), compact)
        XCTAssertTrue(human.contains("[expectation FAILED: expected changed(elements_changed), got noChange]"), human)
        XCTAssertTrue(human.contains("accessibility activation path is inert or mismatched"), human)
        XCTAssertTrue(response.isFailure)
    }

    func testActivateNoChangeWithoutExpectationRemainsSuccessful() {
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult(success: true, method: .activate)
        )

        let json = publicJSONObject(response)

        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertNil(json["expectation"])
        XCTAssertEqual(response.compactFormatted(), "activate: ok")
        XCTAssertTrue(response.humanFormatted().contains("✓ activate"))
        XCTAssertFalse(response.isFailure)
    }

    func testActivateNoChangeCarriesActivationTraceWithoutFailingAction() {
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult(
                success: true,
                method: .activate,
                accessibilityTrace: makeReceiptTestTrace(
                    before: makeReceiptTestInterface(elementCount: 3),
                    after: makeReceiptTestInterface(elementCount: 3)
                ),
                activationTrace: ActivationTrace(
                    axActivateReturned: false,
                    tapActivationDispatched: true,
                    tapActivationPoint: ScreenPoint(x: 888, y: 372),
                    tapActivationSucceeded: true
                )
            )
        )

        let json = publicJSONObject(response)
        let activationTrace = json["activationTrace"] as? [String: Any]
        let compact = response.compactFormatted()

        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(activationTrace?["axActivateReturned"] as? Bool, false)
        XCTAssertEqual(activationTrace?["tapActivationDispatched"] as? Bool, true)
        XCTAssertEqual(activationTrace?["tapActivationSucceeded"] as? Bool, true)
        XCTAssertEqual(response.isFailure, false)
        XCTAssertTrue(compact.contains("activate: no change"), compact)
        XCTAssertTrue(compact.contains("tapActivationDispatched=true"), compact)
        XCTAssertTrue(compact.contains("tapActivationPoint=point(888,372)"), compact)
    }

    func testElementsChangedActionOutputIncludesConcreteElementDelta() {
        let added = makeReceiptTestElement(
            label: "Barbaresco",
            value: "$55.00",
            identifier: "wine_barbaresco",
            traits: [.staticText]
        )
        let unchanged = (0..<11).map { index in
            makeReceiptTestElement(label: "Row \(index)", identifier: "row_\(index)")
        }
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(unchanged),
            after: makeReceiptTestInterface(unchanged + [added])
        )
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult(success: true, method: .activate, accessibilityTrace: trace)
        )

        let json = publicJSONObject(response)
        let delta = json["delta"] as? [String: Any]
        let edits = delta?["edits"] as? [String: Any]
        let addedJSON = edits?["added"] as? [[String: Any]]
        let compact = response.compactFormatted()
        let human = response.humanFormatted()

        XCTAssertEqual(delta?["kind"] as? String, "elementsChanged")
        XCTAssertEqual(addedJSON?.first?["label"] as? String, "Barbaresco")
        XCTAssertEqual(addedJSON?.first?["identifier"] as? String, "wine_barbaresco")
        XCTAssertTrue(compact.contains(#"+ "Barbaresco":"$55.00" staticText id="wine_barbaresco""#), compact)
        XCTAssertTrue(human.contains(#"+ "Barbaresco":"$55.00" staticText id="wine_barbaresco""#), human)
    }

    func testScreenChangedActionOutputIncludesDestinationSummaryTree() {
        let destination = makeReceiptTestInterface([
            makeReceiptTestElement(label: "Checkout", identifier: "checkout_title", traits: [.header]),
            makeReceiptTestElement(label: "Pay", identifier: "pay_button", traits: [.button], actions: [.activate]),
        ])
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface([makeReceiptTestElement(label: "Cart", identifier: "cart_title")]),
            after: destination,
            beforeScreenId: "cart",
            afterScreenId: "checkout"
        )
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult(success: true, method: .activate, accessibilityTrace: trace)
        )

        let json = publicJSONObject(response)
        let delta = json["delta"] as? [String: Any]
        let newInterface = delta?["newInterface"] as? [String: Any]
        let compact = response.compactFormatted()
        let human = response.humanFormatted()

        XCTAssertEqual(delta?["kind"] as? String, "screenChanged")
        XCTAssertNotNil(newInterface)
        XCTAssertTrue(compact.contains("activate: screen changed\n2 elements"), compact)
        XCTAssertTrue(compact.contains(#""Checkout" header id="checkout_title""#), compact)
        XCTAssertTrue(compact.contains(#""Pay" button id="pay_button""#), compact)
        XCTAssertTrue(human.contains("screen changed]\n2 elements"), human)
        XCTAssertTrue(human.contains(#""Checkout" header id="checkout_title""#), human)
    }

    func testHeistActionStructuredOutputIncludesConcreteElementDeltaWithoutDumpingSuccessCompact() throws {
        let unchanged = (0..<3).map { index in
            makeReceiptTestElement(label: "Row \(index)", identifier: "row_\(index)")
        }
        let lazyRow = makeReceiptTestElement(
            label: "Lazy Row",
            value: "Loaded by scroll",
            identifier: "lazy_row",
            traits: [.staticText]
        )
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(unchanged),
            after: makeReceiptTestInterface(unchanged + [lazyRow])
        )
        let command = HeistActionCommand.activate(.target(.predicate(ElementPredicate(label: "Load More"))))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let result = HeistExecutionResult(
            steps: [
                actionReceiptStep(
                    command: command,
                    result: ActionResult(success: true, method: .activate, accessibilityTrace: trace)
                ),
            ],
            durationMs: 8
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

        let compact = response.compactFormatted()
        let json = publicJSONObject(response)
        let report = try XCTUnwrap(json["report"] as? [String: Any])
        let nodes = try XCTUnwrap(report["nodes"] as? [[String: Any]])
        let action = try XCTUnwrap(nodes.first?["action"] as? [String: Any])
        let actionResult = try XCTUnwrap(action["result"] as? [String: Any])
        let delta = try XCTUnwrap(actionResult["delta"] as? [String: Any])
        let edits = try XCTUnwrap(delta["edits"] as? [String: Any])
        let added = try XCTUnwrap(edits["added"] as? [[String: Any]])

        XCTAssertTrue(compact.contains("-> elements changed"), compact)
        XCTAssertFalse(compact.contains(#"+ "Lazy Row":"Loaded by scroll" staticText id="lazy_row""#), compact)
        XCTAssertEqual(delta["kind"] as? String, "elementsChanged")
        XCTAssertEqual(added.first?["label"] as? String, "Lazy Row")
        XCTAssertEqual(added.first?["value"] as? String, "Loaded by scroll")
        XCTAssertEqual(added.first?["identifier"] as? String, "lazy_row")
    }

    func testPublicHeistJSONBoundsActionDeltaAndReportsOmissions() throws {
        let addedRows = (0..<8).map { index in
            makeReceiptTestElement(
                label: "Lazy Row \(index)",
                value: "Loaded \(index)",
                identifier: "lazy_row_\(index)",
                traits: [.staticText]
            )
        }
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface([]),
            after: makeReceiptTestInterface(addedRows)
        )
        let command = HeistActionCommand.activate(.target(.predicate(ElementPredicate(label: "Load More"))))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let response = FenceResponse.heistExecution(
            plan: plan,
            result: HeistExecutionResult(
                steps: [
                    actionReceiptStep(
                        command: command,
                        result: ActionResult(success: true, method: .activate, accessibilityTrace: trace)
                    ),
                ],
                durationMs: 8
            )
        )

        let json = publicJSONObject(response)
        let report = try XCTUnwrap(json["report"] as? [String: Any])
        let nodes = try XCTUnwrap(report["nodes"] as? [[String: Any]])
        let action = try XCTUnwrap(nodes.first?["action"] as? [String: Any])
        let actionResult = try XCTUnwrap(action["result"] as? [String: Any])
        let delta = try XCTUnwrap(actionResult["delta"] as? [String: Any])
        let edits = try XCTUnwrap(delta["edits"] as? [String: Any])
        let added = try XCTUnwrap(edits["added"] as? [[String: Any]])
        let editOmissions = try XCTUnwrap(edits["omitted"] as? [String: Any])
        let resultOmissions = try XCTUnwrap(actionResult["omitted"] as? [String: Any])
        let traceOmission = try XCTUnwrap(resultOmissions["accessibilityTrace"] as? [String: Any])
        let encoded = String(data: try response.jsonData(), encoding: .utf8) ?? ""

        XCTAssertEqual(added.count, 5)
        XCTAssertTrue(added.allSatisfy { ($0["label"] as? String)?.hasPrefix("Lazy Row ") == true }, "\(added)")
        XCTAssertEqual(editOmissions["added"] as? Int, 3)
        XCTAssertEqual(traceOmission["projectedAs"] as? String, "delta")
        XCTAssertEqual(traceOmission["omittedCount"] as? Int, 2)
        XCTAssertFalse(encoded.contains(#""captures""#), encoded)
        XCTAssertFalse(encoded.contains(#""newInterface""#), encoded)
    }

    func testPublicHeistJSONUsesBoundedScreenProjectionForActionDelta() throws {
        let afterRows = (0..<8).map { index in
            makeReceiptTestElement(
                label: "Checkout Row \(index)",
                identifier: "checkout_row_\(index)",
                traits: [.staticText]
            )
        }
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface([]),
            after: makeReceiptTestInterface(afterRows),
            beforeScreenId: "before",
            afterScreenId: "checkout"
        )
        let command = HeistActionCommand.activate(.target(.predicate(ElementPredicate(label: "Checkout"))))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let response = FenceResponse.heistExecution(
            plan: plan,
            result: HeistExecutionResult(
                steps: [
                    actionReceiptStep(
                        command: command,
                        result: ActionResult(success: true, method: .activate, accessibilityTrace: trace)
                    ),
                ],
                durationMs: 8
            )
        )

        let json = publicJSONObject(response)
        let report = try XCTUnwrap(json["report"] as? [String: Any])
        let nodes = try XCTUnwrap(report["nodes"] as? [[String: Any]])
        let action = try XCTUnwrap(nodes.first?["action"] as? [String: Any])
        let actionResult = try XCTUnwrap(action["result"] as? [String: Any])
        let delta = try XCTUnwrap(actionResult["delta"] as? [String: Any])
        let screen = try XCTUnwrap(delta["screen"] as? [String: Any])
        let elements = try XCTUnwrap(screen["elements"] as? [[String: Any]])
        let encoded = String(data: try response.jsonData(), encoding: .utf8) ?? ""

        XCTAssertEqual(delta["kind"] as? String, "screenChanged")
        XCTAssertNil(delta["newInterface"])
        XCTAssertEqual(actionResult["screenId"] as? String, "checkout")
        XCTAssertEqual(screen["elementCount"] as? Int, 8)
        XCTAssertEqual(elements.count, 5)
        XCTAssertEqual(elements.last?["label"] as? String, "Checkout Row 4")
        XCTAssertEqual(screen["omittedElementCount"] as? Int, 3)
        XCTAssertFalse(encoded.contains(#""tree""#), encoded)
        XCTAssertFalse(encoded.contains(#""captures""#), encoded)
    }

    func testFailedHeistActionCompactOutputIncludesConcreteElementDeltaEvidence() throws {
        let unchanged = (0..<3).map { index in
            makeReceiptTestElement(label: "Row \(index)", identifier: "row_\(index)")
        }
        let lazyRow = makeReceiptTestElement(
            label: "Lazy Row",
            value: "Loaded by scroll",
            identifier: "lazy_row",
            traits: [.staticText]
        )
        let trace = makeReceiptTestTrace(
            before: makeReceiptTestInterface(unchanged),
            after: makeReceiptTestInterface(unchanged + [lazyRow])
        )
        let command = HeistActionCommand.activate(.target(.predicate(ElementPredicate(label: "Load More"))))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let result = HeistExecutionResult(
            steps: [
                actionReceiptStep(
                    command: command,
                    result: ActionResult(
                        success: false,
                        method: .activate,
                        message: "target stopped responding",
                        errorKind: .actionFailed,
                        accessibilityTrace: trace
                    ),
                    failure: HeistFailureDetail(
                        category: .action,
                        contract: "activate command succeeds",
                        observed: "target stopped responding"
                    )
                ),
            ],
            durationMs: 8,
            abortedAtPath: "$.body[0]"
        )

        let compact = FenceResponse.heistExecution(plan: plan, result: result).compactFormatted()

        XCTAssertTrue(compact.contains("-> error: target stopped responding"), compact)
        XCTAssertTrue(compact.contains("evidence: elements changed"), compact)
        XCTAssertTrue(compact.contains(#"+ "Lazy Row":"Loaded by scroll" staticText id="lazy_row""#), compact)
    }

    func testExpectationSuccessStaysSuccessfulAcrossPublicFormats() {
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult(success: true, method: .activate),
            expectation: ExpectationResult(
                met: true,
                predicate: .state(.present(ElementPredicate(label: "Done"))),
                actual: "matched"
            )
        )

        let json = publicJSONObject(response)
        let expectation = json["expectation"] as? [String: Any]

        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertEqual(expectation?["met"] as? Bool, true)
        XCTAssertEqual(response.compactFormatted(), "activate: ok")
        XCTAssertTrue(response.humanFormatted().contains("[expectation met]"))
        XCTAssertFalse(response.isFailure)
    }

    func testHumanHeistFormattingCountsNestedProjectedExpectations() throws {
        let expected = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let childAction = try HeistStep.action(ActionStep(
            command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Submit"))))),
            expectation: WaitStep(predicate: expected, timeout: 1)
        ))
        let casePredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Home")))
        let conditional = try ConditionalStep(cases: [
            PredicateCase(predicate: casePredicate, body: [childAction]),
        ])
        let plan = try HeistPlan(body: [.conditional(conditional)])
        let childResult = actionReceiptStep(
            path: "$.body[0].conditional.cases[0].body[0]",
            result: ActionResult(success: true, method: .activate),
            expectation: ExpectationResult(met: true, predicate: expected)
        )
        let result = HeistExecutionResult(steps: [
                caseReceiptStep(
                    kind: .conditional,
                    status: .passed,
                    selection: HeistCaseSelectionResult(
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
            durationMs: 1
        )

        let output = FenceResponse.heistExecution(plan: plan, result: result).humanFormatted()

        XCTAssertTrue(output.contains("[expectations: 1/1 met]"), output)
    }

    func testHeistExpectationCountsAgreeAcrossPublicFormats() throws {
        let expected = AccessibilityPredicate.state(.present(ElementPredicate(label: "Done")))
        let action = try HeistStep.action(ActionStep(
            command: .activate(.target(.predicate(ElementPredicate(label: "Submit")))),
            expectation: WaitStep(predicate: expected, timeout: 1)
        ))
        let plan = try HeistPlan(body: [
            .warn(WarnStep(message: "starting checkout")),
            action,
        ])
        let result = HeistExecutionResult(
            steps: [
                warnReceiptStep(path: "$.body[0]", message: "starting checkout"),
                actionReceiptStep(
                    path: "$.body[1]",
                    command: .activate(.target(.predicate(ElementPredicate(label: "Submit")))),
                    result: ActionResult(success: true, method: .activate),
                    expectationActionResult: ActionResult(success: true, method: .wait),
                    expectation: ExpectationResult(met: true, predicate: expected, actual: "matched")
                ),
            ],
            durationMs: 5
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

        let json = publicJSONObject(response)
        let expectations = json["expectations"] as? [String: Any]
        let report = json["report"] as? [String: Any]
        let summary = report?["summary"] as? [String: Any]
        let reportExpectations = summary?["expectations"] as? [String: Any]

        XCTAssertEqual(json["executedTopLevelStepCount"] as? Int, 2)
        XCTAssertEqual(json["executedNodeCount"] as? Int, 2)
        XCTAssertEqual(json["outputReceiptNodeCount"] as? Int, 2)
        XCTAssertEqual(summary?["executedTopLevelStepCount"] as? Int, 2)
        XCTAssertEqual(summary?["executedNodeCount"] as? Int, 2)
        XCTAssertEqual(summary?["outputReceiptNodeCount"] as? Int, 2)
        XCTAssertEqual(expectations?["checked"] as? Int, 1)
        XCTAssertEqual(expectations?["met"] as? Int, 1)
        XCTAssertEqual(reportExpectations?["checked"] as? Int, 1)
        XCTAssertEqual(reportExpectations?["met"] as? Int, 1)
        XCTAssertTrue(response.compactFormatted().contains("heist: 2 top-level steps in 5ms"))
        XCTAssertTrue(response.compactFormatted().contains("[expectations: 1/1]"))
        XCTAssertTrue(response.humanFormatted().contains("Heist: 2 top-level step(s) executed in 5ms"))
        XCTAssertTrue(response.humanFormatted().contains("[expectations: 1/1 met]"))
    }

    func testExplicitSingleActionHeistKeepsReportShapeAcrossPublicFormats() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Pay")))))),
        ])
        let result = HeistExecutionResult(
            steps: [
                actionReceiptStep(
                    command: .activate(.target(.predicate(ElementPredicate(label: "Pay")))),
                    result: ActionResult(success: true, method: .activate)
                ),
            ],
            durationMs: 3
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

        let json = publicJSONObject(response)
        let compact = response.compactFormatted()

        XCTAssertEqual(json["status"] as? String, "ok")
        XCTAssertNotNil(json["report"])
        XCTAssertNil(json["method"])
        XCTAssertTrue(compact.contains("heist: 1 top-level steps in 3ms"), compact)
        XCTAssertTrue(compact.contains("[0] activate"), compact)
    }

    func testCompactHeistFormattingReportsFailStepMessage() throws {
        let plan = try HeistPlan(body: [.fail(FailStep(message: "Unknown screen"))])
        let result = HeistExecutionResult(
            steps: [
                failReceiptStep(message: "Unknown screen"),
            ],
            durationMs: 1,
            abortedAtPath: "$.body[0]"
        )

        let output = FenceResponse.heistExecution(plan: plan, result: result).compactFormatted()

        XCTAssertTrue(output.contains("[0] fail -> error: Unknown screen"), output)
    }

    func testPublicHeistJSONReportsFailStepMessage() throws {
        let plan = try HeistPlan(body: [.fail(FailStep(message: "Unknown screen"))])
        let result = HeistExecutionResult(
            steps: [
                failReceiptStep(message: "Unknown screen"),
            ],
            durationMs: 1,
            abortedAtPath: "$.body[0]"
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

    func testAbortedHeistOutputCountsOnlyReceiptNodes() throws {
        let plan = try HeistPlan(body: [
            .warn(WarnStep(message: "before")),
            .fail(FailStep(message: "stop")),
            .warn(WarnStep(message: "after")),
        ])
        let result = HeistExecutionResult(
            steps: [
                warnReceiptStep(path: "$.body[0]", message: "before"),
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
                    kind: .warn,
                    status: .skipped,
                    durationMs: 0
                ),
            ],
            durationMs: 2,
            abortedAtPath: "$.body[1]"
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

        let json = publicJSONObject(response)
        let report = try XCTUnwrap(json["report"] as? [String: Any])
        let summary = try XCTUnwrap(report["summary"] as? [String: Any])
        let nodes = try XCTUnwrap(report["nodes"] as? [[String: Any]])
        let compact = response.compactFormatted()

        XCTAssertEqual(json["executedTopLevelStepCount"] as? Int, 2)
        XCTAssertEqual(json["executedNodeCount"] as? Int, 2)
        XCTAssertEqual(json["outputReceiptNodeCount"] as? Int, 3)
        XCTAssertEqual(summary["executedTopLevelStepCount"] as? Int, 2)
        XCTAssertEqual(summary["executedNodeCount"] as? Int, 2)
        XCTAssertEqual(summary["outputReceiptNodeCount"] as? Int, 3)
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(nodes.map { $0["path"] as? String }, ["$.body[0]", "$.body[1]", "$.body[2]"])
        XCTAssertEqual(nodes.map { $0["status"] as? String }, ["passed", "failed", "skipped"])
        XCTAssertTrue(compact.contains("heist: 2 top-level steps"), compact)
        XCTAssertTrue(compact.contains("[0] warn -> warning: before"), compact)
        XCTAssertTrue(compact.contains("[2] warn -> skipped"), compact)
        XCTAssertFalse(compact.contains("after"), compact)
        XCTAssertTrue(
            response.humanFormatted().contains("Heist: 2 top-level step(s) executed"),
            response.humanFormatted()
        )
    }

    func testPublicHeistJSONReportsNestedSelectedCaseFailureAsTreeNodes() throws {
        let childAction = try HeistStep.action(ActionStep(
            command: .activate(.target(.predicate(ElementPredicate(label: "Continue"))))
        ))
        let casePredicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Ready")))
        let conditional = try ConditionalStep(cases: [
            PredicateCase(predicate: casePredicate, body: [childAction]),
        ])
        let plan = try HeistPlan(body: [.conditional(conditional)])
        let childPath = "$.body[0].conditional.cases[0].body[0]"
        let childResult = actionReceiptStep(
            path: childPath,
            command: .activate(.target(.predicate(ElementPredicate(label: "Continue")))),
            result: ActionResult(
                success: false,
                method: .activate,
                message: "nested button failed",
                errorKind: .actionFailed
            ),
            failure: HeistFailureDetail(
                category: .action,
                contract: "activate command succeeds",
                observed: "nested button failed"
            )
        )
        let result = HeistExecutionResult(
            steps: [
                caseReceiptStep(
                    kind: .conditional,
                    status: .failed,
                    selection: HeistCaseSelectionResult(
                        cases: [
                            HeistCaseMatchResult(
                                predicate: casePredicate,
                                result: ExpectationResult(met: true, predicate: casePredicate)
                            ),
                        ],
                        selectedCaseIndex: 0,
                        elapsedMs: 1
                    ),
                    failure: HeistFailureDetail(
                        category: .invocation,
                        contract: "selected case completes without failure",
                        observed: "child failed at \(childPath)"
                    ),
                    children: [childResult]
                ),
            ],
            durationMs: 9,
            abortedAtPath: childPath
        )

        let json = publicJSONObject(.heistExecution(plan: plan, result: result))
        let report = try XCTUnwrap(json["report"] as? [String: Any])
        let nodes = try XCTUnwrap(report["nodes"] as? [[String: Any]])
        let root = try XCTUnwrap(nodes.first)
        let children = try XCTUnwrap(root["children"] as? [[String: Any]])
        let child = try XCTUnwrap(children.first)
        let evidence = try XCTUnwrap(root["evidence"] as? [String: Any])
        let action = try XCTUnwrap(child["action"] as? [String: Any])
        let actionResult = try XCTUnwrap(action["result"] as? [String: Any])

        XCTAssertNil(json["results"])
        XCTAssertEqual(root["path"] as? String, "$.body[0]")
        XCTAssertEqual(root["kind"] as? String, "if")
        XCTAssertNotNil(evidence["caseSelection"])
        XCTAssertEqual(root["abortedAtChildPath"] as? String, childPath)
        XCTAssertEqual(child["path"] as? String, "$.body[0].conditional.cases[0].body[0]")
        XCTAssertEqual(child["kind"] as? String, "action")
        XCTAssertEqual(child["status"] as? String, "failed")
        XCTAssertEqual(action["commandName"] as? String, "activate")
        XCTAssertEqual(actionResult["status"] as? String, "error")
        XCTAssertEqual(actionResult["message"] as? String, "nested button failed")
    }

    func testPublicHeistJSONReportsSelectedElsePathAsTreeNodes() throws {
        let elseStep = try HeistStep.action(ActionStep(
            command: .activate(.target(.predicate(ElementPredicate(label: "Fallback"))))
        ))
        let predicate = AccessibilityPredicate.state(.present(ElementPredicate(label: "Home")))
        let conditional = try ConditionalStep(
            cases: [
                PredicateCase(
                    predicate: predicate,
                    body: [try HeistStep.action(ActionStep(command: .activate(.target(.predicate(ElementPredicate(label: "Home"))))))]
                ),
            ],
            elseBody: [elseStep]
        )
        let plan = try HeistPlan(body: [.conditional(conditional)])
        let childPath = "$.body[0].conditional.else_body[0]"
        let childResult = actionReceiptStep(
            path: childPath,
            command: .activate(.target(.predicate(ElementPredicate(label: "Fallback")))),
            result: ActionResult(success: true, method: .activate)
        )
        let result = HeistExecutionResult(
            steps: [
                caseReceiptStep(
                    kind: .conditional,
                    status: .passed,
                    selection: HeistCaseSelectionResult(
                        cases: [
                            HeistCaseMatchResult(
                                predicate: predicate,
                                result: ExpectationResult(met: false, predicate: predicate)
                            ),
                        ],
                        selectedCaseIndex: nil,
                        elapsedMs: 1,
                        elseRan: true
                    ),
                    children: [childResult]
                ),
            ],
            durationMs: 3
        )

        let json = publicJSONObject(.heistExecution(plan: plan, result: result))
        let report = try XCTUnwrap(json["report"] as? [String: Any])
        let nodes = try XCTUnwrap(report["nodes"] as? [[String: Any]])
        let root = try XCTUnwrap(nodes.first)
        let evidence = try XCTUnwrap(root["evidence"] as? [String: Any])
        let children = try XCTUnwrap(root["children"] as? [[String: Any]])
        let compact = FenceResponse.heistExecution(plan: plan, result: result).compactFormatted()

        XCTAssertEqual(root["kind"] as? String, "if")
        XCTAssertEqual(root["status"] as? String, "passed")
        XCTAssertNotNil(evidence["caseSelection"])
        XCTAssertEqual(children.first?["path"] as? String, "$.body[0].conditional.else_body[0]")
        XCTAssertTrue(compact.contains("[0] if"), compact)
        XCTAssertTrue(compact.contains("[1] activate"), compact)
    }

    func testPublicHeistOutputReportsForEachStructurally() throws {
        let forEach = try ForEachStringStep(
            values: ["Milk", "Eggs"],
            parameter: "item",
            body: [try HeistStep.action(ActionStep(command: .typeText(text: .ref("item"), target: nil)))]
        )
        let plan = try HeistPlan(body: [.forEachString(forEach)])
        let firstIteration = forEachStringIterationReceiptStep(
            ordinal: 0,
            value: "Milk",
            status: .passed,
            children: [
                actionReceiptStep(
                    path: "$.body[0].for_each_string.iterations[0].body[0]",
                    command: .typeText(text: .ref("item"), target: nil),
                    result: ActionResult(success: true, method: .typeText)
                ),
            ]
        )
        let failedActionPath = "$.body[0].for_each_string.iterations[1].body[0]"
        let failedAction = actionReceiptStep(
            path: failedActionPath,
            command: .typeText(text: .ref("item"), target: nil),
            result: ActionResult(
                success: false,
                method: .typeText,
                message: "field missing",
                errorKind: .elementNotFound
            ),
            failure: HeistFailureDetail(
                category: .action,
                contract: "type_text command succeeds",
                observed: "field missing"
            )
        )
        let secondIteration = forEachStringIterationReceiptStep(
            ordinal: 1,
            value: "Eggs",
            status: .failed,
            failureReason: "iteration 1 failed for value \"Eggs\"",
            children: [failedAction]
        )
        let result = HeistExecutionResult(
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
                        contract: "for_each_string completes all 2 value(s)",
                        observed: "for_each_string stopped after 2 of 2 iteration(s): iteration 1 failed for value \"Eggs\""
                    ),
                    abortedAtChildPath: failedActionPath,
                    children: [firstIteration, secondIteration]
                ),
            ],
            durationMs: 30,
            abortedAtPath: failedActionPath
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

        let json = publicJSONObject(response)
        let report = try XCTUnwrap(json["report"] as? [String: Any])
        let summary = try XCTUnwrap(report["summary"] as? [String: Any])
        let nodes = try XCTUnwrap(report["nodes"] as? [[String: Any]])
        let root = try XCTUnwrap(nodes.first)
        let evidence = try XCTUnwrap(root["evidence"] as? [String: Any])
        let children = try XCTUnwrap(root["children"] as? [[String: Any]])
        let compact = response.compactFormatted()

        XCTAssertEqual(json["executedTopLevelStepCount"] as? Int, 1)
        XCTAssertEqual(json["executedNodeCount"] as? Int, 5)
        XCTAssertEqual(json["outputReceiptNodeCount"] as? Int, 5)
        XCTAssertEqual(summary["executedTopLevelStepCount"] as? Int, 1)
        XCTAssertEqual(summary["executedNodeCount"] as? Int, 5)
        XCTAssertEqual(summary["outputReceiptNodeCount"] as? Int, 5)
        XCTAssertEqual(root["kind"] as? String, "for_each_string")
        XCTAssertNotNil(evidence["forEachString"])
        XCTAssertEqual(root["abortedAtChildPath"] as? String, failedActionPath)
        XCTAssertEqual(children.map { $0["kind"] as? String }, ["for_each_iteration", "for_each_iteration"])
        XCTAssertTrue(compact.contains("heist: 1 top-level steps in 30ms"), compact)
        XCTAssertTrue(compact.contains("[0] for_each_string -> error: for_each_string stopped"), compact)
    }

    func testCompactInterfaceRendersNestedContainersAndElements() {
        let output = FenceResponse.compactInterface(formattingFixtureInterface(), detail: .summary)

        XCTAssertEqual(output, """
        4 elements
        group label="Actions" id="actions" containerName="semantic_actions__actions"
          [0] "Submit" button
          table rows=3 columns=4 containerName="orders_table"
            [1] "Order ID" staticText
          tab_bar containerName="main_tabs"
            [2] "Home" tabBarItem
        scrollable containerName="main_scroll" viewport=390x400 content=390x1200 scrollAxis=vertical pageScrollsY=3 observedElementCount=1 modal=true
          [3] "Bottom" staticText
        """)
        XCTAssertFalse(output.contains("<"), output)
        XCTAssertFalse(output.contains("semanticGroup"), output)
        XCTAssertFalse(output.contains("dataTable"), output)
        XCTAssertFalse(output.contains("tabBar containerName"), output)
        XCTAssertFalse(output.contains("stableId"), output)
    }

    func testCompactInterfaceRendersHorizontalAndBothAxisScrollSummaries() {
        let horizontal = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestScrollableContainer(
                    contentWidth: 1200,
                    contentHeight: 400,
                    frameWidth: 390,
                    frameHeight: 400
                ),
                containerName: "horizontal_scroll",
                children: [.element(makeReceiptTestElement(label: "Right"))]
            ),
        ])
        let both = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestScrollableContainer(
                    contentWidth: 1200,
                    contentHeight: 1200,
                    frameWidth: 390,
                    frameHeight: 400
                ),
                containerName: "both_axis_scroll",
                children: [.element(makeReceiptTestElement(label: "Corner"))]
            ),
        ])

        let horizontalOutput = FenceResponse.compactInterface(horizontal, detail: .summary)
        let bothOutput = FenceResponse.compactInterface(both, detail: .summary)
        let expectedHorizontalSummary =
            #"scrollable containerName="horizontal_scroll" viewport=390x400 content=1200x400 "# +
            #"scrollAxis=horizontal pageScrollsX=3 observedElementCount=1"#
        let expectedBothSummary =
            #"scrollable containerName="both_axis_scroll" viewport=390x400 content=1200x1200 "# +
            #"scrollAxis=both pageScrollsX=3 pageScrollsY=3 observedElementCount=1"#

        XCTAssertTrue(
            horizontalOutput.contains(expectedHorizontalSummary),
            horizontalOutput
        )
        XCTAssertFalse(horizontalOutput.contains("pageScrollsY"), horizontalOutput)
        XCTAssertTrue(
            bothOutput.contains(expectedBothSummary),
            bothOutput
        )
    }

    func testCompactInterfaceTruncatesScrollableSubtreeAtVisibleElementBudget() {
        let rows = (0..<4).map { index in
            ReceiptTestInterfaceNode.element(makeReceiptTestElement(label: "Row \(index)"))
        }
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestScrollableContainer(
                    contentWidth: 390,
                    contentHeight: 1200,
                    frameWidth: 390,
                    frameHeight: 400
                ),
                containerName: "long_scroll",
                children: rows
            ),
            .element(makeReceiptTestElement(label: "After")),
        ])

        let output = FenceResponse.compactInterface(
            interface,
            detail: .summary,
            visibleElementBudget: 2
        )

        XCTAssertEqual(output, """
        5 elements
        scrollable containerName="long_scroll" viewport=390x400 content=390x1200 scrollAxis=vertical pageScrollsY=3 observedElementCount=4
          [0] "Row 0" staticText
          [1] "Row 1" staticText
          ... subtree truncated: omitted 2 observed elements (visibleElementBudget=2)
        [4] "After" staticText
        """)
    }

    func testCompactInterfaceTruncatesWholeInterfaceAtTotalNodeBudget() {
        let rows = (0..<4).map { index in
            ReceiptTestInterfaceNode.element(makeReceiptTestElement(label: "Row \(index)"))
        }
        let interface = makeReceiptTestInterface(nodes: rows)

        let output = FenceResponse.compactInterface(
            interface,
            detail: .summary,
            visibleElementBudget: 10,
            totalNodeBudget: 2
        )

        XCTAssertEqual(output, """
        4 elements
        [0] "Row 0" staticText
        [1] "Row 1" staticText
        ... interface truncated: omitted 2 observed elements (totalNodeBudget=2)
        """)
    }

    func testCompactInterfaceDoesNotReportScrollBudgetWhenTotalNodeBudgetStopsFirst() {
        let rows = (0..<4).map { index in
            ReceiptTestInterfaceNode.element(makeReceiptTestElement(label: "Row \(index)"))
        }
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestScrollableContainer(
                    contentWidth: 390,
                    contentHeight: 1_200,
                    frameWidth: 390,
                    frameHeight: 400
                ),
                containerName: "long_scroll",
                children: rows
            ),
        ])

        let output = FenceResponse.compactInterface(
            interface,
            detail: .summary,
            visibleElementBudget: 3,
            totalNodeBudget: 2
        )

        XCTAssertFalse(output.contains("subtree truncated"), output)
        XCTAssertTrue(
            output.contains("... interface truncated: omitted 3 observed elements (totalNodeBudget=2)"),
            output
        )
    }

    func testCompactInterfaceTotalNodeBudgetCountsContainers() {
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestSemanticContainer(label: "Outer"),
                containerName: "outer",
                children: [
                    .container(
                        makeReceiptTestSemanticContainer(label: "Empty"),
                        containerName: "empty",
                        children: []
                    ),
                    .element(makeReceiptTestElement(label: "After")),
                ]
            ),
        ])

        let output = FenceResponse.compactInterface(
            interface,
            detail: .summary,
            totalNodeBudget: 2
        )

        XCTAssertEqual(output, """
        1 elements
        group label="Outer" containerName="outer"
          group label="Empty" containerName="empty"
        ... interface truncated: omitted 1 observed elements (totalNodeBudget=2)
        """)
    }

    func testCompactInterfaceNestedScrollCannotResetParentVisibleElementBudget() {
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestScrollableContainer(
                    contentWidth: 390,
                    contentHeight: 2_000,
                    frameWidth: 390,
                    frameHeight: 400
                ),
                containerName: "outer_scroll",
                children: [
                    .element(makeReceiptTestElement(label: "Row 0")),
                    .container(
                        makeReceiptTestScrollableContainer(
                            contentWidth: 390,
                            contentHeight: 1_200,
                            frameWidth: 390,
                            frameHeight: 400
                        ),
                        containerName: "inner_scroll",
                        children: [
                            .element(makeReceiptTestElement(label: "Row 1")),
                            .element(makeReceiptTestElement(label: "Row 2")),
                            .element(makeReceiptTestElement(label: "Row 3")),
                        ]
                    ),
                    .element(makeReceiptTestElement(label: "Row 4")),
                ]
            ),
        ])

        let output = FenceResponse.compactInterface(
            interface,
            detail: .summary,
            visibleElementBudget: 2
        )

        XCTAssertTrue(output.contains(#"[0] "Row 0" staticText"#), output)
        XCTAssertTrue(output.contains(#"[1] "Row 1" staticText"#), output)
        XCTAssertFalse(output.contains("Row 2"), output)
        XCTAssertFalse(output.contains("Row 3"), output)
        XCTAssertFalse(output.contains("Row 4"), output)
        XCTAssertTrue(
            output.contains(
                "... subtree truncated: omitted 3 observed elements (visibleElementBudget=2)"
            ),
            output
        )
    }

    func testPublicInterfaceJSONRendersScrollSummaryFields() throws {
        let response = FenceResponse.interface(formattingFixtureInterface(), detail: .summary)

        let json = publicJSONObject(response)
        let interface = try XCTUnwrap(json["interface"] as? [String: Any])
        let snapshotQuality = try XCTUnwrap(interface["snapshotQuality"] as? [String: Any])
        let tree = try XCTUnwrap(interface["tree"] as? [[String: Any]])
        let scrollContainer = try XCTUnwrap(tree[1]["container"] as? [String: Any])

        XCTAssertEqual(snapshotQuality["state"] as? String, "full")
        XCTAssertNil(snapshotQuality["reasonCode"])
        XCTAssertEqual((snapshotQuality["observedElementCount"] as? NSNumber)?.intValue, 4)
        XCTAssertEqual((snapshotQuality["renderedElementCount"] as? NSNumber)?.intValue, 4)
        XCTAssertEqual((snapshotQuality["omittedElementCount"] as? NSNumber)?.intValue, 0)
        XCTAssertNil(snapshotQuality["visibleElementBudget"])
        XCTAssertNil(snapshotQuality["totalNodeBudget"])
        XCTAssertEqual(scrollContainer["type"] as? String, "scrollable")
        XCTAssertEqual((scrollContainer["contentWidth"] as? NSNumber)?.doubleValue, 390)
        XCTAssertEqual((scrollContainer["contentHeight"] as? NSNumber)?.doubleValue, 1200)
        XCTAssertEqual(scrollContainer["scrollAxis"] as? String, "vertical")
        XCTAssertNil(scrollContainer["pageScrollsX"])
        XCTAssertEqual((scrollContainer["pageScrollsY"] as? NSNumber)?.intValue, 3)
        XCTAssertEqual((scrollContainer["observedElementCount"] as? NSNumber)?.intValue, 1)
        XCTAssertNil(scrollContainer["truncation"])
    }

    func testPublicInterfaceOutputIncludesDiscoveryLimitDiagnostics() throws {
        let diagnostics = InterfaceDiagnostics(discovery: InterfaceDiscoveryDiagnostics(
            state: "limited",
            reasonCodes: ["scroll-attempt-budget"],
            includedElementCount: 2,
            scrollAttempts: 5,
            maxScrollsPerDiscovery: 5,
            maxScrollsPerContainer: 3,
            exploredScrollableContainerCount: 1,
            omittedScrollableContainerCount: 1,
            omittedContainers: [
                InterfaceDiscoveryOmittedContainer(
                    containerName: "main_scroll",
                    type: "scrollable",
                    reasonCodes: ["scroll-attempt-budget"],
                    scrollAxis: .vertical,
                    viewportWidth: 390,
                    viewportHeight: 400,
                    contentWidth: 390,
                    contentHeight: 1_200
                ),
            ],
            nextAction: "Retry get_interface with a higher maxScrollsPerDiscovery."
        ))
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestScrollableContainer(
                    contentWidth: 390,
                    contentHeight: 1_200,
                    frameWidth: 390,
                    frameHeight: 400
                ),
                containerName: "main_scroll",
                children: [
                    .element(makeReceiptTestElement(label: "Top")),
                    .element(makeReceiptTestElement(label: "Bottom")),
                ]
            ),
        ]).withDiagnostics(diagnostics)

        let compact = FenceResponse.compactInterface(interface, detail: .summary)
        let json = try publicInterfaceJSONObject(PublicInterface(interface: interface, detail: .summary))
        let encodedDiagnostics = try XCTUnwrap(json["diagnostics"] as? [String: Any])
        let discovery = try XCTUnwrap(encodedDiagnostics["discovery"] as? [String: Any])
        let omittedContainers = try XCTUnwrap(discovery["omittedContainers"] as? [[String: Any]])
        let omitted = try XCTUnwrap(omittedContainers.first)

        XCTAssertTrue(
            compact.contains(
                "discovery: limited[scroll-attempt-budget] includedElements=2 scrollAttempts=5/5"
            ),
            compact
        )
        XCTAssertTrue(compact.contains(#"omitted: scrollable containerName="main_scroll""#), compact)
        XCTAssertTrue(compact.contains("next: Retry get_interface"), compact)
        XCTAssertEqual(discovery["state"] as? String, "limited")
        XCTAssertEqual(discovery["reasonCodes"] as? [String], ["scroll-attempt-budget"])
        XCTAssertEqual((discovery["includedElementCount"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((discovery["scrollAttempts"] as? NSNumber)?.intValue, 5)
        XCTAssertEqual((discovery["maxScrollsPerDiscovery"] as? NSNumber)?.intValue, 5)
        XCTAssertEqual((discovery["maxScrollsPerContainer"] as? NSNumber)?.intValue, 3)
        XCTAssertEqual((discovery["omittedScrollableContainerCount"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(omitted["containerName"] as? String, "main_scroll")
        XCTAssertEqual(omitted["scrollAxis"] as? String, "vertical")
        XCTAssertEqual(omitted["reasonCodes"] as? [String], ["scroll-attempt-budget"])
    }

    func testPublicInterfaceJSONTruncatesScrollableSubtreeAtVisibleElementBudget() throws {
        let rows = (0..<4).map { index in
            ReceiptTestInterfaceNode.element(makeReceiptTestElement(label: "Row \(index)"))
        }
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestScrollableContainer(
                    contentWidth: 390,
                    contentHeight: 1_200,
                    frameWidth: 390,
                    frameHeight: 400
                ),
                containerName: "long_scroll",
                children: rows
            ),
            .element(makeReceiptTestElement(label: "After")),
        ])

        let json = try publicInterfaceJSONObject(
            PublicInterface(interface: interface, detail: .summary, visibleElementBudget: 2)
        )
        let snapshotQuality = try XCTUnwrap(json["snapshotQuality"] as? [String: Any])
        let tree = try XCTUnwrap(json["tree"] as? [[String: Any]])
        let scrollContainer = try XCTUnwrap(tree[0]["container"] as? [String: Any])
        let scrollChildren = try XCTUnwrap(scrollContainer["children"] as? [[String: Any]])
        let truncation = try XCTUnwrap(scrollContainer["truncation"] as? [String: Any])
        let after = try XCTUnwrap(tree[1]["element"] as? [String: Any])

        XCTAssertEqual(snapshotQuality["state"] as? String, "truncated")
        XCTAssertEqual(snapshotQuality["reasonCode"] as? String, "scroll-subtree-element-budget")
        XCTAssertEqual((snapshotQuality["observedElementCount"] as? NSNumber)?.intValue, 5)
        XCTAssertEqual((snapshotQuality["renderedElementCount"] as? NSNumber)?.intValue, 3)
        XCTAssertEqual((snapshotQuality["omittedElementCount"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((snapshotQuality["visibleElementBudget"] as? NSNumber)?.intValue, 2)
        XCTAssertNil(snapshotQuality["totalNodeBudget"])
        XCTAssertEqual(scrollChildren.count, 2)
        XCTAssertEqual((scrollContainer["observedElementCount"] as? NSNumber)?.intValue, 4)
        XCTAssertEqual(truncation["state"] as? String, "truncated")
        XCTAssertEqual(truncation["reasonCode"] as? String, "scroll-subtree-element-budget")
        XCTAssertEqual((truncation["observedElementCount"] as? NSNumber)?.intValue, 4)
        XCTAssertEqual((truncation["renderedElementCount"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((truncation["omittedElementCount"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((truncation["visibleElementBudget"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(after["label"] as? String, "After")
        XCTAssertEqual((after["order"] as? NSNumber)?.intValue, 4)
    }

    func testPublicInterfaceJSONTruncatesWholeInterfaceAtTotalNodeBudget() throws {
        let rows = (0..<4).map { index in
            ReceiptTestInterfaceNode.element(makeReceiptTestElement(label: "Row \(index)"))
        }
        let interface = makeReceiptTestInterface(nodes: rows)

        let json = try publicInterfaceJSONObject(
            PublicInterface(
                interface: interface,
                detail: .summary,
                visibleElementBudget: 10,
                totalNodeBudget: 2
            )
        )
        let snapshotQuality = try XCTUnwrap(json["snapshotQuality"] as? [String: Any])
        let tree = try XCTUnwrap(json["tree"] as? [[String: Any]])

        XCTAssertEqual(snapshotQuality["state"] as? String, "truncated")
        XCTAssertEqual(snapshotQuality["reasonCode"] as? String, "total-node-budget")
        XCTAssertEqual((snapshotQuality["observedElementCount"] as? NSNumber)?.intValue, 4)
        XCTAssertEqual((snapshotQuality["renderedElementCount"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual((snapshotQuality["omittedElementCount"] as? NSNumber)?.intValue, 2)
        XCTAssertNil(snapshotQuality["visibleElementBudget"])
        XCTAssertEqual((snapshotQuality["totalNodeBudget"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(tree.count, 2)
    }

    func testPublicInterfaceJSONTotalNodeBudgetCountsContainers() throws {
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestSemanticContainer(label: "Outer"),
                containerName: "outer",
                children: [
                    .container(
                        makeReceiptTestSemanticContainer(label: "Empty"),
                        containerName: "empty",
                        children: []
                    ),
                    .element(makeReceiptTestElement(label: "After")),
                ]
            ),
        ])

        let json = try publicInterfaceJSONObject(
            PublicInterface(
                interface: interface,
                detail: .summary,
                totalNodeBudget: 2
            )
        )
        let snapshotQuality = try XCTUnwrap(json["snapshotQuality"] as? [String: Any])
        let tree = try XCTUnwrap(json["tree"] as? [[String: Any]])
        let outer = try XCTUnwrap(tree[0]["container"] as? [String: Any])
        let children = try XCTUnwrap(outer["children"] as? [[String: Any]])
        let empty = try XCTUnwrap(children[0]["container"] as? [String: Any])

        XCTAssertEqual(snapshotQuality["state"] as? String, "truncated")
        XCTAssertEqual(snapshotQuality["reasonCode"] as? String, "total-node-budget")
        XCTAssertEqual((snapshotQuality["observedElementCount"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((snapshotQuality["renderedElementCount"] as? NSNumber)?.intValue, 0)
        XCTAssertEqual((snapshotQuality["omittedElementCount"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((snapshotQuality["totalNodeBudget"] as? NSNumber)?.intValue, 2)
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(outer["containerName"] as? String, "outer")
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(empty["containerName"] as? String, "empty")
    }

    func testPublicInterfaceJSONDoesNotReportScrollBudgetWhenTotalNodeBudgetStopsFirst() throws {
        let rows = (0..<4).map { index in
            ReceiptTestInterfaceNode.element(makeReceiptTestElement(label: "Row \(index)"))
        }
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestScrollableContainer(
                    contentWidth: 390,
                    contentHeight: 1_200,
                    frameWidth: 390,
                    frameHeight: 400
                ),
                containerName: "long_scroll",
                children: rows
            ),
        ])

        let json = try publicInterfaceJSONObject(
            PublicInterface(
                interface: interface,
                detail: .summary,
                visibleElementBudget: 3,
                totalNodeBudget: 2
            )
        )
        let snapshotQuality = try XCTUnwrap(json["snapshotQuality"] as? [String: Any])
        let tree = try XCTUnwrap(json["tree"] as? [[String: Any]])
        let scrollContainer = try XCTUnwrap(tree[0]["container"] as? [String: Any])

        XCTAssertEqual(snapshotQuality["reasonCode"] as? String, "total-node-budget")
        XCTAssertNil(snapshotQuality["visibleElementBudget"])
        XCTAssertEqual((snapshotQuality["totalNodeBudget"] as? NSNumber)?.intValue, 2)
        XCTAssertNil(scrollContainer["truncation"])
    }

    func testCompactContainerEscapesLabelsAndContainerNames() {
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestSemanticContainer(
                    label: "Actions \"Primary\"\nPane",
                    value: "hot\u{0001}",
                    identifier: "actions\"id"
                ),
                containerName: "semantic\n\"actions",
                children: [
                    .element(makeReceiptTestElement(label: "Submit")),
                ]
            ),
        ])

        let output = FenceResponse.compactInterface(interface, detail: .summary)

        XCTAssertTrue(output.contains(#"label="Actions \"Primary\"\nPane""#), output)
        XCTAssertTrue(output.contains(#"value="hot\u0001""#), output)
        XCTAssertTrue(output.contains(#"id="actions\"id""#), output)
        XCTAssertTrue(output.contains(#"containerName="semantic\n\"actions""#), output)
        XCTAssertFalse(output.contains("stableId"), output)
    }

    func testCompactSummaryOmitsContainerGeometryAndFullIncludesFrame() {
        let interface = formattingFixtureInterface()

        let summary = FenceResponse.compactInterface(interface, detail: .summary)
        let full = FenceResponse.compactInterface(interface, detail: .full)

        XCTAssertFalse(summary.contains("frame="), summary)
        XCTAssertTrue(
            full.contains(#"group label="Actions" id="actions" containerName="semantic_actions__actions" frame=(0,40,200,100)"#),
            full
        )
        XCTAssertTrue(summary.contains(#"scrollable containerName="main_scroll" viewport=390x400 content=390x1200"#), summary)
        XCTAssertTrue(summary.contains(#"scrollAxis=vertical pageScrollsY=3 observedElementCount=1"#), summary)
    }

    func testHumanInterfaceRendersHierarchyAndRespectsDetail() {
        let interface = formattingFixtureInterface()

        let summary = FenceResponse.interface(interface, detail: .summary).humanFormatted()
        let full = FenceResponse.interface(interface, detail: .full).humanFormatted()

        XCTAssertTrue(summary.contains(#"group "Actions" id="actions" containerName: semantic_actions__actions"#), summary)
        XCTAssertTrue(summary.contains(#"  [ 0] "Submit" traits=button actions=activate"#), summary)
        XCTAssertTrue(summary.contains(#"  table rows=3 columns=4 containerName: orders_table"#), summary)
        XCTAssertTrue(summary.contains(#"scrollable"#), summary)
        XCTAssertTrue(summary.contains(#"  containerName: main_scroll"#), summary)
        XCTAssertTrue(summary.contains(#"  viewport: 390x400"#), summary)
        XCTAssertTrue(summary.contains(#"  content: 390x1200"#), summary)
        XCTAssertFalse(summary.contains("frame="), summary)
        XCTAssertFalse(summary.contains("stableId"), summary)
        XCTAssertTrue(full.contains(#"group "Actions" id="actions" containerName: semantic_actions__actions frame=(0,40,200,100)"#), full)
    }

    func testCompactScreenshotIncludeInterfaceTextRules() {
        let interface = formattingFixtureInterface()
        let payload = ScreenPayload(pngData: "abc", width: 100, height: 200, interface: interface)

        XCTAssertEqual(
            FenceResponse.screenshotData(payload: payload, options: .init(includeInterface: false)).compactFormatted(),
            "screenshot: 100x200"
        )

        let withInterface = FenceResponse.screenshotData(
            payload: payload,
            options: .init(includeInterface: true)
        ).compactFormatted()
        XCTAssertTrue(withInterface.hasPrefix("screenshot: 100x200\n4 elements\n"), withInterface)
        XCTAssertTrue(
            withInterface.contains(
                #"group label="Actions" id="actions" containerName="semantic_actions__actions" frame=(0,40,200,100)"#
            ),
            withInterface
        )
        XCTAssertFalse(withInterface.contains("stableId"), withInterface)

        XCTAssertEqual(
            FenceResponse.screenshotData(
                payload: ScreenPayload(pngData: "abc", width: 100, height: 200, interface: nil),
                options: .init(includeInterface: true)
            ).compactFormatted(),
            "screenshot: 100x200\ninterface: unavailable"
        )
    }

    func testHumanScreenshotIncludeInterfaceUnavailable() {
        let output = FenceResponse.screenshot(
            path: "/tmp/screen.png",
            payload: ScreenPayload(pngData: "abc", width: 100, height: 200, interface: nil),
            options: .init(includeInterface: true)
        ).humanFormatted()

        XCTAssertTrue(output.contains("✓ Screenshot saved: /tmp/screen.png"), output)
        XCTAssertTrue(output.contains("interface: unavailable"), output)
    }

    private func actionReceiptStep(
        path: String = "$.body[0]",
        command: HeistActionCommand? = .activate(.target(.predicate(ElementPredicate(label: "Button")))),
        result: ActionResult,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        failure: HeistFailureDetail? = nil
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .action,
            status: failure == nil ? .passed : .failed,
            durationMs: 1,
            intent: command.map {
                .action(command: $0.wireType.rawValue, target: $0.reportTarget.map(String.init(describing:)))
            },
            evidence: .action(HeistActionEvidence(
                command: command,
                actionResult: result,
                expectationActionResult: expectationActionResult,
                expectation: expectation
            )),
            failure: failure
        )
    }

    private func warnReceiptStep(path: String, message: String) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: path,
            kind: .warn,
            status: .passed,
            durationMs: 1,
            intent: .warn(message: message),
            evidence: .warning(HeistExecutionWarning(path: path, message: message))
        )
    }

    private func failReceiptStep(message: String) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: "$.body[0]",
            kind: .fail,
            status: .failed,
            durationMs: 1,
            intent: .fail(message: message),
            failure: HeistFailureDetail(
                category: .explicitFailure,
                contract: "explicit heist failure",
                observed: message
            )
        )
    }

    private func caseReceiptStep(
        kind: HeistExecutionStepKind,
        status: HeistExecutionStepStatus,
        selection: HeistCaseSelectionResult,
        failure: HeistFailureDetail? = nil,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: "$.body[0]",
            kind: kind,
            status: status,
            durationMs: 3,
            intent: .conditional,
            evidence: .caseSelection(HeistCaseSelectionEvidence(selection: selection)),
            failure: failure,
            abortedAtChildPath: children.firstFailedStep?.path,
            children: children
        )
    }

    private func forEachStringIterationReceiptStep(
        ordinal: Int,
        value: String,
        status: HeistExecutionStepStatus,
        failureReason: String? = nil,
        children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult {
        HeistExecutionStepResult(
            path: "$.body[0].for_each_string.iterations[\(ordinal)]",
            kind: .forEachIteration,
            status: status,
            durationMs: 1,
            evidence: .forEachString(HeistForEachStringEvidence(
                parameter: "item",
                count: 2,
                iterationCount: 2,
                iterationOrdinal: ordinal,
                value: value,
                failureReason: failureReason
            )),
            failure: failureReason.map {
                HeistFailureDetail(
                    category: .loop,
                    contract: "iteration \(ordinal) completes",
                    observed: $0
                )
            },
            abortedAtChildPath: children.firstFailedStep?.path,
            children: children
        )
    }

    private func formattingFixtureInterface() -> Interface {
        let submit = makeReceiptTestElement(label: "Submit", traits: [.button], actions: [.activate])
        let orderId = makeReceiptTestElement(label: "Order ID", traits: [.staticText])
        let home = makeReceiptTestElement(label: "Home", traits: [.tabBarItem])
        let bottom = makeReceiptTestElement(label: "Bottom", traits: [.staticText])

        return makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestSemanticContainer(
                    label: "Actions",
                    identifier: "actions",
                    frameX: 0,
                    frameY: 40,
                    frameWidth: 200,
                    frameHeight: 100
                ),
                containerName: "semantic_actions__actions",
                children: [
                    .element(submit),
                    .container(
                        makeReceiptTestContainer(
                            type: .dataTable(rowCount: 3, columnCount: 4),
                            frameX: 8,
                            frameY: 52,
                            frameWidth: 180,
                            frameHeight: 36
                        ),
                        containerName: "orders_table",
                        children: [.element(orderId)]
                    ),
                    .container(
                        makeReceiptTestContainer(
                            type: .tabBar,
                            frameX: 0,
                            frameY: 140,
                            frameWidth: 200,
                            frameHeight: 44
                        ),
                        containerName: "main_tabs",
                        children: [.element(home)]
                    ),
                ]
            ),
            .container(
                makeReceiptTestScrollableContainer(
                    contentWidth: 390,
                    contentHeight: 1200,
                    frameX: 0,
                    frameY: 220,
                    frameWidth: 390,
                    frameHeight: 400,
                    isModalBoundary: true
                ),
                containerName: "main_scroll",
                children: [.element(bottom)]
            ),
        ])
    }

}
