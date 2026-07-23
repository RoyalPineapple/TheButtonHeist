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
                screenActionHandler: "UINavigationController"
            )
        )

        XCTAssertEqual(response.compactFormatted(), "perform: ok\nHandler: UINavigationController")
        XCTAssertEqual(response.humanFormatted(), "✓ perform  Handler: UINavigationController")

        let json = try publicJSONProbe(response)
        XCTAssertNoThrow(try json.assertMissing("message"))
        XCTAssertEqual(try json.string("screenActionHandler"), "UINavigationController")
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

    func testMatchedAnnouncementExpectationWinsOverUnrelatedTraceAnnouncement() throws {
        let response = FenceResponse.action(
            command: .wait,
            result: ActionResult.success(
                payload: .wait,
                observation: .announcement("AXPerformElementUpdateImmediatelyToken")
            ),
            expectation: ExpectationResult(
                met: true,
                predicate: .announcement("Ticket saved."),
                actual: "Ticket saved."
            )
        )

        XCTAssertTrue(response.compactFormatted().contains("announcement: \"Ticket saved.\""))
        XCTAssertEqual(try publicJSONProbe(response).string("announcement"), "Ticket saved.")
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
}
