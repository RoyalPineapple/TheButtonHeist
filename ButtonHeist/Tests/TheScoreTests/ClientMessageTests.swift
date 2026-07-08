import ButtonHeistTestSupport
import XCTest
import ThePlans
@_spi(ButtonHeistInternals) import TheScore

final class ClientMessageTests: XCTestCase {

    func testClientHelloRoundTrip() throws {
        let message = ClientMessage.clientHello
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        guard case .clientHello = decoded else {
            return XCTFail("Expected clientHello, got \(decoded)")
        }
    }

    func testRequestSnapshotEncodeDecode() throws {
        let message = ClientMessage.requestInterface(InterfaceQuery())
        let data = try JSONEncoder().encode(message)
        let object = try JSONProbe(data: data)
        XCTAssertEqual(try object.string("type"), "requestInterface")
        _ = try object.object("payload")

        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .requestInterface = decoded {
        } else {
            XCTFail("Expected requestInterface, got \(decoded)")
        }
    }

    func testRequestSnapshotRejectsMissingPayload() throws {
        let data = Data(#"{"type":"requestInterface"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: data))
    }

    func testRequestSnapshotRejectsInvalidDiscoveryLimits() throws {
        let data = Data(#"{"type":"requestInterface","payload":{"maxScrollsPerContainer":-1}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: data)) { error in
            XCTAssertTrue(
                "\(error)".contains("maxScrollsPerContainer must be between 1 and 2000"),
                "\(error)"
            )
        }
    }

    func testRequestEnvelopeRejectsServerOnlyMessageTypeAtTypedBoundary() {
        let data = Data("""
        {"buttonHeistVersion":"\(TheScore.buttonHeistVersion)","type":"serverHello"}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(RequestEnvelope.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertEqual(context.debugDescription, "Unsupported client wire message type: serverHello")
        }
    }

    func testRequestEnvelopeRejectsUnknownTopLevelField() throws {
        let data = Data("""
        {"buttonHeistVersion":"\(TheScore.buttonHeistVersion)","type":"ping","unknownField":"value"}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(RequestEnvelope.self, from: data)) { error in
            XCTAssertTrue(
                "\(error)".contains("unknownField"),
                "Expected unknown request envelope field in error, got \(error)"
            )
        }
    }

    func testClientMessageRejectsUnknownTopLevelField() throws {
        let data = Data(#"{"type":"ping","staleField":"value"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("staleField"), "\(error)")
        }
    }

    func testNoPayloadClientMessageRejectsStrayPayload() throws {
        let data = Data(#"{"type":"ping","payload":{"junk":true}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("ping must not include a payload"), "\(error)")
        }
    }

    func testNoPayloadRequestEnvelopeRejectsStrayPayload() throws {
        let data = Data("""
        {"buttonHeistVersion":"\(TheScore.buttonHeistVersion)","type":"ping","payload":{"junk":true}}
        """.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(RequestEnvelope.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("ping must not include a payload"), "\(error)")
        }
    }

    func testWireTypeMatchesEncodedType() throws {
        let messages: [ClientMessage] = [
            .clientHello,
            .requestInterface(InterfaceQuery()),
            .ping,
            .status,
            .getPasteboard,
            .getAnnouncements,
            .requestScreen(),
            .heistPlan(HeistPlanRun(plan: try HeistPlan(body: [
                .action(try ActionStep(
                    command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Save")))))
                )),
            ]))),
        ]

        for message in messages {
            let encoded = try JSONEncoder().encode(message)
            let wireType = try JSONDecoder().decode(EncodedClientMessageType.self, from: encoded).type

            XCTAssertEqual(message.wireType.rawValue, wireType, "\(message)")
        }
    }

    func testPingEncodeDecode() throws {
        let message = ClientMessage.ping
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .ping = decoded {
        } else {
            XCTFail("Expected ping, got \(decoded)")
        }
    }

    func testStatusEncodeDecode() throws {
        let message = ClientMessage.status
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .status = decoded {
        } else {
            XCTFail("Expected status, got \(decoded)")
        }
    }

    // MARK: - Heist Plan Tests

    func testHeistPlanClientMessageRoundTrip() throws {
        let saveTarget = ElementTarget.predicate(ElementPredicate(label: "Save", traits: [.button]))
        let plan = try HeistPlan(body: [
                .action(try ActionStep(
                    command: .activate(.target(saveTarget)),
                    expectationPolicy: .expect(ActionExpectation(predicate: .change(.screen()), timeout: 10)))),
                .wait(WaitStep(
                    predicate: .exists(ElementPredicate(label: "Save", traits: [.button])),
                    timeout: 2.5
                )),
                .wait(WaitStep(
                    predicate: .exists(ElementPredicate(label: "Done")),
                    timeout: 1.0
                )),
            ]
        )
        let message = ClientMessage.heistPlan(HeistPlanRun(plan: plan))

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        guard case .heistPlan(let decodedRun) = decoded else {
            return XCTFail("Expected heistPlan, got \(decoded)")
        }
        let decodedPlan = decodedRun.plan
        XCTAssertEqual(decodedRun.argument, HeistArgument.none)
        XCTAssertEqual(decodedPlan.body.count, 3)
        guard case .action(let decodedAction) = decodedPlan.body[0],
              case .activate(let decodedTarget) = decodedAction.command,
              decodedAction.expectationPolicy.expectedStep?.predicate == AccessibilityPredicateExpr.predicate(.change(.screen())) else {
            return XCTFail("Expected activate command with screen change predicate")
        }
        XCTAssertEqual(decodedTarget, ElementTargetExpr.target(saveTarget))
    }

    func testHeistPlanClientMessageRoundTripPreservesRootArgument() throws {
        let plan = try HeistPlan(
            name: "search",
            parameter: .string(name: "query"),
            body: [
                .action(try ActionStep(command: .typeText(
                    text: .ref("query"),
                    target: .target(.predicate(.label("Search")))
                ))),
            ]
        )
        let message = ClientMessage.heistPlan(HeistPlanRun(
            plan: plan,
            argument: .string(.literal("milk"))
        ))

        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        guard case .heistPlan(let decodedRun) = decoded else {
            return XCTFail("Expected heistPlan, got \(decoded)")
        }
        XCTAssertEqual(decodedRun.plan, plan)
        XCTAssertEqual(decodedRun.argument, .string(.literal("milk")))
    }

    func testHeistPlanEnvelopeRoundTrip() throws {
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .typeText(
                    text: .literal("hello"),
                    target: .predicate(ElementPredicateTemplate(identifier: .exact(.literal("nameField"))))
                )
            )),
        ])
        let envelope = RequestEnvelope(
            requestId: "heist-1",
            message: .heistPlan(HeistPlanRun(plan: plan))
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "heist-1")
        guard case .heistPlan(let decodedRun) = decoded.message,
              let step = decodedRun.plan.body.first,
              case .action(let action) = step,
              case .typeText(let text, let target, let replacingExisting) = action.command,
              action.expectationPolicy.expectedStep == nil else {
            return XCTFail("Expected heistPlan envelope, got \(decoded.message)")
        }
        XCTAssertEqual(text, StringExpr.literal("hello"))
        XCTAssertEqual(target, ElementTargetExpr.predicate(ElementPredicateTemplate(identifier: .exact(.literal("nameField")))))
        XCTAssertFalse(replacingExisting)
    }

    func testHeistActionDescriptionUsesNormalCommandIdentity() throws {
        let step = try ActionStep(
            command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Save"))))),
            expectationPolicy: .expect(ActionExpectation(predicate: .change(.screen()), timeout: 10)))

        XCTAssertEqual(
            step.description,
            #"action(command=activate expect=wait(change(screen(*)) timeout=10))"#
        )
    }

    func testPrimitiveMutatingRequestEnvelopeJSONIsRejected() throws {
        let primitiveRequests = [
            #"{"buttonHeistVersion":"\#(TheScore.buttonHeistVersion)","type":"activate","payload":{"label":"Save"}}"#,
            #"{"buttonHeistVersion":"\#(TheScore.buttonHeistVersion)","type":"wait","payload":{"predicate":{"type":"change","scopes":[{"type":"elements"}]}}}"#,
            #"{"buttonHeistVersion":"\#(TheScore.buttonHeistVersion)","type":"setPasteboard","payload":{"text":"clipboard"}}"#,
        ]

        for json in primitiveRequests {
            XCTAssertThrowsError(try JSONDecoder().decode(RequestEnvelope.self, from: Data(json.utf8)), json) { error in
                XCTAssertTrue("\(error)".contains("Unsupported client wire message type"), "\(error)")
            }
        }
    }

    func testPrimitiveMutatingClientMessageJSONIsRejected() throws {
        let primitiveMessages = [
            #"{"type":"activate","payload":{"label":"Save"}}"#,
            #"{"type":"typeText","payload":{"text":"hello"}}"#,
            #"{"type":"setPasteboard","payload":{"text":"clipboard"}}"#,
            #"{"type":"wait","payload":{"predicate":{"type":"change","scopes":[{"type":"elements"}]},"timeout":1}}"#,
        ]

        for json in primitiveMessages {
            XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)), json) { error in
                XCTAssertTrue("\(error)".contains("Unsupported client wire message type"), "\(error)")
            }
        }
    }

    func testSingleActivateWireShapeIsHeistPlan() throws {
        let plan = try HeistPlan(body: [
            .action(try ActionStep(
                command: .activate(.predicate(ElementPredicateTemplate(label: .exact(.literal("Log In")))))
            )),
        ])
        let message = ClientMessage.heistPlan(HeistPlanRun(plan: plan))
        let data = try JSONEncoder().encode(message)

        let object = try JSONProbe(data: data)
        XCTAssertEqual(try object.string("type"), "heistPlan")
        let body = try object.object("payload").object("plan").array("body")
        let firstStep = try XCTUnwrap(body.first)
        XCTAssertEqual(try firstStep.string("type"), "action")
    }

    func testRequestScreenshotEncodeDecode() throws {
        let message = ClientMessage.requestScreen()
        let data = try JSONEncoder().encode(message)
        let object = try JSONProbe(data: data)
        XCTAssertEqual(try object.string("type"), "requestScreen")
        try object.assertMissing("payload")

        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .requestScreen = decoded {
        } else {
            XCTFail("Expected requestScreen, got \(decoded)")
        }
    }

    func testRequestAccessibilityScreenshotEncodeDecode() throws {
        let envelope = RequestEnvelope(
            requestId: "screen-1",
            message: .requestScreen(ScreenRequestPayload(mode: .accessibility))
        )
        let data = try JSONEncoder().encode(envelope)
        let object = try JSONProbe(data: data)
        XCTAssertEqual(try object.string("type"), "requestScreen")
        XCTAssertEqual(try object.object("payload").string("mode"), "accessibility")

        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)
        if case .requestScreen(let payload) = decoded.message {
            XCTAssertEqual(payload.mode, .accessibility)
        } else {
            XCTFail("Expected requestScreen, got \(decoded.message)")
        }
    }

    func testRequestScreenshotRejectsUnknownPayloadField() throws {
        let data = Data(#"{"type":"requestScreen","payload":{"mode":"raw","stale":true}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: data)) { error in
            XCTAssertTrue("\(error)".contains("stale"), "\(error)")
        }
    }

    // MARK: - TypeText Tests

    func testTypeTextWithTextOnly() throws {
        let target = TypeTextTarget(text: "Hello")
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TypeTextTarget.self, from: data)

        XCTAssertEqual(decoded.text, "Hello")
        XCTAssertNil(decoded.elementTarget)
        XCTAssertFalse(decoded.replacingExisting)
    }

    func testTypeTextRejectsMissingTextOnDecode() throws {
        let json = #"{}"#

        XCTAssertThrowsError(try JSONDecoder().decode(TypeTextTarget.self, from: Data(json.utf8)))
    }

    func testTypeTextReplacingExistingAllowsEmptyText() throws {
        let target = TypeTextTarget(
            text: "",
            elementTarget: .predicate(ElementPredicate(identifier: "nameField")),
            replacingExisting: true
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TypeTextTarget.self, from: data)

        XCTAssertEqual(decoded.text, "")
        XCTAssertTrue(decoded.replacingExisting)
        if case .predicate(let matcher, _) = decoded.elementTarget {
            XCTAssertEqual(matcher.checks, [.identifier(.exact("nameField"))])
        } else {
            XCTFail("Expected .matcher elementTarget")
        }
    }

    func testTypeTextRejectsEmptyTextWithoutReplacingExistingOnDecode() throws {
        let json = #"{"text":""}"#

        XCTAssertThrowsError(try JSONDecoder().decode(TypeTextTarget.self, from: Data(json.utf8)))
    }

    func testTypeTextWithElementTarget() throws {
        let target = TypeTextTarget(
            text: "Hello",
            elementTarget: .predicate(ElementPredicate(identifier: "nameField"))
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TypeTextTarget.self, from: data)

        XCTAssertEqual(decoded.text, "Hello")
        if case .predicate(let matcher, _) = decoded.elementTarget {
            XCTAssertEqual(matcher.checks, [.identifier(.exact("nameField"))])
        } else {
            XCTFail("Expected .matcher elementTarget")
        }
    }

    // MARK: - SetPasteboard Tests

    func testSetPasteboardRoundTrip() throws {
        let target = SetPasteboardTarget(text: "clipboard content")
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(SetPasteboardTarget.self, from: data)

        XCTAssertEqual(decoded.text, "clipboard content")
    }

    func testSetPasteboardEnvelopeUsesHeistPlan() throws {
        let plan = try HeistPlan(body: [
            .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "hello")))),
        ])
        let envelope = RequestEnvelope(
            requestId: "pb-set",
            message: .heistPlan(HeistPlanRun(plan: plan))
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "pb-set")
        guard case .heistPlan(let run) = decoded.message,
              case .action(let step)? = run.plan.body.first,
              case .setPasteboard(let target) = step.command else {
            return XCTFail("Expected heistPlan setPasteboard, got \(decoded.message)")
        }
        XCTAssertEqual(target.text, "hello")
    }

    // MARK: - GetPasteboard Tests

    func testGetPasteboardRoundTrip() throws {
        let message = ClientMessage.getPasteboard
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .getPasteboard = decoded {
            // pass
        } else {
            XCTFail("Expected getPasteboard, got \(decoded)")
        }
    }

    func testGetPasteboardEnvelopeRoundTrip() throws {
        let envelope = RequestEnvelope(
            requestId: "pb-get",
            message: .getPasteboard
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "pb-get")
        if case .getPasteboard = decoded.message {
            // pass
        } else {
            XCTFail("Expected getPasteboard, got \(decoded.message)")
        }
    }

    func testGetAnnouncementsRoundTrip() throws {
        let message = ClientMessage.getAnnouncements
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .getAnnouncements = decoded {
            // pass
        } else {
            XCTFail("Expected getAnnouncements, got \(decoded)")
        }
    }

    func testGetAnnouncementsEnvelopeRoundTrip() throws {
        let envelope = RequestEnvelope(
            requestId: "ann-get",
            message: .getAnnouncements
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "ann-get")
        if case .getAnnouncements = decoded.message {
            // pass
        } else {
            XCTFail("Expected getAnnouncements, got \(decoded.message)")
        }
    }

    // MARK: - Wait Tests

    func testWaitAbsentRoundTrip() throws {
        let target = WaitTarget(
            predicate: .state(.missing(ElementPredicate(label: "Loading", traits: [.staticText]))),
            timeout: 5.0
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(WaitTarget.self, from: data)

        if case .state(.missing(let predicate)) = decoded.predicate {
            XCTAssertEqual(predicate.checks, [
                .label(.exact("Loading")),
                .traits([.staticText]),
            ])
            XCTAssertEqual(decoded.timeout, 5.0)
        } else {
            XCTFail("Expected wait(.missing), got \(decoded)")
        }
    }

    func testWaitPresentRoundTrip() throws {
        let target = WaitTarget(predicate: .state(.exists(ElementPredicate(identifier: "spinner"))))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(WaitTarget.self, from: data)

        if case .state(.exists(let predicate)) = decoded.predicate {
            XCTAssertEqual(predicate.checks, [.identifier(.exact("spinner"))])
            XCTAssertNil(decoded.timeout)
            XCTAssertEqual(decoded.resolvedTimeout, defaultWaitTimeout)
        } else {
            XCTFail("Expected wait(.exists), got \(decoded)")
        }
    }

    func testWaitTimeoutClamping() {
        let target = WaitTarget(predicate: .state(.exists(ElementPredicate(label: "x"))), timeout: 999)
        XCTAssertEqual(target.resolvedTimeout, 30.0)
    }

    func testWaitChangedScreenRoundTrip() throws {
        let target = WaitTarget(predicate: .change(.screen()), timeout: 15.0)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(WaitTarget.self, from: data)

        XCTAssertEqual(decoded.predicate, .change(.screen()))
        XCTAssertEqual(decoded.timeout, 15.0)
    }

    func testWaitAbsentConvenienceRoundTrip() throws {
        let target = WaitTarget(predicate: .missing(ElementPredicate(label: "Loading")), timeout: 5.0)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(WaitTarget.self, from: data)

        XCTAssertEqual(decoded.predicate, .missing(ElementPredicate(label: "Loading")))
        XCTAssertEqual(decoded.timeout, 5.0)
    }

    func testWaitEnvelopeUsesHeistPlan() throws {
        let plan = try HeistPlan(body: [
            .wait(WaitStep(predicate: .change(.elements()), timeout: 8.0)),
        ])
        let envelope = RequestEnvelope(
            requestId: "wait-1",
            message: .heistPlan(HeistPlanRun(plan: plan))
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "wait-1")
        guard case .heistPlan(let run) = decoded.message,
              case .wait(let target)? = run.plan.body.first else {
            return XCTFail("Expected heistPlan wait, got \(decoded.message)")
        }
        XCTAssertEqual(target.predicate, .change(.elements()))
        XCTAssertEqual(target.timeout, 8.0)
    }

    func testActionResultWithoutPayload() throws {
        let result = ActionResult.success(method: .activate)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertNil(decoded.payload)
    }

    // MARK: - ElementTarget Ordinal Tests

    func testElementTargetMatcherWithoutOrdinalRoundTrip() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Save"))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: data)

        guard case .predicate(let matcher, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertEqual(matcher.checks, [.label(.exact("Save"))])
        XCTAssertNil(ordinal)
    }

    func testElementTargetMatcherWithOrdinalRoundTrip() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Save", traits: [.button]), ordinal: 2)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: data)

        guard case .predicate(let matcher, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertEqual(matcher.checks, [
            .label(.exact("Save")),
            .traits([.button]),
        ])
        XCTAssertEqual(ordinal, 2)
    }

    func testElementTargetOrdinalWireFormat() throws {
        let json = #"{"checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}],"ordinal":2}"#
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))

        guard case .predicate(let matcher, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertEqual(matcher.checks, [.label(.exact("Save"))])
        XCTAssertEqual(ordinal, 2)
    }

    func testElementTargetOrdinalOmittedInWireFormat() throws {
        let json = #"{"checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}]}"#
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))

        guard case .predicate(_, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertNil(ordinal)
    }

    func testElementTargetNegativeOrdinalThrows() {
        let json = #"{"checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}],"ordinal":-1}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("non-negative"))
        }
    }

    func testElementTargetRejectsHeistIdWithMatcherFieldsAtCodableBoundary() {
        // heistId is no longer a targeting field — it is rejected as unknown.
        let json = #"{"heistId":"button_save","checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}]}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("heistId"))
        }
    }

    func testElementTargetRejectsHeistIdWithOrdinalAtCodableBoundary() {
        let json = #"{"heistId":"button_save","ordinal":1}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("heistId"))
        }
    }

    func testElementTargetRejectsUnknownFieldAtCodableBoundary() {
        let json = #"{"checks":[{"kind":"label","match":{"mode":"exact","value":"Save"}}],"unexpectedTargetField":"button_save"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("unexpectedTargetField"))
        }
    }

    func testElementTargetOrdinalEquality() {
        let withOrdinal = ElementTarget.predicate(ElementPredicate(label: "Save"), ordinal: 1)
        let withoutOrdinal = ElementTarget.predicate(ElementPredicate(label: "Save"))
        let differentOrdinal = ElementTarget.predicate(ElementPredicate(label: "Save"), ordinal: 2)

        XCTAssertNotEqual(withOrdinal, withoutOrdinal)
        XCTAssertNotEqual(withOrdinal, differentOrdinal)
        XCTAssertEqual(withOrdinal, ElementTarget.predicate(ElementPredicate(label: "Save"), ordinal: 1))
    }

    // MARK: - UnitPoint Tests

    func testUnitPointRoundTrip() throws {
        let swipe = SwipeTarget(
            selection: .unitElement(
                .predicate(ElementPredicate(identifier: "scrollable")),
                start: UnitPoint(x: 0.8, y: 0.5),
                end: UnitPoint(x: 0.2, y: 0.5)
            )
        )
        let data = try JSONEncoder().encode(swipe)
        let decoded = try JSONDecoder().decode(SwipeTarget.self, from: data)

        XCTAssertEqual(
            decoded.selection,
            .unitElement(
                .predicate(ElementPredicate(identifier: "scrollable")),
                start: UnitPoint(x: 0.8, y: 0.5),
                end: UnitPoint(x: 0.2, y: 0.5)
            )
        )
    }
}

// MARK: - Test Helpers

private struct EncodedClientMessageType: Decodable {
    let type: String
}

extension HeistElement {
    static func stub(
        label: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            description: label ?? "stub",
            label: label,
            value: nil,
            identifier: nil,
            traits: traits,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }
}
