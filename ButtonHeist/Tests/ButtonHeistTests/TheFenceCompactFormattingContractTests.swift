import ButtonHeistTestSupport
import XCTest
import ThePlans
import AccessibilitySnapshotModel
@_spi(ButtonHeistTooling) @testable import ButtonHeist
import TheScore

final class TheFenceCompactFormattingContractTests: XCTestCase {

    private struct MetricSampleExpectation: Equatable {
        let name: String
        let valueMs: Int
        let path: String?

        init(name: String, valueMs: Int, path: String?) {
            self.name = name
            self.valueMs = valueMs
            self.path = path
        }

        init(sample: HeistExecutionMetricSample) {
            self.init(name: sample.name.rawValue, valueMs: sample.valueMs, path: sample.path)
        }
    }

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
                result: makeTestActionResult(method: testCase.method)
            ).compactFormatted()

            XCTAssertEqual(output, testCase.expected)
        }
    }

    func testCompactActionRenderingDoesNotInferCommandFromActionMethod() {
        let output = FenceResponse.action(
            command: .drag,
            result: makeTestActionResult(method: .syntheticTap)
        ).compactFormatted()

        XCTAssertEqual(output, "drag: ok")
    }

    func testScreenActionHandlerMessageRendersInCompactHumanAndJSON() throws {
        let response = FenceResponse.action(
            command: .perform,
            result: makeTestActionResult(
                method: .dismiss,
                message: "Handler: UINavigationController"
            )
        )

        XCTAssertEqual(response.compactFormatted(), "perform: ok\nHandler: UINavigationController")
        XCTAssertEqual(response.humanFormatted(), "✓ perform  Handler: UINavigationController")

        let json = try publicJSONProbe(response)
        XCTAssertEqual(try json.string("message"), "Handler: UINavigationController")
    }

    func testExplicitOneFingerTapKeepsMechanicalResultIdentity() {
        let result = makeTestActionResult(method: .syntheticTap)
        let output = FenceResponse.action(command: .oneFingerTap, result: result).compactFormatted()

        XCTAssertEqual(result.method, .syntheticTap)
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
            result: makeTestActionResult(
                succeeded: false,
                method: .activate,
                message: "button disabled",
                errorKind: .elementNotFound
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
            result: makeTestActionResult(
                succeeded: false,
                method: .wait,
                message: "timed out after 2s",
                errorKind: .timeout
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
            result: makeTestActionResult(
                succeeded: false,
                method: .activate,
                message: "Could not access accessibility tree: no traversable app windows",
                errorKind: .accessibilityTreeUnavailable
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

    func testExpectationFailureStatusAndHintAgreeAcrossJSONAndCompact() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: makeTestActionResult(),
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.screen()),
                actual: "elementsChanged"
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
        XCTAssertTrue(response.isFailure)
    }

    func testActivateNoChangeExpectationFailureExplainsSemanticActivationPath() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: makeTestActionResult(),
            expectation: ExpectationResult(
                met: false,
                predicate: .changed(.elements()),
                actual: "noChange"
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
        XCTAssertTrue(response.isFailure)
    }

    func testActivateNoChangeWithoutExpectationRemainsSuccessful() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: makeTestActionResult()
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
            result: makeTestActionResult(
                method: .activate,
                accessibilityTrace: makeReceiptTestTrace(
                    before: makeReceiptTestInterface(elementCount: 3),
                    after: makeReceiptTestInterface(elementCount: 3)
                ),
                activationTrace: ActivationTrace(.activationPointFallback(
                    axActivateReturned: false,
                    tapActivationPoint: ScreenPoint(x: 888, y: 372),
                    tapActivationSucceeded: true
                ))
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
            result: makeTestActionResult(accessibilityTrace: trace)
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
        let toast = makeReceiptTestElement(label: "Saved", identifier: "saved_toast", traits: [.staticText])
        let empty = makeReceiptTestInterface([])
        let visible = makeReceiptTestInterface([toast])
        let trace = AccessibilityTrace(captures: [
            AccessibilityTrace.Capture(sequence: 1, interface: empty),
            AccessibilityTrace.Capture(sequence: 2, interface: visible),
            AccessibilityTrace.Capture(sequence: 3, interface: empty),
        ])
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(method: .activate, accessibilityTrace: trace)
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
        let interface = makeReceiptTestInterface(elementCount: 1)
        let first = AccessibilityNotificationEvidence(
            sequence: 7,
            kind: .valueChanged,
            timestamp: Date(timeIntervalSince1970: 7),
            notificationData: .none,
            associatedElement: .none
        )
        let second = AccessibilityNotificationEvidence(
            sequence: 8,
            kind: .layoutChanged,
            timestamp: Date(timeIntervalSince1970: 8),
            notificationData: .none,
            associatedElement: .none
        )
        let trace = AccessibilityTrace(captures: [
            AccessibilityTrace.Capture(sequence: 1, interface: interface),
            AccessibilityTrace.Capture(
                sequence: 2,
                interface: interface,
                transition: AccessibilityTrace.Transition(accessibilityNotifications: [first])
            ),
            AccessibilityTrace.Capture(
                sequence: 3,
                interface: interface,
                transition: AccessibilityTrace.Transition(accessibilityNotifications: [first, second])
            ),
        ])
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(method: .activate, accessibilityTrace: trace)
        )

        let delta = try publicJSONProbe(response).object("delta")
        let notifications = try delta.array("accessibilityNotifications")
        let compact = response.compactFormatted()

        XCTAssertEqual(try delta.string("kind"), "elementsChanged")
        try delta.assertMissing("edits")
        XCTAssertEqual(try notifications.map { try $0.int("sequence") }, [7, 8])
        XCTAssertEqual(try notifications.map { try $0.string("kind") }, ["valueChanged", "elementChanged"])
        XCTAssertTrue(compact.contains("accessibility notification valueChanged #7"), compact)
        XCTAssertTrue(compact.contains("accessibility notification elementChanged #8"), compact)
    }

    func testScreenChangedActionOutputIncludesDestinationSummaryTree() throws {
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
            result: ActionResult.success(method: .activate, accessibilityTrace: trace)
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
        let toast = makeReceiptTestElement(label: "Saved", identifier: "saved_toast", traits: [.staticText])
        let cart = makeReceiptTestInterface([
            makeReceiptTestElement(label: "Cart", identifier: "cart_title", traits: [.header]),
        ])
        let cartWithToast = makeReceiptTestInterface([toast] + cart.projectedElements)
        let checkout = makeReceiptTestInterface([
            makeReceiptTestElement(label: "Checkout", identifier: "checkout_title", traits: [.header]),
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
            context: AccessibilityTrace.Context(screenId: "checkout")
        )
        let trace = AccessibilityTrace(captures: [before, elementChange, after])
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(method: .activate, accessibilityTrace: trace)
        )

        let delta = try publicJSONProbe(response).object("delta")

        XCTAssertEqual(try delta.string("kind"), "screenChanged")
        XCTAssertEqual(try delta.array("transient").count, 1)
        XCTAssertEqual(try delta.array("transient").first?.string("identifier"), "saved_toast")
        try delta.assertMissing("edits")
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
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Load More")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let result = HeistExecutionResult(
            steps: [
                actionReceiptStep(
                    command: command,
                    result: ActionResult.success(method: .activate, accessibilityTrace: trace)
                ),
            ],
            durationMs: 8
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

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
            outputReceiptNodeCount: 1,
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
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Load More")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let response = FenceResponse.heistExecution(
            plan: plan,
            result: HeistExecutionResult(
                steps: [
                    actionReceiptStep(
                        command: command,
                        result: ActionResult.success(method: .activate, accessibilityTrace: trace)
                    ),
                ],
                durationMs: 8
            )
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
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Checkout")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let response = FenceResponse.heistExecution(
            plan: plan,
            result: HeistExecutionResult(
                steps: [
                    actionReceiptStep(
                        command: command,
                        result: ActionResult.success(method: .activate, accessibilityTrace: trace)
                    ),
                ],
                durationMs: 8
            )
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
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Load More")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let result = HeistExecutionResult(
            steps: [
                actionReceiptStep(
                    command: command,
                    result: ActionResult.failure(
                        method: .activate,
                        errorKind: .actionFailed,
                        message: "target stopped responding",
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

    func testFailedHeistActionFailureDetailReportsActivationTrace() throws {
        let activationTrace = ActivationTrace(.activationPointFallback(
            axActivateReturned: false,
            tapActivationPoint: ScreenPoint(x: 195, y: 139),
            tapActivationSucceeded: true
        ))
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Search all items")))
        let plan = try HeistPlan(body: [.action(ActionStep(command: command))])
        let response = FenceResponse.heistExecution(
            plan: plan,
            result: HeistExecutionResult(
                steps: [
                    actionReceiptStep(
                        command: command,
                        result: ActionResult.failure(
                            method: .activate,
                            errorKind: .actionFailed,
                            message: "text entry failed: observed focus=none keyboardVisible=false activeTextInput=false",
                            activationTrace: activationTrace
                        ),
                        failure: HeistFailureDetail(
                            category: .action,
                            contract: "action dispatch succeeds",
                            observed: "text entry failed: observed focus=none keyboardVisible=false activeTextInput=false",
                            activationTrace: activationTrace
                        )
                    ),
                ],
                durationMs: 8,
                abortedAtPath: "$.body[0]"
            )
        )

        let compact = response.compactFormatted()
        let node = try XCTUnwrap(try publicJSONProbe(response).object("report").array("nodes").first)
        let failureTrace = try node.object("failure").object("activationTrace")

        XCTAssertEqual(try failureTrace.bool("axActivateReturned"), false)
        XCTAssertEqual(try failureTrace.bool("tapActivationDispatched"), true)
        XCTAssertEqual(try failureTrace.bool("tapActivationSucceeded"), true)
        XCTAssertEqual(try failureTrace.object("tapActivationPoint").double("x"), 195)
        XCTAssertEqual(try failureTrace.object("tapActivationPoint").double("y"), 139)
        XCTAssertTrue(compact.contains("activation: axActivateReturned=false"), compact)
        XCTAssertTrue(compact.contains("tapActivationDispatched=true"), compact)
        XCTAssertTrue(compact.contains("tapActivationSucceeded=true"), compact)
        XCTAssertTrue(compact.contains("tapActivationPoint=point(195,139)"), compact)
    }

    func testExpectationSuccessStaysSuccessfulAcrossPublicFormats() throws {
        let response = FenceResponse.action(
            command: .activate,
            result: ActionResult.success(method: .activate),
            expectation: ExpectationResult(
                met: true,
                predicate: .exists(.label("Done")),
                actual: "matched"
            )
        )

        let json = try publicJSONProbe(response)
        let expectation = try json.object("expectation")

        XCTAssertEqual(try json.string("status"), "ok")
        XCTAssertEqual(try expectation.bool("met"), true)
        XCTAssertEqual(response.compactFormatted(), "activate: ok")
        XCTAssertTrue(response.humanFormatted().contains("[expectation met]"))
        XCTAssertFalse(response.isFailure)
    }

    func testHumanHeistFormattingCountsNestedProjectedExpectations() throws {
        let expected = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let childAction = try HeistStep.action(ActionStep(
            command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Submit"))))),
            expectationPolicy: .expect(ActionExpectation(predicate: expected, timeout: 1))))
        let casePredicate = AccessibilityPredicate<ScreenAssertionContext>.exists(.label("Home"))
        let casePredicateRuntime = AccessibilityPredicate<RootContext>.exists(.label("Home"))
        let conditional = try ConditionalStep(cases: [
            PredicateCase(predicate: casePredicate, body: [childAction]),
        ])
        let plan = try HeistPlan(body: [.conditional(conditional)])
        let childResult = actionReceiptStep(
            path: "$.body[0].conditional.cases[0].body[0]",
            result: ActionResult.success(method: .activate),
            expectationActionResult: ActionResult.success(method: .wait),
            expectation: ExpectationResult(met: true, predicate: expected)
        )
        let result = HeistExecutionResult(steps: [
                caseReceiptStep(
                    kind: .conditional,
                    status: .passed,
                    selection: HeistCaseSelectionResult(
                        cases: [
                            HeistCaseMatchResult(
                                predicate: casePredicateRuntime,
                                result: ExpectationResult(met: true, predicate: casePredicateRuntime)
                            ),
                        ],
                        outcome: .matchedCase(index: 0),
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
        let expected = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let action = try HeistStep.action(ActionStep(
            command: .activate(.predicate(ElementPredicateTemplate(label: "Submit"))),
            expectationPolicy: .expect(ActionExpectation(predicate: expected, timeout: 1))))
        let plan = try HeistPlan(body: [
            .warn(WarnStep(message: "starting checkout")),
            action,
        ])
        let result = HeistExecutionResult(
            steps: [
                warnReceiptStep(path: "$.body[0]", message: "starting checkout"),
                actionReceiptStep(
                    path: "$.body[1]",
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Submit"))),
                    result: ActionResult.success(method: .activate),
                    expectationActionResult: ActionResult.success(method: .wait),
                    expectation: ExpectationResult(met: true, predicate: expected, actual: "matched")
                ),
            ],
            durationMs: 5
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

        let json = try publicJSONProbe(response)
        let report = try json.object("report")
        let reportExpectations = try json.object("report").object("summary").object("expectations")

        try assertHeistReportRootOmitsSummaryDuplicates(json)
        try assertPublicHeistSummary(
            report.object("summary"),
            executedTopLevelStepCount: 2,
            executedNodeCount: 2,
            outputReceiptNodeCount: 2,
            durationMs: 5,
            abortedAtPath: nil
        )
        XCTAssertEqual(try reportExpectations.int("checked"), 1)
        XCTAssertEqual(try reportExpectations.int("met"), 1)
        XCTAssertTrue(response.compactFormatted().contains("heist: 2 top-level steps in 5ms"))
        XCTAssertTrue(response.compactFormatted().contains("[expectations: 1/1]"))
        XCTAssertTrue(response.humanFormatted().contains("Heist: 2 top-level step(s) executed in 5ms"))
        XCTAssertTrue(response.humanFormatted().contains("[expectations: 1/1 met]"))
    }

    func testPublicHeistJSONIncludesScoreMetricProjection() throws {
        let expected = AccessibilityPredicate<RootContext>.exists(.label("Done"))
        let command = HeistActionCommand.activate(.predicate(ElementPredicateTemplate(label: "Submit")))
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: command, expectationPolicy: .expect(ActionExpectation(
                predicate: expected,
                timeout: 1
            )))),
        ])
        let result = HeistExecutionResult(
            steps: [
                actionReceiptStep(
                    command: command,
                    result: ActionResult.success(
                        method: .activate,
                        timing: ActionPerformanceTiming(targetResolutionMs: 1, totalMs: 5)
                    ),
                    expectationActionResult: ActionResult.success(
                        method: .wait,
                        timing: ActionPerformanceTiming(settleMs: 7, totalMs: 9)
                    ),
                    expectation: ExpectationResult(met: true, predicate: expected)
                ),
            ],
            durationMs: 12
        )

        let metrics = try publicHeistReportJSON(
            FenceResponse.heistExecution(plan: plan, result: result)
        ).object("metrics").decode(HeistExecutionMetricProjection.self)

        XCTAssertEqual(metrics.samples.map(MetricSampleExpectation.init(sample:)), [
            MetricSampleExpectation(name: "heistDurationMs", valueMs: 12, path: nil),
            MetricSampleExpectation(name: "actionPipeline.targetResolutionMs", valueMs: 1, path: "$.body[0]"),
            MetricSampleExpectation(name: "actionPipeline.totalMs", valueMs: 5, path: "$.body[0]"),
            MetricSampleExpectation(name: "waitPipeline.settleMs", valueMs: 7, path: "$.body[0]"),
            MetricSampleExpectation(name: "waitPipeline.totalMs", valueMs: 9, path: "$.body[0]"),
            MetricSampleExpectation(name: "expectationWaitMs", valueMs: 9, path: "$.body[0]"),
        ])
    }

    func testExplicitSingleActionHeistKeepsReportShapeAcrossPublicFormats() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: "Pay"))))),
        ])
        let result = HeistExecutionResult(
            steps: [
                actionReceiptStep(
                    command: .activate(.predicate(ElementPredicateTemplate(label: "Pay"))),
                    result: ActionResult.success(method: .activate)
                ),
            ],
            durationMs: 3
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

        let json = try publicJSONProbe(response)
        let compact = response.compactFormatted()

        XCTAssertEqual(try json.string("status"), "ok")
        try json.assertPresent("report")
        try json.assertMissing("method")
        XCTAssertTrue(compact.contains("heist: 1 top-level steps in 3ms"), compact)
        XCTAssertTrue(compact.contains("[0] activate"), compact)
    }

    func testPublicHeistJSONProjectsNetDeltaInsideReport() throws {
        let plan = try HeistPlan(body: [
            .action(ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: "Pay"))))),
        ])
        let response = FenceResponse.heistExecution(
            plan: plan,
            result: HeistExecutionResult(
                steps: [
                    actionReceiptStep(
                        command: .activate(.predicate(ElementPredicateTemplate(label: "Pay"))),
                        result: ActionResult.success(method: .activate)
                    ),
                ],
                durationMs: 3
            ),
            accessibilityTrace: makeReceiptTestTrace(
                before: makeReceiptTestInterface(elementCount: 0),
                after: makeReceiptTestInterface(elementCount: 2)
            )
        )

        let json = try publicJSONProbe(response)
        let reportProbe = try json.object("report")
        let netDeltaProbe = try reportProbe.object("netDelta")

        try assertHeistReportRootOmitsSummaryDuplicates(json)
        XCTAssertEqual(try netDeltaProbe.string("kind"), "elementsChanged")
        XCTAssertEqual(try netDeltaProbe.int("elementCount"), 2)
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

        let json = try publicJSONProbe(response)
        let node = try XCTUnwrap(try json.object("report").array("nodes").first)

        XCTAssertEqual(try json.string("status"), "partial")
        try json.assertMissing("results")
        XCTAssertEqual(try node.string("path"), "$.body[0]")
        XCTAssertEqual(try node.string("kind"), "fail")
        XCTAssertEqual(try node.string("status"), "failed")
        XCTAssertEqual(try node.string("message"), "Unknown screen")
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
                    kind: .warn,
                    durationMs: 0
                ),
            ],
            durationMs: 2,
            abortedAtPath: "$.body[1]"
        )
        let response = FenceResponse.heistExecution(plan: plan, result: result)

        let json = try publicJSONProbe(response)
        let report = try json.object("report")
        let nodes = try report.array("nodes")
        let compact = response.compactFormatted()

        try assertHeistReportRootOmitsSummaryDuplicates(json)
        try assertPublicHeistSummary(
            report.object("summary"),
            executedTopLevelStepCount: 2,
            executedNodeCount: 2,
            outputReceiptNodeCount: 3,
            durationMs: 2,
            abortedAtPath: "$.body[1]"
        )
        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(try nodes.map { try $0.string("path") }, ["$.body[0]", "$.body[1]", "$.body[2]"])
        XCTAssertEqual(try nodes.map { try $0.string("status") }, ["passed", "failed", "skipped"])
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
            command: .activate(.predicate(ElementPredicateTemplate(label: "Continue")))
        ))
        let casePredicate = AccessibilityPredicate<ScreenAssertionContext>.exists(.label("Ready"))
        let casePredicateRuntime = AccessibilityPredicate<RootContext>.exists(.label("Ready"))
        let conditional = try ConditionalStep(cases: [
            PredicateCase(predicate: casePredicate, body: [childAction]),
        ])
        let plan = try HeistPlan(body: [.conditional(conditional)])
        let childPath = "$.body[0].conditional.cases[0].body[0]"
        let childResult = actionReceiptStep(
            path: childPath,
            command: .activate(.predicate(ElementPredicateTemplate(label: "Continue"))),
            result: ActionResult.failure(
                method: .activate,
                errorKind: .actionFailed,
                message: "nested button failed"),
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
                                predicate: casePredicateRuntime,
                                result: ExpectationResult(met: true, predicate: casePredicateRuntime)
                            ),
                        ],
                        outcome: .matchedCase(index: 0),
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

        let json = try publicJSONProbe(.heistExecution(plan: plan, result: result))
        let nodes = try json.object("report").array("nodes")
        let root = try XCTUnwrap(nodes.first)
        let children = try root.array("children")
        let child = try XCTUnwrap(children.first)
        let caseSelection = try root.object("evidence").object("caseSelection")
        let action = try child.object("evidence").object("action")
        let actionResult = try action.object("result")

        try json.assertMissing("results")
        XCTAssertEqual(try root.string("path"), "$.body[0]")
        XCTAssertEqual(try root.string("kind"), "conditional")
        try caseSelection.assertPresent("outcome")
        try caseSelection.assertMissing("selectedCaseIndex")
        try caseSelection.assertMissing("timedOut")
        try caseSelection.assertMissing("elseRan")
        XCTAssertEqual(try root.string("abortedAtChildPath"), childPath)
        XCTAssertEqual(try child.string("path"), "$.body[0].conditional.cases[0].body[0]")
        XCTAssertEqual(try child.string("kind"), "action")
        XCTAssertEqual(try child.string("status"), "failed")
        try child.assertMissing("action")
        XCTAssertEqual(try action.string("commandName"), "activate")
        XCTAssertEqual(try actionResult.string("status"), "error")
        XCTAssertEqual(try actionResult.string("message"), "nested button failed")
    }

    func testPublicHeistJSONReportsSelectedElsePathAsTreeNodes() throws {
        let elseStep = try HeistStep.action(ActionStep(
            command: .activate(.predicate(ElementPredicateTemplate(label: "Fallback")))
        ))
        let predicate = AccessibilityPredicate<ScreenAssertionContext>.exists(.label("Home"))
        let runtimePredicate = AccessibilityPredicate<RootContext>.exists(.label("Home"))
        let conditional = try ConditionalStep(
            cases: [
                PredicateCase(
                    predicate: predicate,
                    body: [try HeistStep.action(ActionStep(command: .activate(.predicate(ElementPredicateTemplate(label: "Home")))))]
                ),
            ],
            elseBody: [elseStep]
        )
        let plan = try HeistPlan(body: [.conditional(conditional)])
        let childPath = "$.body[0].conditional.else_body[0]"
        let childResult = actionReceiptStep(
            path: childPath,
            command: .activate(.predicate(ElementPredicateTemplate(label: "Fallback"))),
            result: ActionResult.success(method: .activate)
        )
        let result = HeistExecutionResult(
            steps: [
                caseReceiptStep(
                    kind: .conditional,
                    status: .passed,
                    selection: HeistCaseSelectionResult(
                        cases: [
                            HeistCaseMatchResult(
                                predicate: runtimePredicate,
                                result: ExpectationResult(met: false, predicate: runtimePredicate)
                            ),
                        ],
                        outcome: .elseBranch(reason: .noMatch),
                        elapsedMs: 1,
                        lastObservedSummary: nil
                    ),
                    children: [childResult]
                ),
            ],
            durationMs: 3
        )

        let json = try publicJSONProbe(.heistExecution(plan: plan, result: result))
        let nodes = try json.object("report").array("nodes")
        let root = try XCTUnwrap(nodes.first)
        let evidence = try root.object("evidence")
        let children = try root.array("children")
        let child = try XCTUnwrap(children.first)
        let compact = FenceResponse.heistExecution(plan: plan, result: result).compactFormatted()

        XCTAssertEqual(try root.string("kind"), "conditional")
        XCTAssertEqual(try root.string("status"), "passed")
        try evidence.assertPresent("caseSelection")
        XCTAssertEqual(try child.string("path"), "$.body[0].conditional.else_body[0]")
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
                    result: ActionResult.success(method: .typeText)
                ),
            ]
        )
        let failedActionPath = "$.body[0].for_each_string.iterations[1].body[0]"
        let failedAction = actionReceiptStep(
            path: failedActionPath,
            command: .typeText(text: .ref("item"), target: nil),
            result: ActionResult.failure(
                method: .typeText,
                errorKind: .elementNotFound,
                message: "field missing"),
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

        let json = try publicJSONProbe(response)
        let report = try json.object("report")
        let nodeProbes = try json.object("report").array("nodes")
        let rootProbe = try XCTUnwrap(nodeProbes.first)
        let evidence = try rootProbe.object("evidence")
        let children = try rootProbe.array("children")
        let compact = response.compactFormatted()

        try assertHeistReportRootOmitsSummaryDuplicates(json)
        try assertPublicHeistSummary(
            report.object("summary"),
            executedTopLevelStepCount: 1,
            executedNodeCount: 5,
            outputReceiptNodeCount: 5,
            durationMs: 30,
            abortedAtPath: failedActionPath
        )
        XCTAssertEqual(try rootProbe.string("kind"), "for_each_string")
        try evidence.assertPresent("forEachString")
        XCTAssertEqual(try rootProbe.string("abortedAtChildPath"), failedActionPath)
        XCTAssertEqual(try children.map { try $0.string("kind") }, ["for_each_iteration", "for_each_iteration"])
        XCTAssertTrue(compact.contains("heist: 1 top-level steps in 30ms"), compact)
        XCTAssertTrue(compact.contains("[0] for_each_string -> error: for_each_string stopped"), compact)
    }

    private func assertHeistReportRootOmitsSummaryDuplicates(
        _ json: JSONProbe,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        do {
            try json.assertMissing("executedTopLevelStepCount")
            try json.assertMissing("executedNodeCount")
            try json.assertMissing("outputReceiptNodeCount")
            try json.assertMissing("durationMs")
            try json.assertMissing("abortedAtPath")
            try json.assertMissing("expectations")
            try json.assertMissing("netDelta")
        } catch {
            XCTFail("\(error)", file: file, line: line)
            throw error
        }
    }

    func testCompactInterfaceRendersNestedContainersAndElements() {
        let output = FenceResponse.compactInterface(formattingFixtureInterface(), detail: .summary)

        XCTAssertEqual(output, """
        4 elements
        ── group "Actions" id="actions" "semantic_actions__actions" ──
          [0] "Submit" button
          ── table rows=3 columns=4 "orders_table" ──
            [1] "Order ID" staticText
          ── /orders_table ──
          ── tab_bar "main_tabs" ──
            [2] "Home" tabBarItem
          ── /main_tabs ──
        ── /semantic_actions__actions ──
        ── container "main_scroll" 1 elements modal ──
          390×400 view, 390×1200 content (4 pages), vertical
          [3] "Bottom" staticText
        ── /main_scroll ──
        """)
        XCTAssertFalse(output.contains("<"), output)
        XCTAssertFalse(output.contains("semanticGroup"), output)
        XCTAssertFalse(output.contains("dataTable"), output)
        XCTAssertFalse(output.contains("tabBar containerName"), output)
        XCTAssertFalse(output.contains("stableId"), output)
    }

    func testCompactInterfaceStartsWithSummaryElementLabel() {
        let interface = makeReceiptTestInterface([
            makeReceiptTestElement(label: "Inbox", traits: [.header]),
            makeReceiptTestElement(label: "Messages", traits: [.summaryElement]),
            makeReceiptTestElement(label: "Search", traits: [.searchField]),
        ])

        let output = FenceResponse.compactInterface(interface, detail: .summary)

        XCTAssertEqual(output, """
        Messages
        3 elements
        [0] "Inbox" header
        [1] "Messages" summaryElement
        [2] "Search" searchField
        """)
    }

    func testInterfaceRendersScreenActionsInCompactAndJSON() throws {
        let interface = formattingFixtureInterface().withScreenActions([.dismiss, .magicTap])
        let compact = FenceResponse.compactInterface(interface, detail: .summary)
        let json = try publicInterfaceJSONProbe(PublicInterface(interface: interface, detail: .summary))

        XCTAssertTrue(compact.hasPrefix("Actions: dismiss, magicTap\n4 elements"), compact)
        XCTAssertEqual(try json.strings("screenActions"), ["dismiss", "magicTap"])
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
            """
            ── container "horizontal_scroll" 1 elements ──
              390×400 view, 1200×400 content (4 pages), horizontal
            """
        let expectedBothSummary =
            """
            ── container "both_axis_scroll" 1 elements ──
              390×400 view, 1200×1200 content (4 pages), both
            """

        XCTAssertTrue(
            horizontalOutput.contains(expectedHorizontalSummary),
            horizontalOutput
        )
        XCTAssertFalse(horizontalOutput.contains("vertical"), horizontalOutput)
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
        ── container "long_scroll" 4 elements ──
          390×400 view, 390×1200 content (4 pages), vertical
          [0] "Row 0" staticText
          [1] "Row 1" staticText
          ⋮ 2 more
        ── /long_scroll ──
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
        ── group "Outer" "outer" ──
          ── group "Empty" "empty" ──
          ── /empty ──
        ── /outer ──
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
        XCTAssertTrue(output.contains(#"── container "outer_scroll" 5 elements ──"#), output)
        XCTAssertTrue(output.contains(#"── container "inner_scroll" 3 elements ──"#), output)
        XCTAssertTrue(output.contains("⋮ 2 more"), output)
        XCTAssertTrue(output.contains("⋮ 3 more"), output)
    }

    func testPublicInterfaceJSONRendersScrollSummaryFields() throws {
        let response = FenceResponse.interface(formattingFixtureInterface(), detail: .summary)

        let interface = try publicJSONProbe(response).object("interface")
        let rendering = try interface.object("rendering")
        let tree = try interface.array("tree")
        let scrollContainer = try tree[1].object("container")

        XCTAssertEqual(try rendering.string("state"), "full")
        try rendering.assertMissing("reasonCode")
        XCTAssertEqual(try rendering.int("observedElementCount"), 4)
        XCTAssertEqual(try rendering.int("renderedElementCount"), 4)
        XCTAssertEqual(try rendering.int("omittedElementCount"), 0)
        try rendering.assertMissing("visibleElementBudget")
        try rendering.assertMissing("totalNodeBudget")
        XCTAssertEqual(try scrollContainer.string("type"), "none")
        XCTAssertEqual(try scrollContainer.double("contentWidth"), 390)
        XCTAssertEqual(try scrollContainer.double("contentHeight"), 1200)
        XCTAssertEqual(try scrollContainer.string("scrollAxis"), "vertical")
        try scrollContainer.assertMissing("pageScrollsX")
        XCTAssertEqual(try scrollContainer.int("pageScrollsY"), 3)
        XCTAssertEqual(try scrollContainer.int("observedElementCount"), 1)
        try scrollContainer.assertMissing("truncation")
    }

    func testPublicInterfaceOutputIncludesDiscoveryLimitDiagnostics() throws {
        let diagnostics = InterfaceDiagnostics(discovery: InterfaceDiscoveryDiagnostics(
            state: .limited,
            reasonCodes: [.discoveryScrollLimit],
            includedElementCount: 2,
            scrollAttempts: 5,
            maxScrollsPerDiscovery: 5,
            maxScrollsPerContainer: 3,
            exploredScrollableContainerCount: 1,
            omittedScrollableContainerCount: 1,
            omittedContainers: [
                InterfaceDiscoveryOmittedContainer(
                    containerName: "main_scroll",
                    type: .none,
                    reasonCodes: [.discoveryScrollLimit],
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
        let json = try publicInterfaceJSONProbe(PublicInterface(interface: interface, detail: .summary))
        let discovery = try json.object("diagnostics").object("discovery")
        let omittedContainers = try discovery.array("omittedContainers")
        let omitted = try XCTUnwrap(omittedContainers.first)

        XCTAssertTrue(
            compact.contains(
                "discovery: limited[scroll-attempt-budget] includedElements=2 scrollAttempts=5/5"
            ),
            compact
        )
        XCTAssertTrue(compact.contains(#"omitted: none containerName="main_scroll""#), compact)
        XCTAssertTrue(compact.contains("next: Retry get_interface"), compact)
        XCTAssertEqual(try discovery.string("state"), "limited")
        XCTAssertEqual(try discovery.strings("reasonCodes"), ["scroll-attempt-budget"])
        XCTAssertEqual(try discovery.int("includedElementCount"), 2)
        XCTAssertEqual(try discovery.int("scrollAttempts"), 5)
        XCTAssertEqual(try discovery.int("maxScrollsPerDiscovery"), 5)
        XCTAssertEqual(try discovery.int("maxScrollsPerContainer"), 3)
        XCTAssertEqual(try discovery.int("omittedScrollableContainerCount"), 1)
        XCTAssertEqual(try omitted.string("containerName"), "main_scroll")
        XCTAssertEqual(try omitted.string("scrollAxis"), "vertical")
        XCTAssertEqual(try omitted.strings("reasonCodes"), ["scroll-attempt-budget"])
    }

    func testPublicInterfaceJSONProjectsScrollableContainerAsScrollable() throws {
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
                ]
            ),
        ])

        let dto = try publicInterfaceContractDTO(interface)
        let container = try XCTUnwrap(dto.topLevelContainers.first)

        XCTAssertEqual(container.type, "none")
        XCTAssertNotEqual(container.type, "scrollable")
        XCTAssertEqual(container.containerName, "main_scroll")
        XCTAssertEqual(container.contentWidth, 390)
        XCTAssertEqual(container.contentHeight, 1_200)
        XCTAssertEqual(container.scrollAxis, "vertical")
        XCTAssertEqual(container.pageScrollsY, 3)
    }

    func testPublicInterfaceJSONKeepsNonScrollableContainerTypesDistinct() throws {
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestSemanticContainer(label: "Actions", value: "Primary", identifier: "actions"),
                containerName: "actions_group",
                children: []
            ),
            .container(
                makeReceiptTestContainer(type: .list),
                containerName: "rows_list",
                children: []
            ),
            .container(
                makeReceiptTestContainer(type: .landmark),
                containerName: "main_landmark",
                children: []
            ),
            .container(
                makeReceiptTestContainer(type: .dataTable(rowCount: 3, columnCount: 2, cells: [])),
                containerName: "prices_table",
                children: []
            ),
            .container(
                makeReceiptTestContainer(type: .tabBar),
                containerName: "primary_tabs",
                children: []
            ),
        ])

        let containers = try publicInterfaceContractDTO(interface).topLevelContainers

        XCTAssertEqual(containers.map(\.type), [
            "semanticGroup",
            "list",
            "landmark",
            "dataTable",
            "tabBar",
        ])
        XCTAssertEqual(containers[0].label, "Actions")
        XCTAssertEqual(containers[0].value, "Primary")
        XCTAssertEqual(containers[0].identifier, "actions")
        XCTAssertEqual(containers[1].containerName, "rows_list")
        XCTAssertEqual(containers[3].rowCount, 3)
        XCTAssertEqual(containers[3].columnCount, 2)
    }

    func testPublicInterfaceOutputRendersContainerCustomActions() throws {
        let interface = makeReceiptTestInterface(nodes: [
            .container(
                makeReceiptTestContainer(
                    type: .none,
                    customActions: [AccessibilityElement.CustomAction(name: "Archive")]
                ),
                containerName: "archive_container",
                children: []
            ),
        ])

        let compact = FenceResponse.compactInterface(interface, detail: .summary)
        let human = FenceResponse.interface(interface, detail: .summary).humanFormatted()
        let container = try XCTUnwrap(try publicInterfaceContractDTO(interface).topLevelContainers.first)

        XCTAssertTrue(compact.contains(#"── container "archive_container" actions="Archive" ──"#), compact)
        XCTAssertTrue(human.contains(#"container containerName: archive_container actions="Archive""#), human)
        XCTAssertEqual(container.actions, ["Archive"])
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

        let json = try publicInterfaceJSONProbe(
            PublicInterface(interface: interface, detail: .summary, visibleElementBudget: 2)
        )
        let rendering = try json.object("rendering")
        let tree = try json.array("tree")
        let scrollContainer = try tree[0].object("container")
        let scrollChildren = try scrollContainer.array("children")
        let truncation = try scrollContainer.object("truncation")
        let after = try tree[1].object("element")

        XCTAssertEqual(try rendering.string("state"), "truncated")
        XCTAssertEqual(try rendering.string("reasonCode"), "scroll-subtree-element-budget")
        XCTAssertEqual(try rendering.int("observedElementCount"), 5)
        XCTAssertEqual(try rendering.int("renderedElementCount"), 3)
        XCTAssertEqual(try rendering.int("omittedElementCount"), 2)
        XCTAssertEqual(try rendering.int("visibleElementBudget"), 2)
        try rendering.assertMissing("totalNodeBudget")
        XCTAssertEqual(scrollChildren.count, 2)
        XCTAssertEqual(try scrollContainer.int("observedElementCount"), 4)
        XCTAssertEqual(try truncation.string("state"), "truncated")
        XCTAssertEqual(try truncation.string("reasonCode"), "scroll-subtree-element-budget")
        XCTAssertEqual(try truncation.int("observedElementCount"), 4)
        XCTAssertEqual(try truncation.int("renderedElementCount"), 2)
        XCTAssertEqual(try truncation.int("omittedElementCount"), 2)
        XCTAssertEqual(try truncation.int("visibleElementBudget"), 2)
        XCTAssertEqual(try after.string("label"), "After")
        XCTAssertEqual(try after.int("order"), 4)
    }

    func testPublicInterfaceJSONTruncatesWholeInterfaceAtTotalNodeBudget() throws {
        let rows = (0..<4).map { index in
            ReceiptTestInterfaceNode.element(makeReceiptTestElement(label: "Row \(index)"))
        }
        let interface = makeReceiptTestInterface(nodes: rows)

        let json = try publicInterfaceJSONProbe(
            PublicInterface(
                interface: interface,
                detail: .summary,
                visibleElementBudget: 10,
                totalNodeBudget: 2
            )
        )
        let rendering = try json.object("rendering")
        let tree = try json.array("tree")

        XCTAssertEqual(try rendering.string("state"), "truncated")
        XCTAssertEqual(try rendering.string("reasonCode"), "total-node-budget")
        XCTAssertEqual(try rendering.int("observedElementCount"), 4)
        XCTAssertEqual(try rendering.int("renderedElementCount"), 2)
        XCTAssertEqual(try rendering.int("omittedElementCount"), 2)
        try rendering.assertMissing("visibleElementBudget")
        XCTAssertEqual(try rendering.int("totalNodeBudget"), 2)
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

        let json = try publicInterfaceJSONProbe(
            PublicInterface(
                interface: interface,
                detail: .summary,
                totalNodeBudget: 2
            )
        )
        let rendering = try json.object("rendering")
        let tree = try json.array("tree")
        let outer = try tree[0].object("container")
        let children = try outer.array("children")
        let empty = try children[0].object("container")

        XCTAssertEqual(try rendering.string("state"), "truncated")
        XCTAssertEqual(try rendering.string("reasonCode"), "total-node-budget")
        XCTAssertEqual(try rendering.int("observedElementCount"), 1)
        XCTAssertEqual(try rendering.int("renderedElementCount"), 0)
        XCTAssertEqual(try rendering.int("omittedElementCount"), 1)
        XCTAssertEqual(try rendering.int("totalNodeBudget"), 2)
        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(try outer.string("containerName"), "outer")
        XCTAssertEqual(children.count, 1)
        XCTAssertEqual(try empty.string("containerName"), "empty")
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

        let json = try publicInterfaceJSONProbe(
            PublicInterface(
                interface: interface,
                detail: .summary,
                visibleElementBudget: 3,
                totalNodeBudget: 2
            )
        )
        let rendering = try json.object("rendering")
        let tree = try json.array("tree")
        let scrollContainer = try tree[0].object("container")

        XCTAssertEqual(try rendering.string("reasonCode"), "total-node-budget")
        try rendering.assertMissing("visibleElementBudget")
        XCTAssertEqual(try rendering.int("totalNodeBudget"), 2)
        try scrollContainer.assertMissing("truncation")
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

        XCTAssertTrue(output.contains(#"── group "Actions \"Primary\"\nPane" value="hot\u0001" id="actions\"id" "semantic\n\"actions" ──"#), output)
        XCTAssertFalse(output.contains("stableId"), output)
    }

    func testCompactSummaryOmitsContainerGeometryAndFullIncludesFrame() {
        let interface = formattingFixtureInterface()

        let summary = FenceResponse.compactInterface(interface, detail: .summary)
        let full = FenceResponse.compactInterface(interface, detail: .full)

        XCTAssertFalse(summary.contains("frame="), summary)
        XCTAssertTrue(
            full.contains(#"── group "Actions" id="actions" "semantic_actions__actions" frame=(0,40,200,100) ──"#),
            full
        )
        XCTAssertTrue(summary.contains(#"── container "main_scroll" 1 elements modal ──"#), summary)
        XCTAssertTrue(summary.contains("390×400 view, 390×1200 content (4 pages), vertical"), summary)
    }

    func testHumanInterfaceRendersHierarchyAndRespectsDetail() {
        let interface = formattingFixtureInterface()

        let summary = FenceResponse.interface(interface, detail: .summary).humanFormatted()
        let full = FenceResponse.interface(interface, detail: .full).humanFormatted()

        XCTAssertTrue(summary.contains(#"group "Actions" id="actions" containerName: semantic_actions__actions"#), summary)
        XCTAssertTrue(summary.contains(#"  [ 0] "Submit" traits=button actions=activate"#), summary)
        XCTAssertTrue(summary.contains(#"  table rows=3 columns=4 containerName: orders_table"#), summary)
        XCTAssertTrue(summary.contains(#"container containerName: main_scroll viewport=390x400 content=390x1200 modal=true"#), summary)
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
                #"── group "Actions" id="actions" "semantic_actions__actions" frame=(0,40,200,100) ──"#
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
        command: HeistActionCommand? = .activate(.predicate(ElementPredicateTemplate(label: "Button"))),
        result: ActionResult,
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
                dispatchResult: result,
                expectationResult: expectationActionResult,
                expectation: expectation
            )
        } else {
            precondition(expectationActionResult == nil && expectation == nil)
            evidence = command.map {
                .dispatch(command: $0, dispatchResult: result)
            } ?? .commandlessDispatch(dispatchResult: result)
        }

        let intent = command.map {
            HeistStepIntent.action(command: $0)
        }
        if let failure {
            return .failed(
                path: path,
                receiptKind: .action,
                durationMs: 1,
                intent: intent,
                evidence: evidence,
                failure: failure
            )
        }
        return .passed(
            path: path,
            receiptKind: .action,
            durationMs: 1,
            intent: intent,
            evidence: evidence
        )
    }

    private func warnReceiptStep(path: String, message: String) -> HeistExecutionStepResult {
        .passed(
            path: path,
            receiptKind: .warning,
            durationMs: 1,
            intent: .warn(message: message),
            evidence: HeistExecutionWarning(path: path, message: message)
        )
    }

    private func failReceiptStep(message: String) -> HeistExecutionStepResult {
        .failed(
            path: "$.body[0]",
            kind: .fail,
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
        let evidence = HeistCaseSelectionEvidence(selection: selection)
        if let abortedAtChildPath = children.firstFailedStep?.path {
            return .childAborted(
                path: "$.body[0]",
                receiptKind: .conditional,
                durationMs: 3,
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
                durationMs: 3,
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
            durationMs: 3,
            intent: .conditional,
            evidence: evidence,
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
        let path = "$.body[0].for_each_string.iterations[\(ordinal)]"
        let evidence = HeistForEachStringEvidence(
            parameter: "item",
            count: 2,
            iterationCount: 2,
            iterationOrdinal: ordinal,
            value: value,
            failureReason: failureReason
        )
        let failure = failureReason.map {
            HeistFailureDetail(
                category: .loop,
                contract: "iteration \(ordinal) completes",
                observed: $0
            )
        }
        if let abortedAtChildPath = children.firstFailedStep?.path {
            return .childAborted(
                path: path,
                receiptKind: .forEachStringIteration,
                durationMs: 1,
                evidence: evidence,
                failure: failure ?? HeistFailureDetail(
                    category: .loop,
                    contract: "iteration \(ordinal) completes",
                    observed: "child failed at \(abortedAtChildPath)"
                ),
                abortedAtChildPath: abortedAtChildPath,
                children: children
            )
        }
        if status == .failed {
            return .failed(
                path: path,
                receiptKind: .forEachStringIteration,
                durationMs: 1,
                evidence: evidence,
                failure: failure ?? HeistFailureDetail(
                    category: .loop,
                    contract: "iteration \(ordinal) completes",
                    observed: "iteration failed"
                ),
                children: children
            )
        }
        return .passed(
            path: path,
            receiptKind: .forEachStringIteration,
            durationMs: 1,
            evidence: evidence,
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
                            type: .dataTable(rowCount: 3, columnCount: 4, cells: []),
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

private func publicInterfaceContractDTO(
    _ interface: Interface,
    detail: InterfaceDetail = .summary
) throws -> PublicInterfaceContractDTO {
    let data = try JSONEncoder().encode(PublicInterface(interface: interface, detail: detail))
    return try JSONDecoder().decode(PublicInterfaceContractDTO.self, from: data)
}

private struct PublicInterfaceContractDTO: Decodable {
    let tree: [PublicInterfaceTreeNodeContractDTO]

    var topLevelContainers: [PublicInterfaceContainerContractDTO] {
        tree.compactMap(\.container)
    }
}

private struct PublicInterfaceTreeNodeContractDTO: Decodable {
    let container: PublicInterfaceContainerContractDTO?
}

private struct PublicInterfaceContainerContractDTO: Decodable {
    let type: String
    let label: String?
    let value: String?
    let identifier: String?
    let rowCount: Int?
    let columnCount: Int?
    let actions: [String]?
    let contentWidth: Double?
    let contentHeight: Double?
    let scrollAxis: String?
    let pageScrollsY: Int?
    let containerName: String?
    let children: [PublicInterfaceTreeNodeContractDTO]
}
