import XCTest
import TheScore

/// Round-trip coverage for `ClientMessage` action variants and the assorted
/// gesture/edit/wait targets they wrap. Migrated from `ButtonHeistCLI/Tests/`
/// where it was checking TheScore wire types from the wrong target.
///
/// Where the underlying target struct already has a dedicated round-trip in
/// `WireTypeRoundTripTests`, the duplicate has been pruned — the message-level
/// tests below stay as proof that ClientMessage carries them through correctly.
final class ClientMessageActionRoundTripTests: XCTestCase {

    // MARK: - Touch Targets via ClientMessage

    func testClientMessageActivateEncoding() throws {
        let activateMessage = ClientMessage.activate(.matcher(ElementMatcher(identifier: "btn")))
        let data = try JSONEncoder().encode(activateMessage)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .activate(let target) = decoded {
            guard case .matcher(let matcher, _) = target else { return XCTFail("Expected .matcher") }
            XCTAssertEqual(matcher.identifier, "btn")
        } else {
            XCTFail("Expected activate message")
        }
    }

    func testClientMessageRotorPreviousEncoding() throws {
        let message = ClientMessage.rotor(RotorTarget(
            elementTarget: .heistId("form"),
            rotor: "Errors",
            direction: .previous,
            currentHeistId: "email",
            currentTextRange: TextRangeReference(startOffset: 10, endOffset: 15)
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .rotor(let target) = decoded {
            XCTAssertEqual(target.elementTarget, .heistId("form"))
            XCTAssertEqual(target.rotor, "Errors")
            XCTAssertNil(target.rotorIndex)
            XCTAssertEqual(target.direction, .previous)
            XCTAssertEqual(target.currentHeistId, "email")
            XCTAssertEqual(target.currentTextRange, TextRangeReference(startOffset: 10, endOffset: 15))
        } else {
            XCTFail("Expected rotor message")
        }
    }

    func testClientMessageRotorRejectsNegativeIndex() throws {
        let json = """
        {"type":"rotor","payload":{"heistId":"form","rotorIndex":-1}}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)))
    }

    func testClientMessageRotorRejectsInvalidCurrentTextRange() throws {
        let json = """
        {"type":"rotor","payload":{"heistId":"form","currentTextRange":{"startOffset":8,"endOffset":3}}}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)))
    }

    func testClientMessageTouchTapEncoding() throws {
        let message = ClientMessage.touchTap(TouchTapTarget(pointX: 100, pointY: 200))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchTap(let target) = decoded {
            XCTAssertEqual(target.pointX, 100)
            XCTAssertEqual(target.pointY, 200)
        } else {
            XCTFail("Expected touchTap message")
        }
    }

    func testClientMessageTouchLongPressEncoding() throws {
        let message = ClientMessage.touchLongPress(LongPressTarget(pointX: 50, pointY: 75, duration: 1.0))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchLongPress(let target) = decoded {
            XCTAssertEqual(target.pointX, 50)
            XCTAssertEqual(target.duration, 1.0)
        } else {
            XCTFail("Expected touchLongPress message")
        }
    }

    func testClientMessageTouchDragEncoding() throws {
        let message = ClientMessage.touchDrag(DragTarget(
            startX: 50, startY: 100, endX: 250, endY: 100, duration: 0.5
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchDrag(let target) = decoded {
            XCTAssertEqual(target.startX, 50)
            XCTAssertEqual(target.endX, 250)
            XCTAssertEqual(target.duration, 0.5)
        } else {
            XCTFail("Expected touchDrag message")
        }
    }

    func testClientMessageTouchPinchEncoding() throws {
        let message = ClientMessage.touchPinch(PinchTarget(centerX: 200, centerY: 300, scale: 2.0))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchPinch(let target) = decoded {
            XCTAssertEqual(target.centerX, 200)
            XCTAssertEqual(target.scale, 2.0)
        } else {
            XCTFail("Expected touchPinch message")
        }
    }

    func testClientMessageTouchRotateEncoding() throws {
        let message = ClientMessage.touchRotate(RotateTarget(centerX: 150, centerY: 250, angle: 1.57))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchRotate(let target) = decoded {
            XCTAssertEqual(target.centerX, 150)
            XCTAssertEqual(target.angle, 1.57)
        } else {
            XCTFail("Expected touchRotate message")
        }
    }

    func testClientMessageTouchTwoFingerTapEncoding() throws {
        let message = ClientMessage.touchTwoFingerTap(TwoFingerTapTarget(centerX: 100, centerY: 200, spread: 50))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchTwoFingerTap(let target) = decoded {
            XCTAssertEqual(target.centerX, 100)
            XCTAssertEqual(target.spread, 50)
        } else {
            XCTFail("Expected touchTwoFingerTap message")
        }
    }

    func testClientMessageTouchDrawPathEncoding() throws {
        let message = ClientMessage.touchDrawPath(DrawPathTarget(
            points: [PathPoint(x: 10, y: 20), PathPoint(x: 30, y: 40)],
            duration: 0.5
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchDrawPath(let target) = decoded {
            XCTAssertEqual(target.points.count, 2)
            XCTAssertEqual(target.points[0].x, 10)
            XCTAssertEqual(target.duration, 0.5)
        } else {
            XCTFail("Expected touchDrawPath message")
        }
    }

    func testClientMessageTouchDrawBezierEncoding() throws {
        let message = ClientMessage.touchDrawBezier(DrawBezierTarget(
            startX: 50, startY: 100,
            segments: [
                BezierSegment(cp1X: 50, cp1Y: 50, cp2X: 150, cp2Y: 50, endX: 150, endY: 100)
            ],
            duration: 0.8
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchDrawBezier(let target) = decoded {
            XCTAssertEqual(target.startX, 50)
            XCTAssertEqual(target.segments.count, 1)
            XCTAssertEqual(target.duration, 0.8)
        } else {
            XCTFail("Expected touchDrawBezier message")
        }
    }

    // MARK: - Edit / ResignFirstResponder / WaitForIdle

    func testClientMessageEditActionEncoding() throws {
        let message = ClientMessage.editAction(EditActionTarget(action: .paste))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .editAction(let target) = decoded {
            XCTAssertEqual(target.action, .paste)
        } else {
            XCTFail("Expected editAction message")
        }
    }

    func testClientMessageResignFirstResponderEncoding() throws {
        let message = ClientMessage.resignFirstResponder
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .resignFirstResponder = decoded {
            // Success
        } else {
            XCTFail("Expected resignFirstResponder message")
        }
    }

    func testWaitForIdleTargetDefaultTimeout() throws {
        let target = WaitForIdleTarget()
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(WaitForIdleTarget.self, from: data)

        XCTAssertNil(decoded.timeout)
    }

    func testClientMessageWaitForIdleEncoding() throws {
        let message = ClientMessage.waitForIdle(WaitForIdleTarget(timeout: 5.0))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .waitForIdle(let target) = decoded {
            XCTAssertEqual(target.timeout, 5.0)
        } else {
            XCTFail("Expected waitForIdle message")
        }
    }

    // MARK: - ActionResult / Method coverage

    func testActionResultMethodAllCases() throws {
        let methods: [ActionMethod] = [
            .activate,
            .increment,
            .decrement,
            .syntheticTap,
            .syntheticLongPress,
            .syntheticSwipe,
            .syntheticDrag,
            .syntheticPinch,
            .syntheticRotate,
            .syntheticTwoFingerTap,
            .syntheticDrawPath,
            .typeText,
            .customAction,
            .editAction,
            .resignFirstResponder,
            .rotor,
            .waitForIdle,
            .elementNotFound,
            .elementDeallocated,
        ]

        for method in methods {
            let result = ActionResult(success: true, method: method)
            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
            XCTAssertEqual(decoded.method, method)
        }
    }

    func testActionResultWithFailureMessage() throws {
        let result = ActionResult(
            success: false,
            method: .elementNotFound,
            message: "Element not found"
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.method, .elementNotFound)
        XCTAssertEqual(decoded.message, "Element not found")
    }

    func testActionResultWithValueField() throws {
        let result = ActionResult(success: true, method: .typeText, payload: .value("hello world"))
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.method, .typeText)
        guard case .value(let text) = decoded.payload else {
            return XCTFail("Expected .value payload, got \(String(describing: decoded.payload))")
        }
        XCTAssertEqual(text, "hello world")
    }

    func testServerMessageActionResultEncoding() throws {
        let result = ActionResult(success: true, method: .syntheticTap)
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertTrue(decodedResult.success)
            XCTAssertEqual(decodedResult.method, .syntheticTap)
        } else {
            XCTFail("Expected actionResult message")
        }
    }

    // MARK: - Activate with ordinal

    func testActivateMessageWithOrdinalEncoding() throws {
        let target = ElementTarget.matcher(ElementMatcher(label: "Add", traits: [.button]), ordinal: 1)
        let message = ClientMessage.activate(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .activate(let decodedTarget) = decoded {
            guard case .matcher(let matcher, let ordinal) = decodedTarget else { return XCTFail("Expected .matcher") }
            XCTAssertEqual(matcher.label, "Add")
            XCTAssertEqual(matcher.traits, [.button])
            XCTAssertEqual(ordinal, 1)
        } else {
            XCTFail("Expected activate message")
        }
    }
}
