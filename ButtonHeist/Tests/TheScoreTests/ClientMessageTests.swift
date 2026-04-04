import XCTest
 import TheScore

final class ClientMessageTests: XCTestCase {

    func testRequestSnapshotEncodeDecode() throws {
        let message = ClientMessage.requestInterface
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .requestInterface = decoded {
            // Success
        } else {
            XCTFail("Expected requestInterface, got \(decoded)")
        }
    }

    func testSubscribeEncodeDecode() throws {
        let message = ClientMessage.subscribe
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .subscribe = decoded {
            // Success
        } else {
            XCTFail("Expected subscribe, got \(decoded)")
        }
    }

    func testUnsubscribeEncodeDecode() throws {
        let message = ClientMessage.unsubscribe
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .unsubscribe = decoded {
            // Success
        } else {
            XCTFail("Expected unsubscribe, got \(decoded)")
        }
    }

    func testPingEncodeDecode() throws {
        let message = ClientMessage.ping
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .ping = decoded {
            // Success
        } else {
            XCTFail("Expected ping, got \(decoded)")
        }
    }

    func testStatusEncodeDecode() throws {
        let message = ClientMessage.status
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .status = decoded {
            // Success
        } else {
            XCTFail("Expected status, got \(decoded)")
        }
    }

    func testRequestScreenshotEncodeDecode() throws {
        let message = ClientMessage.requestScreen
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .requestScreen = decoded {
            // Success
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
            XCTAssertNil(target.deleteCount)
            XCTAssertNil(target.elementTarget)
        } else {
            XCTFail("Expected typeText, got \(decoded)")
        }
    }

    func testTypeTextWithDeleteOnly() throws {
        let message = ClientMessage.typeText(TypeTextTarget(deleteCount: 5))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .typeText(let target) = decoded {
            XCTAssertNil(target.text)
            XCTAssertEqual(target.deleteCount, 5)
            XCTAssertNil(target.elementTarget)
        } else {
            XCTFail("Expected typeText, got \(decoded)")
        }
    }

    func testTypeTextWithTextAndDelete() throws {
        let message = ClientMessage.typeText(TypeTextTarget(text: "World", deleteCount: 3))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .typeText(let target) = decoded {
            XCTAssertEqual(target.text, "World")
            XCTAssertEqual(target.deleteCount, 3)
        } else {
            XCTFail("Expected typeText, got \(decoded)")
        }
    }

    func testTypeTextWithElementTarget() throws {
        let target = TypeTextTarget(
            text: "Hello",
            elementTarget: .matcher(ElementMatcher(identifier: "nameField"))
        )
        let message = ClientMessage.typeText(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        guard case .typeText(let decodedTarget) = decoded else {
            return XCTFail("Expected typeText, got \(decoded)")
        }
        XCTAssertEqual(decodedTarget.text, "Hello")
        if case .matcher(let matcher, _) = decodedTarget.elementTarget {
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

    // MARK: - WaitFor Tests

    func testWaitForMatcherRoundTrip() throws {
        let target = ElementTarget.matcher(ElementMatcher(label: "Loading", traits: [.staticText]))
        let message = ClientMessage.waitFor(WaitForTarget(elementTarget: target, absent: true, timeout: 5.0))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .waitFor(let wf) = decoded, case .matcher(let m, _) = wf.elementTarget {
            XCTAssertEqual(m.label, "Loading")
            XCTAssertEqual(m.traits, [.staticText])
            XCTAssertEqual(wf.absent, true)
            XCTAssertEqual(wf.timeout, 5.0)
        } else {
            XCTFail("Expected waitFor with matcher, got \(decoded)")
        }
    }

    func testWaitForHeistIdRoundTrip() throws {
        let message = ClientMessage.waitFor(WaitForTarget(elementTarget: .heistId("button_login"), timeout: 3.0))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .waitFor(let wf) = decoded, case .heistId(let id) = wf.elementTarget {
            XCTAssertEqual(id, "button_login")
            XCTAssertEqual(wf.timeout, 3.0)
        } else {
            XCTFail("Expected waitFor with heistId, got \(decoded)")
        }
    }

    func testWaitForDefaultsRoundTrip() throws {
        let message = ClientMessage.waitFor(WaitForTarget(elementTarget: .matcher(ElementMatcher(identifier: "spinner"))))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .waitFor(let wf) = decoded {
            XCTAssertNil(wf.absent)
            XCTAssertNil(wf.timeout)
            XCTAssertEqual(wf.resolvedAbsent, false)
            XCTAssertEqual(wf.resolvedTimeout, 10.0)
        } else {
            XCTFail("Expected waitFor, got \(decoded)")
        }
    }

    func testWaitForTimeoutClamping() {
        let target = WaitForTarget(elementTarget: .matcher(ElementMatcher(label: "x")), timeout: 999)
        XCTAssertEqual(target.resolvedTimeout, 30.0)
    }

    func testWaitForEnvelopeRoundTrip() throws {
        let envelope = RequestEnvelope(
            requestId: "wf-1",
            message: .waitFor(WaitForTarget(elementTarget: .matcher(ElementMatcher(label: "Done")), absent: false, timeout: 15.0))
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "wf-1")
        if case .waitFor(let wf) = decoded.message, case .matcher(let m, _) = wf.elementTarget {
            XCTAssertEqual(m.label, "Done")
            XCTAssertEqual(wf.absent, false)
            XCTAssertEqual(wf.timeout, 15.0)
        } else {
            XCTFail("Expected waitFor, got \(decoded.message)")
        }
    }

    // MARK: - Explore

    func testExploreEncodeDecode() throws {
        let message = ClientMessage.explore
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .explore = decoded {
            // Success
        } else {
            XCTFail("Expected explore, got \(decoded)")
        }
    }

    func testExploreEnvelopeRoundTrip() throws {
        let envelope = RequestEnvelope(
            requestId: "explore-1",
            message: .explore
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "explore-1")
        if case .explore = decoded.message {
            // Success
        } else {
            XCTFail("Expected explore, got \(decoded.message)")
        }
    }

    func testExploreResultEncodeDecode() throws {
        let elements = (0..<3).map { i in
            HeistElement.stub(heistId: "el_\(i)", label: "Element \(i)")
        }
        let result = ExploreResult(
            elements: elements, scrollCount: 6,
            containersExplored: 3, explorationTime: 1.25
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ExploreResult.self, from: data)
        XCTAssertEqual(decoded.elementCount, 3)
        XCTAssertEqual(decoded.elements.count, 3)
        XCTAssertEqual(decoded.elements[0].heistId, "el_0")
        XCTAssertEqual(decoded.scrollCount, 6)
        XCTAssertEqual(decoded.containersExplored, 3)
        XCTAssertEqual(decoded.explorationTime, 1.25)
    }

    func testActionResultWithExploreResult() throws {
        let elements = (0..<100).map { i in
            HeistElement.stub(heistId: "el_\(i)", label: "Element \(i)")
        }
        let exploreResult = ExploreResult(
            elements: elements, scrollCount: 12,
            containersExplored: 2, explorationTime: 3.5
        )
        let result = ActionResult(
            success: true, method: .explore,
            message: "100 elements, 12 scrolls, 3.50s",
            exploreResult: exploreResult
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.method, .explore)
        XCTAssertEqual(decoded.exploreResult?.elementCount, 100)
        XCTAssertEqual(decoded.exploreResult?.scrollCount, 12)
        XCTAssertEqual(decoded.exploreResult?.containersExplored, 2)
        XCTAssertEqual(decoded.exploreResult?.explorationTime, 3.5)
    }

    func testActionResultWithoutExploreResult() throws {
        let result = ActionResult(success: true, method: .activate)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertNil(decoded.exploreResult)
    }

    // MARK: - ElementTarget Ordinal Tests

    func testElementTargetMatcherWithoutOrdinalRoundTrip() throws {
        let target = ElementTarget.matcher(ElementMatcher(label: "Save"))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: data)

        guard case .matcher(let matcher, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertNil(ordinal)
    }

    func testElementTargetMatcherWithOrdinalRoundTrip() throws {
        let target = ElementTarget.matcher(ElementMatcher(label: "Save", traits: [.button]), ordinal: 2)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: data)

        guard case .matcher(let matcher, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(matcher.traits, [.button])
        XCTAssertEqual(ordinal, 2)
    }

    func testElementTargetOrdinalFlatWireFormat() throws {
        let json = #"{"label":"Save","ordinal":2}"#
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))

        guard case .matcher(let matcher, let ordinal) = decoded else {
            return XCTFail("Expected .matcher, got \(decoded)")
        }
        XCTAssertEqual(matcher.label, "Save")
        XCTAssertEqual(ordinal, 2)
    }

    func testElementTargetOrdinalOmittedInWireFormat() throws {
        let json = #"{"label":"Save"}"#
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))

        guard case .matcher(_, let ordinal) = decoded else {
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

    func testElementTargetHeistIdIgnoresOrdinal() throws {
        let json = #"{"heistId":"button_save","ordinal":2}"#
        let decoded = try JSONDecoder().decode(ElementTarget.self, from: Data(json.utf8))

        guard case .heistId(let id) = decoded else {
            return XCTFail("Expected .heistId, got \(decoded)")
        }
        XCTAssertEqual(id, "button_save")
    }

    func testElementTargetOrdinalEquality() {
        let withOrdinal = ElementTarget.matcher(ElementMatcher(label: "Save"), ordinal: 1)
        let withoutOrdinal = ElementTarget.matcher(ElementMatcher(label: "Save"))
        let differentOrdinal = ElementTarget.matcher(ElementMatcher(label: "Save"), ordinal: 2)

        XCTAssertNotEqual(withOrdinal, withoutOrdinal)
        XCTAssertNotEqual(withOrdinal, differentOrdinal)
        XCTAssertEqual(withOrdinal, ElementTarget.matcher(ElementMatcher(label: "Save"), ordinal: 1))
    }

    // MARK: - UnitPoint Tests

    func testUnitPointRoundTrip() throws {
        let swipe = SwipeTarget(
            direction: .up,
            start: UnitPoint(x: 0.8, y: 0.5),
            end: UnitPoint(x: 0.2, y: 0.5)
        )
        let message = ClientMessage.touchSwipe(swipe)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchSwipe(let target) = decoded {
            XCTAssertEqual(target.start, UnitPoint(x: 0.8, y: 0.5))
            XCTAssertEqual(target.end, UnitPoint(x: 0.2, y: 0.5))
        } else {
            XCTFail("Expected touchSwipe, got \(decoded)")
        }
    }
}

// MARK: - Test Helpers

extension HeistElement {
    static func stub(
        heistId: String = "test",
        label: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label ?? heistId,
            label: label,
            value: nil,
            identifier: nil,
            traits: traits,
            frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
            actions: []
        )
    }
}
