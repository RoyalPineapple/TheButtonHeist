import XCTest
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
        scrollable containerName="main_scroll" viewport=390x400 content=390x1200 modal=true
          [3] "Bottom" staticText
        """)
        XCTAssertFalse(output.contains("<"), output)
        XCTAssertFalse(output.contains("semanticGroup"), output)
        XCTAssertFalse(output.contains("dataTable"), output)
        XCTAssertFalse(output.contains("tabBar containerName"), output)
        XCTAssertFalse(output.contains("stableId"), output)
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
