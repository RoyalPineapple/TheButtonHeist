import ButtonHeistTestSupport
import XCTest
import ThePlans
import AccessibilitySnapshotModel
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

extension TheFenceCompactFormattingContractTests {

    func testCompactActionRenderingUsesParsedCommandNames() {
        let cases: [(command: TheFence.Command, payload: ActionResult.Payload, expected: String)] = [
            (.typeText, .typeText(nil), "type_text: ok"),
            (.wait, .wait, "wait: ok"),
            (.activate, .customAction, "activate: ok"),
            (.dismissKeyboard, .dismissKeyboard, "dismiss_keyboard: ok"),
            (.oneFingerTap, .oneFingerTap, "one_finger_tap: ok"),
        ]

        for testCase in cases {
            let output = FenceResponse.action(
                command: testCase.command,
                result: HeistResultFixture.actionResult(payload: testCase.payload)
            ).compactFormatted()

            XCTAssertEqual(output, testCase.expected)
        }
    }

    func testCompactActionRenderingDoesNotInferCommandFromActionMethod() {
        let output = FenceResponse.action(
            command: .drag,
            result: HeistResultFixture.actionResult(payload: .oneFingerTap)
        ).compactFormatted()

        XCTAssertEqual(output, "drag: ok")
    }

    func testScreenActionHandlerMessageRendersInCompactHumanAndJSON() throws {
        let response = FenceResponse.action(
            command: .perform,
            result: HeistResultFixture.actionResult(
                payload: .dismiss,
                message: "Handler: UINavigationController"
            )
        )

        XCTAssertEqual(response.compactFormatted(), "perform: ok\nHandler: UINavigationController")
        XCTAssertEqual(response.humanFormatted(), "✓ perform  Handler: UINavigationController")

        let json = try publicJSONProbe(response)
        XCTAssertEqual(try json.string("message"), "Handler: UINavigationController")
    }

    func testExplicitOneFingerTapKeepsCanonicalResultIdentity() {
        let result = HeistResultFixture.actionResult(payload: .oneFingerTap)
        let output = FenceResponse.action(command: .oneFingerTap, result: result).compactFormatted()

        XCTAssertEqual(result.method, .oneFingerTap)
        XCTAssertEqual(output, "one_finger_tap: ok")
    }

    func testActionFailureWinsOverAttachedExpectationResult() throws {
        let expectation = ExpectationResult(
            met: false,
            predicate: .exists(.label("Done")),
            actual: "not evaluated"
        )
        let response = FenceResponse.action(
            command: .activate,
            result: HeistResultFixture.actionResult(
                succeeded: false,
                payload: .activate,
                message: "button disabled",
                failureKind: .elementNotFound
            ),
            expectation: expectation
        )

        let json = try publicJSONProbe(response)

        XCTAssertEqual(try json.string("status"), "error")
        XCTAssertEqual(try json.string("errorClass"), "elementNotFound")
        XCTAssertEqual(try json.string("code"), "request.element_not_found")
        XCTAssertEqual(try json.string("kind"), "request")
        XCTAssertEqual(try json.string("phase"), "request")
        XCTAssertEqual(try json.bool("retryable"), false)
        try json.assertMissing("expectation")
        XCTAssertEqual(response.compactFormatted(), "activate: error[request.element_not_found]: button disabled")
        XCTAssertEqual(response.humanFormatted(), "Error: button disabled")
        XCTAssertTrue(response.isFailure)
    }

    func testActionFailureProjectionFeedsJSONAndCompactRendering() throws {
        let response = FenceResponse.action(
            command: .wait,
            result: HeistResultFixture.actionResult(
                succeeded: false,
                payload: .wait,
                message: "timed out after 2s",
                failureKind: .timeout
            )
        )

        let json = try publicJSONProbe(response)

        XCTAssertEqual(try json.string("status"), "error")
        XCTAssertEqual(try json.string("errorClass"), "timeout")
        XCTAssertEqual(try json.string("code"), "request.timeout")
        XCTAssertEqual(try json.string("kind"), "request")
        XCTAssertEqual(try json.string("phase"), "request")
        XCTAssertEqual(try json.bool("retryable"), true)
        XCTAssertEqual(response.compactFormatted(), "wait: error[request.timeout]: timed out after 2s")
    }

    func testActionFailureCodeAndClassAgreeAcrossPublicFormats() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: HeistResultFixture.actionResult(
                succeeded: false,
                payload: .activate,
                message: "Could not access accessibility tree: no traversable app windows",
                failureKind: .accessibilityTreeUnavailable
            )
        )

        let json = try publicJSONProbe(response)
        let compact = response.compactFormatted()

        XCTAssertEqual(try json.string("status"), "error")
        XCTAssertEqual(try json.string("errorClass"), "accessibilityTreeUnavailable")
        XCTAssertEqual(try json.string("code"), "request.accessibility_tree_unavailable")
        XCTAssertEqual(try json.string("kind"), "request")
        XCTAssertEqual(try json.string("phase"), "request")
        XCTAssertEqual(try json.bool("retryable"), true)
        XCTAssertTrue(compact.contains("error[request.accessibility_tree_unavailable]"), compact)
    }

    func testScreenExpectationFailureHintUsesTypedElementChangesRegardlessOfActualText() throws {
        let trace = makeTestTrace(
            before: makeTestInterface(elementCount: 1),
            after: makeTestInterface(elementCount: 2)
        )
        let result = HeistResultFixture.actionResult(
            traceEvidence: makeTestTraceEvidence(trace, completeness: .incomplete)
        )
        let response = FenceResponse.action(
            command: .activate,
            result: result,
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.screen()),
                actual: "elementsChanged"
            )
        )
        let arbitraryActualResponse = FenceResponse.action(
            command: .activate,
            result: result,
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.screen()),
                actual: "arbitrary diagnostic"
            )
        )

        let json = try publicJSONProbe(response)
        let expectation = try json.object("expectation")
        let compact = response.compactFormatted()

        XCTAssertEqual(try json.string("status"), "expectation_failed")
        try json.assertMissing("errorClass")
        XCTAssertEqual(try expectation.bool("met"), false)
        XCTAssertEqual(try expectation.string("actual"), "elementsChanged")
        XCTAssertTrue(compact.contains("[expectation FAILED: got elementsChanged]"), compact)
        XCTAssertTrue(compact.contains(".changed(.screen()) requires a screen-level transition"), compact)
        XCTAssertTrue(
            arbitraryActualResponse.compactFormatted()
                .contains(".changed(.screen()) requires a screen-level transition")
        )
        XCTAssertTrue(response.isFailure)
    }

    func testScreenExpectationFailureHintDoesNotTrustElementsChangedActualText() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: HeistResultFixture.actionResult(),
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.screen()),
                actual: "elementsChanged"
            )
        )

        let expectation = try publicJSONProbe(response).object("expectation")
        let compact = response.compactFormatted()

        try expectation.assertMissing("hint")
        XCTAssertFalse(compact.contains(".changed(.screen()) requires a screen-level transition"), compact)
    }

    func testActivateNoChangeExpectationFailureUsesTypedSettledTraceRegardlessOfActualText() throws {
        let unchanged = makeTestInterface(elementCount: 1)
        let trace = makeTestTrace(before: unchanged, after: unchanged)
        let result = ActionResult.success(
            payload: .activate,
            observation: .settledTrace(
                makeTestTraceEvidence(trace, completeness: .complete),
                .settled(duration: 1)
            )
        )
        let response = FenceResponse.action(
            command: .activate,
            result: result,
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.elements()),
                actual: "noChange"
            )
        )
        let arbitraryActualResponse = FenceResponse.action(
            command: .activate,
            result: result,
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.elements()),
                actual: "arbitrary diagnostic"
            )
        )

        let json = try publicJSONProbe(response)
        let expectation = try json.object("expectation")
        let compact = response.compactFormatted()
        let human = response.humanFormatted()

        XCTAssertEqual(try json.string("status"), "expectation_failed")
        XCTAssertEqual(try expectation.string("actual"), "noChange")
        let hint = try expectation.string("hint")
        XCTAssertTrue(
            hint.contains("accessibilityActivate()"),
            hint
        )
        XCTAssertTrue(compact.contains("[expectation FAILED: got noChange]"), compact)
        XCTAssertTrue(compact.contains("does not send activation-point tap dispatch"), compact)
        XCTAssertTrue(human.contains("[expectation FAILED: expected changed(elements(*)), got noChange]"), human)
        XCTAssertTrue(human.contains("accessibility activation path is inert or mismatched"), human)
        XCTAssertTrue(
            arbitraryActualResponse.compactFormatted()
                .contains("does not send activation-point tap dispatch")
        )
        XCTAssertTrue(response.isFailure)
    }

    func testActivateNoChangeExpectationHintDoesNotTrustNoChangeActualText() throws {
        let trace = makeTestTrace(
            before: makeTestInterface(elementCount: 1),
            after: makeTestInterface(elementCount: 2)
        )
        let response = FenceResponse.action(
            command: .activate,
            result: HeistResultFixture.actionResult(
                payload: .activate,
                traceEvidence: makeTestTraceEvidence(trace, completeness: .incomplete)
            ),
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.elements()),
                actual: "noChange"
            )
        )

        let expectation = try publicJSONProbe(response).object("expectation")
        let compact = response.compactFormatted()

        try expectation.assertMissing("hint")
        XCTAssertFalse(compact.contains("accessibilityActivate()"), compact)
    }

    func testActivateNoChangeExpectationHintRequiresSuccessfulActivateMethod() {
        let unchanged = makeTestInterface(elementCount: 1)
        let trace = makeTestTrace(before: unchanged, after: unchanged)
        let observation = ActionResultObservationEvidence.settledTrace(
            makeTestTraceEvidence(trace, completeness: .incomplete),
            .settled(duration: 1)
        )
        let expectation = ExpectationResult(
            met: false,
            predicate: .changed(.elements()),
            actual: "noChange"
        )
        let customActionResult = ActionResult.success(
            payload: .customAction,
            observation: observation
        )
        let failedActivateResult = ActionResult.failure(
            payload: .activate,
            failureKind: .actionFailed,
            observation: observation
        )

        XCTAssertNil(FenceResponse.expectationFailureHint(
            expectation,
            command: .activate,
            result: customActionResult
        ))
        XCTAssertNil(FenceResponse.expectationFailureHint(
            expectation,
            command: .activate,
            result: failedActivateResult
        ))
    }

    func testActivateNoChangeWithoutExpectationRemainsSuccessful() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: HeistResultFixture.actionResult()
        )

        let json = try publicJSONProbe(response)

        XCTAssertEqual(try json.string("status"), "ok")
        try json.assertMissing("expectation")
        XCTAssertEqual(response.compactFormatted(), "activate: ok")
        XCTAssertTrue(response.humanFormatted().contains("✓ activate"))
        XCTAssertFalse(response.isFailure)
    }

    func testActivateNoChangeCarriesActivationTraceWithoutFailingAction() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: HeistResultFixture.actionResult(
                payload: .activate,
                traceEvidence: makeTestTraceEvidence(
                    makeTestTrace(
                        before: makeTestInterface(elementCount: 3),
                        after: makeTestInterface(elementCount: 3)
                    ),
                    completeness: .complete
                ),
                activationTrace: ActivationTrace(.activationPointFallback(
                    axActivateReturned: false,
                    tapActivationPoint: ScreenPoint(x: 888, y: 372),
                    tapActivationSucceeded: true
                ), implementsAccessibilityActivation: false)
            )
        )

        let json = try publicJSONProbe(response)
        let activationTrace = try json.object("activationTrace")
        let compact = response.compactFormatted()

        XCTAssertEqual(try json.string("status"), "ok")
        XCTAssertEqual(try activationTrace.bool("axActivateReturned"), false)
        XCTAssertEqual(try activationTrace.bool("tapActivationDispatched"), true)
        XCTAssertEqual(try activationTrace.bool("tapActivationSucceeded"), true)
        XCTAssertEqual(response.isFailure, false)
        XCTAssertTrue(compact.contains("activate: no change"), compact)
        XCTAssertTrue(compact.contains("tapActivationDispatched=true"), compact)
        XCTAssertTrue(compact.contains("tapActivationPoint=point(888,372)"), compact)
    }

    func testElementsChangedActionOutputIncludesConcreteElementDelta() throws {
        let added = makeTestHeistElement(
            label: "Barbaresco",
            value: "$55.00",
            identifier: "wine_barbaresco",
            traits: [.staticText]
        )
        let unchanged = (0..<11).map { index in
            makeTestHeistElement(label: "Row \(index)", identifier: "row_\(index)")
        }
        let trace = makeTestTrace(
            before: makeTestInterface(elements: unchanged),
            after: makeTestInterface(elements: unchanged + [added])
        )
        let response = FenceResponse.action(
            command: .activate,
            result: HeistResultFixture.actionResult(
                traceEvidence: makeTestTraceEvidence(trace, completeness: .incomplete)
            )
        )

        let delta = try publicJSONProbe(response).object("delta")
        let addedJSON = try delta.object("edits").array("added")
        let digest = try delta.object("interactionDigest")
        let compact = response.compactFormatted()
        let human = response.humanFormatted()

        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        XCTAssertEqual(try digest.int("nodeCountBefore"), 11)
        XCTAssertEqual(try digest.int("nodeCountAfter"), 12)
        XCTAssertEqual(try digest.bool("nodeCountChanged"), true)
        XCTAssertEqual(try digest.bool("elementSetChanged"), true)
        XCTAssertEqual(try addedJSON.first?.string("label"), "Barbaresco")
        XCTAssertEqual(try addedJSON.first?.string("identifier"), "wine_barbaresco")
        XCTAssertTrue(compact.contains(#"+ "Barbaresco":"$55.00" staticText id="wine_barbaresco""#), compact)
        XCTAssertTrue(human.contains(#"+ "Barbaresco":"$55.00" staticText id="wine_barbaresco""#), human)
    }

    func testDeltaFoldsFastElementLifecycleWithoutEndpointDiffing() throws {
        let toast = makeTestHeistElement(label: "Saved", identifier: "saved_toast", traits: [.staticText])
        let empty = makeTestInterface(elements: [])
        let visible = makeTestInterface(elements: [toast])
        let trace = AccessibilityTrace(first: empty)
            .appending(visible)
            .appending(empty)
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        )

        let delta = try publicJSONProbe(response).object("delta")
        let compact = response.compactFormatted()

        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        XCTAssertEqual(try delta.array("transient").first?.string("identifier"), "saved_toast")
        try delta.assertMissing("edits")
        XCTAssertTrue(compact.contains("activate: elements changed"), compact)
        XCTAssertTrue(compact.contains(#"+- "Saved" staticText id="saved_toast""#), compact)
    }

    func testNotificationOnlyDeltaPreservesDeduplicatedTemporalEvidence() throws {
        let interface = makeTestInterface(elementCount: 1)
        let first = AccessibilityNotificationEvidence(
            sequence: 7,
            kind: .elementChanged(.value),
            timestamp: Date(timeIntervalSince1970: 7),
            notificationData: .none,
            associatedElement: .none
        )
        let second = AccessibilityNotificationEvidence(
            sequence: 8,
            kind: .elementChanged(.layout),
            timestamp: Date(timeIntervalSince1970: 8),
            notificationData: .none,
            associatedElement: .none
        )
        let trace = AccessibilityTrace(first: interface)
            .appending(
                interface,
                transition: AccessibilityTrace.Transition(accessibilityNotifications: [first])
            )
            .appending(
                interface,
                transition: AccessibilityTrace.Transition(accessibilityNotifications: [first, second])
            )
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        )

        let delta = try publicJSONProbe(response).object("delta")
        let notifications = try delta.array("accessibilityNotifications")
        let compact = response.compactFormatted()

        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        try delta.assertMissing("edits")
        XCTAssertEqual(try notifications.map { try $0.int("sequence") }, [7, 8])
        let kinds = try notifications.map { try $0.object("kind") }
        XCTAssertEqual(try kinds.map { try $0.string("type") }, ["elementChanged", "elementChanged"])
        XCTAssertEqual(try kinds.map { try $0.string("notification") }, ["value", "layout"])
        XCTAssertTrue(compact.contains("accessibility notification elementChanged(value) #7"), compact)
        XCTAssertTrue(compact.contains("accessibility notification elementChanged(layout) #8"), compact)
    }

    func testScreenChangedActionOutputIncludesDestinationSummaryTree() throws {
        let destination = makeTestInterface(elements: [
            makeTestHeistElement(label: "Checkout", identifier: "checkout_title", traits: [.header]),
            makeTestHeistElement(label: "Pay", identifier: "pay_button", traits: [.button], actions: [.activate]),
        ])
        let trace = makeTestTrace(
            before: makeTestInterface(elements: [makeTestHeistElement(label: "Cart", identifier: "cart_title")]),
            after: destination,
            beforeScreenId: "cart",
            afterScreenId: "checkout",
            afterTransition: makeTestScreenChangedTransition()
        )
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        )

        let delta = try publicJSONProbe(response).object("delta")
        let newInterface = try delta.object("newInterface")
        let compact = response.compactFormatted()
        let human = response.humanFormatted()

        XCTAssertEqual(try delta.string("kind"), "screenChanged")
        XCTAssertEqual(try newInterface.array("tree").count, 2)
        XCTAssertTrue(compact.contains("activate: screen changed\nCheckout\n2 elements"), compact)
        XCTAssertTrue(compact.contains(#""Checkout" header id="checkout_title""#), compact)
        XCTAssertTrue(compact.contains(#""Pay" button id="pay_button""#), compact)
        XCTAssertTrue(human.contains("screen changed]\nCheckout\n2 elements"), human)
        XCTAssertTrue(human.contains(#""Checkout" header id="checkout_title""#), human)
    }

    func testLaterScreenChangeDominatesEarlierElementFactsAndDeduplicatesTransitionEvidence() throws {
        let toast = makeTestHeistElement(label: "Saved", identifier: "saved_toast", traits: [.staticText])
        let cart = makeTestInterface(elements: [
            makeTestHeistElement(label: "Cart", identifier: "cart_title", traits: [.header]),
        ])
        let cartWithToast = makeTestInterface(elements: [toast] + cart.projectedElements)
        let checkout = makeTestInterface(elements: [
            makeTestHeistElement(label: "Checkout", identifier: "checkout_title", traits: [.header]),
        ])
        let before = AccessibilityTrace.Capture(
            sequence: 1,
            interface: cart,
            context: AccessibilityTrace.Context(screenId: "cart")
        )
        let elementChange = AccessibilityTrace.Capture(
            sequence: 2,
            interface: cartWithToast,
            parentHash: before.hash,
            context: AccessibilityTrace.Context(screenId: "cart")
        )
        let after = AccessibilityTrace.Capture(
            sequence: 3,
            interface: checkout,
            parentHash: elementChange.hash,
            context: AccessibilityTrace.Context(screenId: "checkout"),
            transition: makeTestScreenChangedTransition(sequence: 9)
        )
        let trace = AccessibilityTrace(captures: [before, elementChange, after])
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(
                payload: .activate,
                observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
            )
        )

        let delta = try publicJSONProbe(response).object("delta")

        XCTAssertEqual(try delta.string("kind"), "screenChanged")
        XCTAssertEqual(try delta.array("transient").count, 1)
        XCTAssertEqual(try delta.array("transient").first?.string("identifier"), "saved_toast")
        try delta.assertMissing("edits")
    }

    func testHeistActionStructuredOutputIncludesConcreteElementDeltaWithoutDumpingSuccessCompact() throws {
        let unchanged = (0..<3).map { index in
            makeTestHeistElement(label: "Row \(index)", identifier: "row_\(index)")
        }
        let lazyRow = makeTestHeistElement(
            label: "Lazy Row",
            value: "Loaded by scroll",
            identifier: "lazy_row",
            traits: [.staticText]
        )
        let trace = makeTestTrace(
            before: makeTestInterface(elements: unchanged),
            after: makeTestInterface(elements: unchanged + [lazyRow])
        )
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Load More")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let result = HeistResult(
            steps: [
                HeistResultFixture.action(
                    command: command,
                    result: ActionResult.success(
                        payload: .activate,
                        observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
                    )
                ),
            ],
            durationMs: 8
        )
        let response = FenceResponse.heistExecution(plan: plan, report: HeistReport.project(result: result))

        let compact = response.compactFormatted()
        let report = try publicHeistReportJSON(response)
        let node = try XCTUnwrap(try report.array("nodes").first)
        let action = try node.object("evidence").object("action")
        let actionResult = try action.object("result")
        let delta = try actionResult.object("delta")

        try assertPublicHeistSummary(
            report.object("summary"),
            executedTopLevelStepCount: 1,
            executedNodeCount: 1,
            outputNodeCount: 1,
            durationMs: 8,
            abortedAtPath: nil
        )
        XCTAssertEqual(try node.string("path"), "$.body[0]")
        XCTAssertEqual(try node.string("kind"), "action")
        XCTAssertEqual(try node.string("status"), "passed")
        XCTAssertEqual(try node.int("durationMs"), 1)
        XCTAssertEqual(try action.string("commandName"), "activate")
        XCTAssertEqual(try actionResult.string("status"), "ok")
        XCTAssertEqual(try actionResult.string("method"), "activate")
        XCTAssertEqual(try actionResult.string("screenId"), "screen")
        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        XCTAssertEqual(try delta.int("elementCount"), 4)
        try assertPublicInteractionDigest(
            delta.object("interactionDigest"),
            expected: AccessibilityTrace.InteractionDigest(
                nodeCountBefore: 3,
                nodeCountAfter: 4,
                elementSetChanged: true,
                screenIdBefore: "screen",
                screenIdAfter: "screen",
                firstResponderChanged: false
            )
        )
        let added = try delta.object("edits").array("added")
        XCTAssertEqual(added.count, 1)
        try assertPublicElement(
            try XCTUnwrap(added.first),
            traits: ["staticText"],
            label: "Lazy Row",
            value: "Loaded by scroll",
            identifier: "lazy_row"
        )
        try assertAccessibilityTraceProjectedAsDelta(actionResult, omittedCount: 2)
        try node.assertMissing("action")
        XCTAssertTrue(compact.contains("-> elements changed"), compact)
        XCTAssertFalse(compact.contains(#"+ "Lazy Row":"Loaded by scroll" staticText id="lazy_row""#), compact)
    }

    func testPublicHeistJSONBoundsActionDeltaAndReportsOmissions() throws {
        let addedRows = (0..<8).map { index in
            makeTestHeistElement(
                label: "Lazy Row \(index)",
                value: "Loaded \(index)",
                identifier: "lazy_row_\(index)",
                traits: [.staticText]
            )
        }
        let trace = makeTestTrace(
            before: makeTestInterface(elements: []),
            after: makeTestInterface(elements: addedRows)
        )
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Load More")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let response = FenceResponse.heistExecution(
            plan: plan,
            report: HeistReport.project(result: HeistResult(
                steps: [
                    HeistResultFixture.action(
                        command: command,
                        result: ActionResult.success(
                            payload: .activate,
                            observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
                        )
                    ),
                ],
                durationMs: 8
            ))
        )

        let json = try publicJSONProbe(response)
        let report = try json.object("report")
        let node = try XCTUnwrap(try report.array("nodes").first)
        let actionResult = try node.object("evidence").object("action").object("result")
        let delta = try actionResult.object("delta")
        let edits = try delta.object("edits")
        let added = try edits.array("added")
        let omitted = try edits.object("omitted")

        XCTAssertEqual(try actionResult.string("status"), "ok")
        XCTAssertEqual(try actionResult.string("method"), "activate")
        XCTAssertEqual(try actionResult.string("screenId"), "screen")
        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        XCTAssertEqual(try delta.int("elementCount"), 8)
        try assertPublicInteractionDigest(
            delta.object("interactionDigest"),
            expected: AccessibilityTrace.InteractionDigest(
                nodeCountBefore: 0,
                nodeCountAfter: 8,
                elementSetChanged: true,
                screenIdBefore: "screen",
                screenIdAfter: "screen",
                firstResponderChanged: false
            )
        )
        XCTAssertEqual(added.count, 5)
        for index in 0..<5 {
            try assertPublicElement(
                added[index],
                traits: ["staticText"],
                label: "Lazy Row \(index)",
                value: "Loaded \(index)",
                identifier: "lazy_row_\(index)"
            )
        }
        XCTAssertEqual(try omitted.int("added"), 3)
        XCTAssertEqual(
            try omitted.strings("addedKeys"),
            ["identifier:lazy_row_5", "identifier:lazy_row_6", "identifier:lazy_row_7"]
        )
        try node.assertMissing("action")
        try delta.assertMissing("newInterface")
        try assertAccessibilityTraceProjectedAsDelta(actionResult, omittedCount: 2)
        try json.assertRecursivelyMissingKeys(["captures"])
    }

    func testPublicHeistJSONUsesBoundedScreenProjectionForActionDelta() throws {
        let afterRows = (0..<8).map { index in
            makeTestHeistElement(
                label: "Checkout Row \(index)",
                identifier: "checkout_row_\(index)",
                traits: [.staticText]
            )
        }
        let trace = makeTestTrace(
            before: makeTestInterface(elements: []),
            after: makeTestInterface(elements: afterRows),
            beforeScreenId: "before",
            afterScreenId: "checkout",
            afterTransition: makeTestScreenChangedTransition()
        )
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Checkout")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let response = FenceResponse.heistExecution(
            plan: plan,
            report: HeistReport.project(result: HeistResult(
                steps: [
                    HeistResultFixture.action(
                        command: command,
                        result: ActionResult.success(
                            payload: .activate,
                            observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
                        )
                    ),
                ],
                durationMs: 8
            ))
        )

        let json = try publicJSONProbe(response)
        let report = try json.object("report")
        let node = try XCTUnwrap(try report.array("nodes").first)
        let actionResult = try node.object("evidence").object("action").object("result")
        let delta = try actionResult.object("delta")
        let screen = try delta.object("screen")
        let elements = try screen.array("elements")

        XCTAssertEqual(try actionResult.string("status"), "ok")
        XCTAssertEqual(try actionResult.string("method"), "activate")
        XCTAssertEqual(try actionResult.string("screenId"), "checkout")
        XCTAssertEqual(try delta.string("kind"), "screenChanged")
        XCTAssertEqual(try delta.int("elementCount"), 8)
        try assertPublicInteractionDigest(
            delta.object("interactionDigest"),
            expected: AccessibilityTrace.InteractionDigest(
                nodeCountBefore: 0,
                nodeCountAfter: 8,
                elementSetChanged: true,
                screenIdBefore: "before",
                screenIdAfter: "checkout",
                firstResponderChanged: false
            )
        )
        XCTAssertEqual(try screen.int("elementCount"), 8)
        XCTAssertEqual(elements.count, 5)
        for index in 0..<5 {
            try assertPublicElement(
                elements[index],
                traits: ["staticText"],
                label: "Checkout Row \(index)",
                identifier: "checkout_row_\(index)"
            )
        }
        XCTAssertEqual(try screen.int("omittedElementCount"), 3)
        try assertAccessibilityTraceProjectedAsDelta(actionResult, omittedCount: 2)
        try node.assertMissing("action")
        try delta.assertMissing("newInterface")
        try json.assertRecursivelyMissingKeys(["tree", "captures"])
    }

    func testFailedHeistActionCompactOutputIncludesConcreteElementDeltaEvidence() throws {
        let unchanged = (0..<3).map { index in
            makeTestHeistElement(label: "Row \(index)", identifier: "row_\(index)")
        }
        let lazyRow = makeTestHeistElement(
            label: "Lazy Row",
            value: "Loaded by scroll",
            identifier: "lazy_row",
            traits: [.staticText]
        )
        let trace = makeTestTrace(
            before: makeTestInterface(elements: unchanged),
            after: makeTestInterface(elements: unchanged + [lazyRow])
        )
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Load More")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let result = HeistResult(
            steps: [
                HeistResultFixture.action(
                    command: command,
                    result: ActionResult.failure(
                        payload: .activate,
                        failureKind: .actionFailed,
                        message: "target stopped responding",
                        observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete))
                    ),
                    failure: HeistFailureDetail(
                        category: .action,
                        contract: "activate command succeeds",
                        observed: "target stopped responding"
                    )
                ),
            ],
            durationMs: 8
        )

        let compact = FenceResponse.heistExecution(plan: plan, report: HeistReport.project(result: result)).compactFormatted()

        XCTAssertTrue(compact.contains("-> error: target stopped responding"), compact)
        XCTAssertTrue(compact.contains("evidence: elements changed"), compact)
        XCTAssertTrue(compact.contains(#"+ "Lazy Row":"Loaded by scroll" staticText id="lazy_row""#), compact)
    }

    func testFailedHeistActionReportsCanonicalActionResultActivationTrace() throws {
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 195, y: 139),
            tapActivationSucceeded: true
        ), implementsAccessibilityActivation: false)
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Search all items")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let response = FenceResponse.heistExecution(
            plan: plan,
            report: HeistReport.project(result: HeistResult(
                steps: [
                    HeistResultFixture.action(
                        command: command,
                        result: ActionResult.activationFailure(
                            failureKind: .actionFailed,
                            message: "text entry failed: observed focus=none keyboardVisible=false activeTextInput=false",
                            observation: .none,
                            activationTrace: activationTrace
                        ),
                        failure: HeistFailureDetail(
                            category: .action,
                            contract: "action dispatch succeeds",
                            observed: "text entry failed: observed focus=none keyboardVisible=false activeTextInput=false"
                        )
                    ),
                ],
                durationMs: 8
            ))
        )

        let compact = response.compactFormatted()
        let node = try XCTUnwrap(try publicJSONProbe(response).object("report").array("nodes").first)
        let actionResult = try node.object("evidence").object("action").object("result")
        let renderedActivationTrace = try actionResult.object("activationTrace")

        try node.object("failure").assertMissing("activationTrace")
        XCTAssertEqual(try renderedActivationTrace.bool("axActivateReturned"), false)
        XCTAssertEqual(try renderedActivationTrace.bool("tapActivationDispatched"), true)
        XCTAssertEqual(try renderedActivationTrace.bool("tapActivationSucceeded"), true)
        XCTAssertEqual(try renderedActivationTrace.object("tapActivationPoint").double("x"), 195)
        XCTAssertEqual(try renderedActivationTrace.object("tapActivationPoint").double("y"), 139)
        XCTAssertTrue(compact.contains("activation: axActivateReturned=false"), compact)
        XCTAssertTrue(compact.contains("tapActivationDispatched=true"), compact)
        XCTAssertTrue(compact.contains("tapActivationSucceeded=true"), compact)
        XCTAssertTrue(compact.contains("tapActivationPoint=point(195,139)"), compact)
    }

}
