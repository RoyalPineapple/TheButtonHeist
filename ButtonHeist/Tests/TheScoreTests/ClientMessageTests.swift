import XCTest
import TheScore

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
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "requestInterface")
        XCTAssertNotNil(object["payload"] as? [String: Any])

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
            .performCustomAction(CustomActionTarget(
                elementTarget: .predicate(ElementPredicate(identifier: "menu")),
                actionName: "Open"
            )),
            .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 12, y: 34)))),
            .scrollToVisible(ScrollToVisibleTarget(elementTarget: .predicate(ElementPredicate(label: "Save")))),
            .wait(WaitTarget(predicate: .changed(.elements), timeout: 1.0)),
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
                    command: .activate(saveTarget),
                    expectation: WaitStep(predicate: .changed(.screen()), timeout: 10)
                )),
                .wait(WaitStep(
                    predicate: .state(.present(ElementPredicate(label: "Save", traits: [.button]))),
                    timeout: 2.5
                )),
                .wait(WaitStep(
                    predicate: .changed(.appeared(ElementPredicate(label: "Done"))),
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
        XCTAssertEqual(decodedRun.argument, .none)
        XCTAssertEqual(decodedPlan.body.count, 3)
        guard case .action(let decodedAction) = decodedPlan.body[0],
              case .activate(let decodedTarget) = decodedAction.command,
              decodedAction.expectation?.predicate == .predicate(.changed(.screen())) else {
            return XCTFail("Expected activate command with screen change predicate")
        }
        XCTAssertEqual(decodedTarget, .target(saveTarget))
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
                command: .typeText(TypeTextTarget(
                    text: "hello",
                    elementTarget: .predicate(ElementPredicate(identifier: "nameField"))
                ))
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
              case .typeText(let text, let target) = action.command,
              action.expectation == nil else {
            return XCTFail("Expected heistPlan envelope, got \(decoded.message)")
        }
        XCTAssertEqual(text, .literal("hello"))
        XCTAssertEqual(target, .target(.predicate(ElementPredicate(identifier: "nameField"))))
    }

    func testHeistActionDescriptionUsesNormalCommandIdentity() throws {
        let step = try ActionStep(
            command: .activate(.predicate(ElementPredicate(label: "Save"))),
            expectation: WaitStep(predicate: .changed(.screen()), timeout: 10)
        )

        XCTAssertEqual(
            step.description,
            #"action(command=activate expect=wait(changed(screen_changed) timeout=10))"#
        )
    }

    func testActivatePredicateWireShape() throws {
        let message = ClientMessage.activate(.predicate(ElementPredicate(label: "Log In")))
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "activate")
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(payload["label"] as? String, "Log In")
        XCTAssertNil(payload["heistId"])
    }

    func testRequestScreenshotEncodeDecode() throws {
        let message = ClientMessage.requestScreen
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .requestScreen = decoded {
        } else {
            XCTFail("Expected requestScreen, got \(decoded)")
        }
    }

    // MARK: - TypeText Tests

    func testTypeTextWithTextOnly() throws {
        let message = ClientMessage.typeText(TypeTextTarget(text: "Hello"))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .typeText(let target) = decoded {
            XCTAssertEqual(target.text, "Hello")
            XCTAssertNil(target.elementTarget)
        } else {
            XCTFail("Expected typeText, got \(decoded)")
        }
    }

    func testTypeTextRejectsMissingTextOnDecode() throws {
        let json = #"{"type":"typeText","payload":{}}"#

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)))
    }

    func testTypeTextWithElementTarget() throws {
        let target = TypeTextTarget(
            text: "Hello",
            elementTarget: .predicate(ElementPredicate(identifier: "nameField"))
        )
        let message = ClientMessage.typeText(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        guard case .typeText(let decodedTarget) = decoded else {
            return XCTFail("Expected typeText, got \(decoded)")
        }
        XCTAssertEqual(decodedTarget.text, "Hello")
        if case .predicate(let matcher, _) = decodedTarget.elementTarget {
            XCTAssertEqual(matcher.identifier, "nameField")
        } else {
            XCTFail("Expected .matcher elementTarget")
        }
    }

    // MARK: - SetPasteboard Tests

    func testSetPasteboardRoundTrip() throws {
        let message = ClientMessage.setPasteboard(SetPasteboardTarget(text: "clipboard content"))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .setPasteboard(let target) = decoded {
            XCTAssertEqual(target.text, "clipboard content")
        } else {
            XCTFail("Expected setPasteboard, got \(decoded)")
        }
    }

    func testSetPasteboardEnvelopeRoundTrip() throws {
        let envelope = RequestEnvelope(
            requestId: "pb-set",
            message: .setPasteboard(SetPasteboardTarget(text: "hello"))
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "pb-set")
        if case .setPasteboard(let target) = decoded.message {
            XCTAssertEqual(target.text, "hello")
        } else {
            XCTFail("Expected setPasteboard, got \(decoded.message)")
        }
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

    // MARK: - Wait Tests

    func testWaitAbsentRoundTrip() throws {
        let target = WaitTarget(predicate: .state(.absent(ElementPredicate(label: "Loading", traits: [.staticText]))), timeout: 5.0)
        let message = ClientMessage.wait(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .wait(let wait) = decoded, case .state(.absent(let predicate)) = wait.predicate {
            XCTAssertEqual(predicate.label, "Loading")
            XCTAssertEqual(predicate.traits, [.staticText])
            XCTAssertEqual(wait.timeout, 5.0)
        } else {
            XCTFail("Expected wait(.absent), got \(decoded)")
        }
    }

    func testWaitPresentRoundTrip() throws {
        let message = ClientMessage.wait(WaitTarget(predicate: .state(.present(ElementPredicate(identifier: "spinner")))))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .wait(let wait) = decoded, case .state(.present(let predicate)) = wait.predicate {
            XCTAssertEqual(predicate.identifier, "spinner")
            XCTAssertNil(wait.timeout)
            XCTAssertEqual(wait.resolvedTimeout, 10.0)
        } else {
            XCTFail("Expected wait(.present), got \(decoded)")
        }
    }

    func testWaitTimeoutClamping() {
        let target = WaitTarget(predicate: .state(.present(ElementPredicate(label: "x"))), timeout: 999)
        XCTAssertEqual(target.resolvedTimeout, 30.0)
    }

    func testWaitChangedScreenRoundTrip() throws {
        let message = ClientMessage.wait(WaitTarget(predicate: .changed(.screen()), timeout: 15.0))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        guard case .wait(let target) = decoded else {
            return XCTFail("Expected wait, got \(decoded)")
        }
        XCTAssertEqual(target.predicate, .changed(.screen()))
        XCTAssertEqual(target.timeout, 15.0)
    }

    func testWaitChangedDisappearedRoundTrip() throws {
        let message = ClientMessage.wait(
            WaitTarget(predicate: .changed(.disappeared(ElementPredicate(label: "Loading"))), timeout: 5.0)
        )
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        guard case .wait(let target) = decoded else {
            return XCTFail("Expected wait, got \(decoded)")
        }
        XCTAssertEqual(target.predicate, .changed(.disappeared(ElementPredicate(label: "Loading"))))
        XCTAssertEqual(target.timeout, 5.0)
    }

    func testWaitEnvelopeRoundTrip() throws {
        let envelope = RequestEnvelope(
            requestId: "wait-1",
            message: .wait(WaitTarget(predicate: .changed(.elements), timeout: 8.0))
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "wait-1")
        guard case .wait(let target) = decoded.message else {
            return XCTFail("Expected wait, got \(decoded.message)")
        }
        XCTAssertEqual(target.predicate, .changed(.elements))
        XCTAssertEqual(target.timeout, 8.0)
    }

    func testActionResultWithoutPayload() throws {
        let result = ActionResult(success: true, method: .activate)
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
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertNil(ordinal)
    }

    func testElementTargetMatcherWithOrdinalRoundTrip() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Save", traits: [.button]), ordinal: 2)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: data)

        guard case .predicate(let matcher, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(matcher.traits, [.button])
        XCTAssertEqual(ordinal, 2)
    }

    func testElementTargetOrdinalFlatWireFormat() throws {
        let json = #"{"label":"Save","ordinal":2}"#
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))

        guard case .predicate(let matcher, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(ordinal, 2)
    }

    func testElementTargetOrdinalOmittedInWireFormat() throws {
        let json = #"{"label":"Save"}"#
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))

        guard case .predicate(_, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertNil(ordinal)
    }

    func testElementTargetNegativeOrdinalThrows() {
        let json = #"{"label":"Save","ordinal":-1}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected dataCorrupted, got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("non-negative"))
        }
    }

    func testElementTargetRejectsHeistIdWithMatcherFieldsAtCodableBoundary() {
        // heistId is no longer a targeting field — it is rejected as unknown.
        let json = #"{"heistId":"button_save","label":"Save"}"#
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
        let json = #"{"label":"Save","unexpectedTargetField":"button_save"}"#
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
        let message = ClientMessage.swipe(swipe)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .swipe(let target) = decoded {
            XCTAssertEqual(
                target.selection,
                .unitElement(
                    .predicate(ElementPredicate(identifier: "scrollable")),
                    start: UnitPoint(x: 0.8, y: 0.5),
                    end: UnitPoint(x: 0.2, y: 0.5)
                )
            )
        } else {
            XCTFail("Expected swipe, got \(decoded)")
        }
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
