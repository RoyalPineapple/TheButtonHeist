import XCTest
import CoreGraphics
import TheScore

/// Round-trip coverage for `ClientMessage` action variants and the assorted
/// gesture/edit/wait targets they wrap. Migrated from `ButtonHeistCLI/Tests/`
/// where it was checking TheScore wire types from the wrong target.
///
/// Where the underlying target struct already has a dedicated round-trip in
/// `WireTypeRoundTripTests`, the duplicate has been pruned — the message-level
/// tests below stay as proof that ClientMessage carries them through correctly.
final class ClientMessageActionRoundTripTests: XCTestCase {

    // MARK: - Gesture Targets via ClientMessage

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
            selection: .named("Errors"),
            direction: .previous,
            continuation: .textRange("email", TextRangeReference(startOffset: 10, endOffset: 15))
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .rotor(let target) = decoded {
            XCTAssertEqual(target.elementTarget, ElementTarget.heistId("form"))
            XCTAssertEqual(target.selection, .named("Errors"))
            XCTAssertEqual(target.direction, RotorDirection.previous)
            XCTAssertEqual(target.currentHeistId, "email")
            XCTAssertEqual(target.currentTextRange, TextRangeReference(startOffset: 10, endOffset: 15))
        } else {
            XCTFail("Expected rotor message")
        }
    }

    func testClientMessageRotorRejectsMixedSelectorShape() throws {
        let json = """
        {"type":"rotor","payload":{"heistId":"form","rotor":"Errors","rotorIndex":1}}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)))
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

    func testClientMessageRotorRejectsTextRangeWithoutCurrentItem() throws {
        let json = """
        {"type":"rotor","payload":{"heistId":"form","currentTextRange":{"startOffset":3,"endOffset":8}}}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)))
    }

    func testClientMessageOneFingerTapEncoding() throws {
        let message = ClientMessage.oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 100, y: 200))))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .oneFingerTap(let target) = decoded {
            XCTAssertEqual(target.selection, GesturePointSelection.coordinate(ScreenPoint(x: 100, y: 200)))
            XCTAssertEqual(target.point, CGPoint(x: 100, y: 200))
        } else {
            XCTFail("Expected oneFingerTap message")
        }
    }

    func testClientMessageLongPressEncoding() throws {
        let message = ClientMessage.longPress(LongPressTarget(
            selection: .coordinate(ScreenPoint(x: 50, y: 75)),
            duration: 1.0
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .longPress(let target) = decoded {
            XCTAssertEqual(target.selection, GesturePointSelection.coordinate(ScreenPoint(x: 50, y: 75)))
            XCTAssertEqual(target.point, CGPoint(x: 50, y: 75))
            XCTAssertEqual(target.duration, 1.0)
        } else {
            XCTFail("Expected longPress message")
        }
    }

    func testClientMessageDragEncoding() throws {
        let message = ClientMessage.drag(DragTarget(
            start: .coordinate(ScreenPoint(x: 50, y: 100)),
            end: ScreenPoint(x: 250, y: 100),
            duration: 0.5
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .drag(let target) = decoded {
            XCTAssertEqual(target.start, .coordinate(ScreenPoint(x: 50, y: 100)))
            XCTAssertEqual(target.end, ScreenPoint(x: 250, y: 100))
            XCTAssertEqual(target.duration, 0.5)
        } else {
            XCTFail("Expected drag message")
        }
    }

    func testClientMessagePinchEncoding() throws {
        let message = ClientMessage.pinch(PinchTarget(
            center: .coordinate(ScreenPoint(x: 200, y: 300)),
            scale: 2.0
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .pinch(let target) = decoded {
            XCTAssertEqual(target.center, GesturePointSelection.coordinate(ScreenPoint(x: 200, y: 300)))
            XCTAssertEqual(target.scale, 2.0)
        } else {
            XCTFail("Expected pinch message")
        }
    }

    func testClientMessageRotateEncoding() throws {
        let message = ClientMessage.rotate(RotateTarget(
            center: .coordinate(ScreenPoint(x: 150, y: 250)),
            angle: 1.57
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .rotate(let target) = decoded {
            XCTAssertEqual(target.center, GesturePointSelection.coordinate(ScreenPoint(x: 150, y: 250)))
            XCTAssertEqual(target.angle, 1.57)
        } else {
            XCTFail("Expected rotate message")
        }
    }

    func testClientMessageTwoFingerTapEncoding() throws {
        let message = ClientMessage.twoFingerTap(TwoFingerTapTarget(
            center: .coordinate(ScreenPoint(x: 100, y: 200)),
            spread: 50
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .twoFingerTap(let target) = decoded {
            XCTAssertEqual(target.center, GesturePointSelection.coordinate(ScreenPoint(x: 100, y: 200)))
            XCTAssertEqual(target.spread, 50)
        } else {
            XCTFail("Expected twoFingerTap message")
        }
    }

    func testClientMessageDrawPathEncoding() throws {
        let message = ClientMessage.drawPath(DrawPathTarget(
            points: [PathPoint(x: 10, y: 20), PathPoint(x: 30, y: 40)],
            duration: 0.5
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .drawPath(let target) = decoded {
            XCTAssertEqual(target.points.count, 2)
            XCTAssertEqual(target.points[0].x, 10)
            XCTAssertEqual(target.duration, 0.5)
        } else {
            XCTFail("Expected drawPath message")
        }
    }

    func testClientMessageDrawBezierEncoding() throws {
        let message = ClientMessage.drawBezier(DrawBezierTarget(
            startX: 50, startY: 100,
            segments: [
                BezierSegment(cp1X: 50, cp1Y: 50, cp2X: 150, cp2Y: 50, endX: 150, endY: 100)
            ],
            duration: 0.8
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .drawBezier(let target) = decoded {
            XCTAssertEqual(target.startPoint, CGPoint(x: 50, y: 100))
            XCTAssertEqual(target.segments.count, 1)
            XCTAssertEqual(target.segments[0].end, CGPoint(x: 150, y: 100))
            XCTAssertEqual(target.duration, 0.8)
        } else {
            XCTFail("Expected drawBezier message")
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
