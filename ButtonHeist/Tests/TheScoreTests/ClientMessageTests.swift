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
        if case .matcher(let matcher) = decodedTarget.elementTarget {
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

    func testWaitForRoundTrip() throws {
        let matcher = ElementMatcher(label: "Loading", traits: ["staticText"])
        let message = ClientMessage.waitFor(WaitForTarget(match: matcher, absent: true, timeout: 5.0))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .waitFor(let target) = decoded {
            XCTAssertEqual(target.match.label, "Loading")
            XCTAssertEqual(target.match.traits, ["staticText"])
            XCTAssertEqual(target.absent, true)
            XCTAssertEqual(target.timeout, 5.0)
        } else {
            XCTFail("Expected waitFor, got \(decoded)")
        }
    }

    func testWaitForDefaultsRoundTrip() throws {
        let message = ClientMessage.waitFor(WaitForTarget(match: ElementMatcher(identifier: "spinner")))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .waitFor(let target) = decoded {
            XCTAssertEqual(target.match.identifier, "spinner")
            XCTAssertNil(target.absent)
            XCTAssertNil(target.timeout)
            XCTAssertEqual(target.resolvedAbsent, false)
            XCTAssertEqual(target.resolvedTimeout, 10.0)
        } else {
            XCTFail("Expected waitFor, got \(decoded)")
        }
    }

    func testWaitForTimeoutClamping() throws {
        let target = WaitForTarget(match: ElementMatcher(label: "x"), timeout: 999)
        XCTAssertEqual(target.resolvedTimeout, 30.0)
    }

    func testWaitForEnvelopeRoundTrip() throws {
        let envelope = RequestEnvelope(
            requestId: "wf-1",
            message: .waitFor(WaitForTarget(match: ElementMatcher(label: "Done"), absent: false, timeout: 15.0))
        )
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(RequestEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "wf-1")
        if case .waitFor(let target) = decoded.message {
            XCTAssertEqual(target.match.label, "Done")
            XCTAssertEqual(target.absent, false)
            XCTAssertEqual(target.timeout, 15.0)
        } else {
            XCTFail("Expected waitFor, got \(decoded.message)")
        }
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
