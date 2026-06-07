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
        let activateMessage = ClientMessage.activate(.predicate(ElementPredicate(identifier: "btn")))
        let data = try JSONEncoder().encode(activateMessage)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .activate(let target) = decoded {
            guard case .predicate(let matcher, _) = target else { return XCTFail("Expected .matcher") }
            XCTAssertEqual(matcher.identifier, "btn")
        } else {
            XCTFail("Expected activate message")
        }
    }

    func testClientMessageRotorPreviousEncoding() throws {
        let message = ClientMessage.rotor(RotorTarget(
            elementTarget: .predicate(ElementPredicate(label: "Form")),
            selection: .named("Errors"),
            direction: .previous
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .rotor(let target) = decoded {
            XCTAssertEqual(target.elementTarget, ElementTarget.predicate(ElementPredicate(label: "Form")))
            XCTAssertEqual(target.selection, .named("Errors"))
            XCTAssertEqual(target.direction, RotorDirection.previous)
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
        {"type":"rotor","payload":{"heistId":"form","continuation":{"heistId":"field","textRange":{"startOffset":8,"endOffset":3}}}}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)))
    }

    func testClientMessageRotorRejectsTextRangeWithoutCurrentItem() throws {
        let json = """
        {"type":"rotor","payload":{"heistId":"form","continuation":{"textRange":{"startOffset":3,"endOffset":8}}}}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)))
    }

    func testClientMessageRotorRejectsLegacyLooseContinuationFields() throws {
        let json = """
        {"type":"rotor","payload":{"heistId":"form","currentHeistId":"field"}}
        """

        XCTAssertThrowsError(try JSONDecoder().decode(ClientMessage.self, from: Data(json.utf8)))
    }

    func testClientMessageOneFingerTapEncoding() throws {
        let message = ClientMessage.oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 100, y: 200))))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .oneFingerTap(let target) = decoded {
            XCTAssertEqual(target.selection, GesturePointSelection.coordinate(ScreenPoint(x: 100, y: 200)))
        } else {
            XCTFail("Expected oneFingerTap message")
        }
    }

    func testClientMessageLongPressEncoding() throws {
        let message = ClientMessage.longPress(LongPressTarget(
            selection: .coordinate(ScreenPoint(x: 50, y: 75)),
            duration: GestureDuration(seconds: 1.0)
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .longPress(let target) = decoded {
            XCTAssertEqual(target.selection, GesturePointSelection.coordinate(ScreenPoint(x: 50, y: 75)))
            XCTAssertEqual(target.duration.seconds, 1.0)
        } else {
            XCTFail("Expected longPress message")
        }
    }

    func testClientMessageDragEncoding() throws {
        let message = ClientMessage.drag(DragTarget(
            start: .coordinate(ScreenPoint(x: 50, y: 100)),
            end: ScreenPoint(x: 250, y: 100),
            duration: GestureDuration(seconds: 0.5)
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .drag(let target) = decoded {
            XCTAssertEqual(target.start, .coordinate(ScreenPoint(x: 50, y: 100)))
            XCTAssertEqual(target.end, ScreenPoint(x: 250, y: 100))
            XCTAssertEqual(target.duration?.seconds, 0.5)
        } else {
            XCTFail("Expected drag message")
        }
    }

    // MARK: - Edit / ResignFirstResponder

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

    func testActionResultWithFailureMessage() throws {
        let result = ActionResult(
            success: false,
            method: .activate,
            message: "Element not found",
            errorKind: .elementNotFound
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.method, .activate)
        XCTAssertEqual(decoded.message, "Element not found")
        XCTAssertEqual(decoded.errorKind, .elementNotFound)
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
        let target = ElementTarget.predicate(ElementPredicate(label: "Add", traits: [.button]), ordinal: 1)
        let message = ClientMessage.activate(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .activate(let decodedTarget) = decoded {
            guard case .predicate(let matcher, let ordinal) = decodedTarget else { return XCTFail("Expected .matcher") }
            XCTAssertEqual(matcher.label, "Add")
            XCTAssertEqual(matcher.traits, [.button])
            XCTAssertEqual(ordinal, 1)
        } else {
            XCTFail("Expected activate message")
        }
    }
}
