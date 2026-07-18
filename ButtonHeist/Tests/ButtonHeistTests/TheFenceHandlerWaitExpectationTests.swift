import ButtonHeistTestSupport
import XCTest
import Network
import ButtonHeistSupport
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import ThePlans
@_spi(ButtonHeistInternals) import TheScore

extension TheFenceHandlerTests {
    // MARK: - Wait Validation

    @ButtonHeistActor
    func testWaitMissingPredicate() async {
        await assertValidationError(command: .wait, contains: "predicate")
    }

    @ButtonHeistActor
    func testWaitPredicateShapesPassValidation() async {
        let cases: [[String: HeistValue]] = [
            ["predicate": .object([
                "type": .string("exists"),
                "target": elementPredicateValue(label: "Loading"),
            ])],
            [
                "predicate": .object([
                    "type": .string("missing"),
                    "target": elementPredicateValue(label: "Loading"),
                ]),
                "timeout": .double(5),
            ],
            ["predicate": .object([
                "type": .string("changed"),
                "scope": .string("screen"),
                "assertions": .array([]),
            ])],
            [
                "predicate": .object([
                    "type": .string("changed"),
                    "scope": .string("elements"),
                    "assertions": .array([]),
                ]),
                "timeout": .double(5),
            ],
            ["predicate": .object([
                "type": .string("changed"),
                "scope": .string("screen"),
                "assertions": .array([
                    .object(["type": .string("exists"), "target": elementPredicateValue(label: "Done")]),
                    .object(["type": .string("missing"), "target": elementPredicateValue(label: "Loading")]),
                ]),
            ])],
            ["predicate": .object([
                "type": .string("changed"),
                "scope": .string("screen"),
                "assertions": .array([.object([
                    "type": .string("exists"),
                    "target": elementPredicateValue(label: "Home"),
                ])]),
            ])],
        ]

        for arguments in cases {
            await assertPassesValidation(command: .wait, arguments: arguments)
        }
    }

    @ButtonHeistActor
    func testWaitSendsDefaultMaximumTimeout() async {
        let (fence, mockConn) = makeConnectedFence()
        _ = try? await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("changed"),
                "scope": .string("screen"),
                "assertions": .array([]),
            ]),
            "timeout": .double(60.0),
        ])
        guard let step = mockConn.sent.sentWaitSteps.last else {
            return XCTFail("Expected wait step")
        }
        XCTAssertEqual(step.predicate, .changed(.screen()))
        XCTAssertEqual(step.timeout, 60.0)
    }

    @ButtonHeistActor
    func testDirectWaitReturnsHeistExecutionBeforeFormatting() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let scriptedResult = HeistReceiptFixture.result(steps: [HeistReceiptFixture.wait()])
        mockConn.responseScript = { _ in scriptedHeistResponse(scriptedResult) }

        let response = try await fence.execute(command: .wait, values: [
            "predicate": .object([
                "type": .string("changed"),
                "scope": .string("elements"),
                "assertions": .array([]),
            ]),
        ])

        assertDirectCommandHeistExecution(response, command: .wait, stepKind: .wait)
        let json = try publicJSONProbe(response).object()
        try json.assertMissing("method")
        try json.assertPresent("report")
    }

    @ButtonHeistActor
    func testInvalidExpectationIsRejectedBeforeDispatch() async throws {
        let (fence, mockConn) = makeConnectedFence()

        let response = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "expect": .string("change"),
        ])

        guard case .error(let failure) = response else {
            return XCTFail("Expected .error response, got \(response)")
        }
        XCTAssertFalse(failure.message.isEmpty)
        XCTAssertTrue(mockConn.sent.isEmpty)
    }

    @ButtonHeistActor
    func testActionExpectationIsSentAsServerSideExpectationStep() async throws {
        let (fence, mockConn) = makeConnectedFence()
        let predicate = AccessibilityPredicate.exists(.label("Home"))

        _ = try await fence.execute(command: .activate, values: [
            "target": targetValue(identifier: "myElement"),
            "expect": .object([
                "type": .string("exists"),
                "target": elementPredicateValue(label: "Home"),
            ]),
        ])

        // The action and its expectation cross the wire as one heist plan; the
        // expectation is a server-side step on the action, not a separate
        // client-issued wait round-trip.
        XCTAssertEqual(mockConn.sent.count, 1)
        guard case .action(let step)? = mockConn.sent.sentHeistPlan?.body.first else {
            return XCTFail("Expected a single action step, got \(String(describing: mockConn.sent.sentHeistPlan))")
        }
        XCTAssertEqual(step.expectationPolicy.expectedStep?.predicate, predicate)
    }

    // MARK: - Expectation Parsing

    @ButtonHeistActor
    func testParseExpectationNilWhenAbsent() async throws {
        let result = try parseTypedExpectation(nil)
        XCTAssertNil(result)
    }

    @ButtonHeistActor
    func testParseExpectationScreenChangedObject() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("changed"),
            "scope": .string("screen"),
            "assertions": .array([]),
        ]))
        XCTAssertEqual(result, .changed(.screen()))
    }

    @ButtonHeistActor
    func testParseExpectationRejectsGenericChangedPredicate() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("changed"),
            "assertions": .array([]),
        ]))) { error in
            XCTAssertTrue(String(describing: error).contains("scope"), "Unexpected error: \(error)")
        }
    }

    func testNormalizeToolCallRoutesWithoutParsingRequestArguments() throws {
        let result = TheFence.Command.routeToolCall(named: "perform")

        guard case .success(let command) = result else {
            return XCTFail("Expected successful command, got \(result)")
        }

        XCTAssertEqual(command, .perform)
    }

    func testNormalizeToolCallRejectsNonMCPCommands() {
        for tool in ["activate", "type_text", "wait", "swipe", "scroll", "help"] {
            let result = TheFence.Command.routeToolCall(named: tool)

            guard case .failure(let error) = result else {
                return XCTFail("Expected non-MCP command rejection, got \(result)")
            }

            XCTAssertEqual(error.message, "Unknown tool: \(tool)")
        }
    }

    @ButtonHeistActor
    func testHeistPlanCarriesTypedActionExpectation() async throws {
        let expectation = AccessibilityPredicate.changed(.elements([
            .updated(.identifier("counter"), .value(after: "5")),
        ]))
        let sourceStep = HeistStep.action(ActionStep(
            command: .activate(.predicate(ElementPredicateTemplate(identifier: .exact("counter")))),
            expectationPolicy: .expect(ActionExpectation(predicate: expectation, timeout: 10))))
        let plan = try HeistPlan(body: [sourceStep])
        guard case .action(let action)? = plan.body.first else {
            return XCTFail("Expected action step")
        }

        XCTAssertEqual(action.expectationPolicy.expectedStep?.predicate, expectation)
    }

    // MARK: - Parse Expectation: Discriminator Wire Shape

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedFull() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("changed"),
            "scope": .string("elements"),
            "assertions": .array([.object([
                "type": .string("updated"),
                "target": elementPredicateValue(identifier: "slider"),
                "before": stringMatchValue(mode: "exact", value: "0"),
                "after": stringMatchValue(mode: "exact", value: "50"),
                "property": .string("value"),
            ])]),
        ]))
        XCTAssertEqual(
            result,
            .changed(.elements([
                .updated(.identifier("slider"), .value(before: "0", after: "50")),
            ]))
        )
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedInvalidPropertyListsValidValues() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("changed"),
            "scope": .string("elements"),
            "assertions": .array([.object([
                "type": .string("updated"),
                "target": elementPredicateValue(identifier: "slider"),
                "property": .string("bogus"),
            ])]),
        ]))) { error in
            guard case FenceError.invalidRequest(let msg) = error else {
                XCTFail("Expected FenceError.invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("ElementProperty"), msg)
            XCTAssertTrue(msg.contains("bogus"), msg)
        }
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorElementUpdatedRequiresTargetAndProperty() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("changed"),
            "scope": .string("elements"),
            "assertions": .array([.object(["type": .string("updated")])]),
        ])))
    }

    @ButtonHeistActor
    func testParseExpectationDiscriminatorPresentWithElement() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("exists"),
            "target": elementPredicateValue(label: "Cart", identifier: "cart.button"),
        ]))
        XCTAssertEqual(
            result,
            .exists(.predicate(ElementPredicateTemplate(label: "Cart", identifier: "cart.button")))
        )
    }

    @ButtonHeistActor
    func testParseExpectationAcceptsContainerTarget() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("exists"),
            "target": .object([
                "container": .object([
                    "checks": .array([.object([
                        "kind": .string("scrollable"),
                        "value": .bool(true),
                    ])]),
                ]),
            ]),
        ]))

        XCTAssertEqual(result, .exists(.container(.matching(.scrollable(true)))))
    }

    @ButtonHeistActor
    func testParseExpectationPreservesTargetRefsForExecutionResolution() async throws {
        let item: HeistReferenceName = "item"
        let result = try parseTypedExpectation(.object([
            "type": .string("exists"),
            "target": .object(["ref": .string("item")]),
        ]))

        XCTAssertEqual(result, .exists(.ref(item)))
    }

    @ButtonHeistActor
    func testParseExpectationTypedPayloadPreservesTargetTraits() async throws {
        let result = try parseTypedExpectation(.object([
            "type": .string("missing"),
            "target": accessibilityTargetValue([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: "Spinner")),
                    predicateCheckValue(kind: "traits", values: [.string("button")]),
                    predicateCheckValue(
                        kind: "exclude",
                        check: predicateCheckValue(kind: "traits", values: [.string("selected")])
                    ),
                ]),
            ]),
        ]))

        XCTAssertEqual(
            result,
            .missing(.element(
                .label("Spinner"),
                .traits([.button]),
                .exclude(.traits([.selected]))
            ))
        )
    }

    @ButtonHeistActor
    func testParseExpectationAcceptsAnnouncementWithOptionalCanonicalMatch() async throws {
        let cases: [(value: HeistValue, expected: AccessibilityPredicate)] = [
            (.object(["type": .string("announcement")]), .announcement),
            (
                .object([
                    "type": .string("announcement"),
                    "match": stringMatchValue(mode: "contains", value: "Payment complete"),
                ]),
                .announcement(.contains("Payment complete"))
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(try parseTypedExpectation(testCase.value), testCase.expected)
        }
    }

    @ButtonHeistActor
    func testParseExpectationRejectsAnnouncementInChangedAssertionContexts() async {
        for (scope, context) in [("screen", "screen assertion"), ("elements", "elements assertion")] {
            XCTAssertThrowsError(try parseTypedExpectation(.object([
                "type": .string("changed"),
                "scope": .string(scope),
                "assertions": .array([.object([
                    "type": .string("announcement"),
                ])]),
            ]))) { error in
                XCTAssertTrue(String(describing: error).contains(context), "Unexpected error: \(error)")
            }
        }
    }

    @ButtonHeistActor
    func testCanonicalExpectationDecoderRejectsUnknownTargetFields() async {
        XCTAssertThrowsError(try parseTypedExpectation(.object([
            "type": .string("exists"),
            "target": .object([
                "checks": .array([
                    predicateCheckValue(kind: "label", match: stringMatchValue(mode: "exact", value: "Done")),
                ]),
                "unknown": .string("ignored before"),
            ]),
        ])))
    }

}
