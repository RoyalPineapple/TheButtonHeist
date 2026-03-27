import XCTest
import Foundation
import ButtonHeist

final class ActionCommandTests: XCTestCase {

    // MARK: - Message Encoding Tests

    func testActionTargetEncoding() throws {
        let target = ActionTarget(match: ElementMatcher(identifier: "testButton"))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ActionTarget.self, from: data)

        XCTAssertEqual(decoded.match?.identifier, "testButton")
    }

    func testTouchTapTargetWithElementEncoding() throws {
        let target = TouchTapTarget(elementTarget: ActionTarget(match: ElementMatcher(identifier: "button")))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TouchTapTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.match?.identifier, "button")
        XCTAssertNil(decoded.pointX)
        XCTAssertNil(decoded.pointY)
    }

    func testTouchTapTargetWithCoordinatesEncoding() throws {
        let target = TouchTapTarget(pointX: 100.5, pointY: 200.5)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TouchTapTarget.self, from: data)

        XCTAssertNil(decoded.elementTarget)
        XCTAssertEqual(decoded.pointX, 100.5)
        XCTAssertEqual(decoded.pointY, 200.5)
        XCTAssertEqual(decoded.point, CGPoint(x: 100.5, y: 200.5))
    }

    func testLongPressTargetEncoding() throws {
        let target = LongPressTarget(elementTarget: ActionTarget(match: ElementMatcher(identifier: "btn")), duration: 1.5)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(LongPressTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.match?.identifier, "btn")
        XCTAssertEqual(decoded.duration, 1.5)
        XCTAssertNil(decoded.pointX)
    }

    func testLongPressTargetWithCoordinatesEncoding() throws {
        let target = LongPressTarget(pointX: 50, pointY: 75, duration: 0.5)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(LongPressTarget.self, from: data)

        XCTAssertNil(decoded.elementTarget)
        XCTAssertEqual(decoded.pointX, 50)
        XCTAssertEqual(decoded.pointY, 75)
        XCTAssertEqual(decoded.duration, 0.5)
        XCTAssertEqual(decoded.point, CGPoint(x: 50, y: 75))
    }

    func testSwipeTargetWithDirectionEncoding() throws {
        let target = SwipeTarget(
            elementTarget: ActionTarget(match: ElementMatcher(identifier: "list")),
            direction: .up
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(SwipeTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.match?.identifier, "list")
        XCTAssertEqual(decoded.direction, .up)
        XCTAssertNil(decoded.endX)
    }

    func testSwipeTargetWithCoordinatesEncoding() throws {
        let target = SwipeTarget(startX: 100, startY: 400, endX: 100, endY: 100, duration: 0.2)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(SwipeTarget.self, from: data)

        XCTAssertNil(decoded.elementTarget)
        XCTAssertEqual(decoded.startX, 100)
        XCTAssertEqual(decoded.startY, 400)
        XCTAssertEqual(decoded.endX, 100)
        XCTAssertEqual(decoded.endY, 100)
        XCTAssertEqual(decoded.duration, 0.2)
        XCTAssertEqual(decoded.startPoint, CGPoint(x: 100, y: 400))
    }

    func testDragTargetEncoding() throws {
        let target = DragTarget(
            elementTarget: ActionTarget(match: ElementMatcher(identifier: "slider")),
            endX: 300, endY: 200, duration: 0.8
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(DragTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.match?.identifier, "slider")
        XCTAssertEqual(decoded.endX, 300)
        XCTAssertEqual(decoded.endY, 200)
        XCTAssertEqual(decoded.duration, 0.8)
        XCTAssertEqual(decoded.endPoint, CGPoint(x: 300, y: 200))
    }

    func testDragTargetWithStartCoordinatesEncoding() throws {
        let target = DragTarget(startX: 50, startY: 100, endX: 250, endY: 100)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(DragTarget.self, from: data)

        XCTAssertNil(decoded.elementTarget)
        XCTAssertEqual(decoded.startX, 50)
        XCTAssertEqual(decoded.startY, 100)
        XCTAssertEqual(decoded.startPoint, CGPoint(x: 50, y: 100))
    }

    func testSwipeDirectionEncoding() throws {
        let directions: [SwipeDirection] = [.up, .down, .left, .right]
        for dir in directions {
            let data = try JSONEncoder().encode(dir)
            let decoded = try JSONDecoder().decode(SwipeDirection.self, from: data)
            XCTAssertEqual(decoded, dir)
        }
    }

    func testCustomActionTargetEncoding() throws {
        let target = CustomActionTarget(
            elementTarget: ActionTarget(match: ElementMatcher(identifier: "item")),
            actionName: "Delete"
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(CustomActionTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget.match?.identifier, "item")
        XCTAssertEqual(decoded.actionName, "Delete")
    }

    func testClientMessageActionEncoding() throws {
        let activateMessage = ClientMessage.activate(ActionTarget(match: ElementMatcher(identifier: "btn")))
        let data = try JSONEncoder().encode(activateMessage)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .activate(let target) = decoded {
            XCTAssertEqual(target.match?.identifier, "btn")
        } else {
            XCTFail("Expected activate message")
        }
    }

    func testActionResultEncoding() throws {
        let result = ActionResult(
            success: true,
            method: .activate,
            message: nil
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.method, .activate)
        XCTAssertNil(decoded.message)
    }

    func testActionResultWithMessageEncoding() throws {
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

    func testClientMessageTouchSwipeEncoding() throws {
        let message = ClientMessage.touchSwipe(SwipeTarget(
            startX: 100, startY: 400, endX: 100, endY: 100
        ))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .touchSwipe(let target) = decoded {
            XCTAssertEqual(target.startX, 100)
            XCTAssertEqual(target.endY, 100)
        } else {
            XCTFail("Expected touchSwipe message")
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

    // MARK: - Multi-Touch Target Tests

    func testPinchTargetWithElementEncoding() throws {
        let target = PinchTarget(elementTarget: ActionTarget(match: ElementMatcher(identifier: "mapView")), scale: 2.0, spread: 80, duration: 0.3)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(PinchTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.match?.identifier, "mapView")
        XCTAssertEqual(decoded.scale, 2.0)
        XCTAssertEqual(decoded.spread, 80)
        XCTAssertEqual(decoded.duration, 0.3)
        XCTAssertNil(decoded.centerX)
    }

    func testPinchTargetWithCoordinatesEncoding() throws {
        let target = PinchTarget(centerX: 200, centerY: 300, scale: 0.5)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(PinchTarget.self, from: data)

        XCTAssertNil(decoded.elementTarget)
        XCTAssertEqual(decoded.centerX, 200)
        XCTAssertEqual(decoded.centerY, 300)
        XCTAssertEqual(decoded.scale, 0.5)
        XCTAssertNil(decoded.spread)
        XCTAssertNil(decoded.duration)
    }

    func testRotateTargetWithElementEncoding() throws {
        let target = RotateTarget(elementTarget: ActionTarget(match: ElementMatcher(identifier: "imageView")), angle: 1.57, radius: 50, duration: 0.8)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(RotateTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.match?.identifier, "imageView")
        XCTAssertEqual(decoded.angle, 1.57)
        XCTAssertEqual(decoded.radius, 50)
        XCTAssertEqual(decoded.duration, 0.8)
        XCTAssertNil(decoded.centerX)
    }

    func testRotateTargetWithCoordinatesEncoding() throws {
        let target = RotateTarget(centerX: 150, centerY: 250, angle: -0.785)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(RotateTarget.self, from: data)

        XCTAssertNil(decoded.elementTarget)
        XCTAssertEqual(decoded.centerX, 150)
        XCTAssertEqual(decoded.centerY, 250)
        XCTAssertEqual(decoded.angle, -0.785)
        XCTAssertNil(decoded.radius)
        XCTAssertNil(decoded.duration)
    }

    func testTwoFingerTapTargetWithElementEncoding() throws {
        let target = TwoFingerTapTarget(elementTarget: ActionTarget(match: ElementMatcher(identifier: "zoomControl")), spread: 60)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TwoFingerTapTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.match?.identifier, "zoomControl")
        XCTAssertEqual(decoded.spread, 60)
        XCTAssertNil(decoded.centerX)
    }

    func testTwoFingerTapTargetWithCoordinatesEncoding() throws {
        let target = TwoFingerTapTarget(centerX: 100, centerY: 200)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TwoFingerTapTarget.self, from: data)

        XCTAssertNil(decoded.elementTarget)
        XCTAssertEqual(decoded.centerX, 100)
        XCTAssertEqual(decoded.centerY, 200)
        XCTAssertNil(decoded.spread)
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

    // MARK: - Draw Path Target Tests

    func testDrawPathTargetEncoding() throws {
        let target = DrawPathTarget(
            points: [PathPoint(x: 100, y: 200), PathPoint(x: 150, y: 250), PathPoint(x: 200, y: 300)],
            duration: 1.0
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(DrawPathTarget.self, from: data)

        XCTAssertEqual(decoded.points.count, 3)
        XCTAssertEqual(decoded.points[0].x, 100)
        XCTAssertEqual(decoded.points[0].y, 200)
        XCTAssertEqual(decoded.points[2].x, 200)
        XCTAssertEqual(decoded.duration, 1.0)
        XCTAssertNil(decoded.velocity)
    }

    func testDrawPathTargetWithVelocityEncoding() throws {
        let target = DrawPathTarget(
            points: [PathPoint(x: 0, y: 0), PathPoint(x: 100, y: 0)],
            velocity: 500
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(DrawPathTarget.self, from: data)

        XCTAssertEqual(decoded.points.count, 2)
        XCTAssertNil(decoded.duration)
        XCTAssertEqual(decoded.velocity, 500)
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

    func testPathPointCGPoint() throws {
        let point = PathPoint(x: 42.5, y: 99.1)
        XCTAssertEqual(point.cgPoint, CGPoint(x: 42.5, y: 99.1))
    }

    // MARK: - Draw Bezier Target Tests

    func testBezierSegmentEncoding() throws {
        let segment = BezierSegment(cp1X: 10, cp1Y: 20, cp2X: 30, cp2Y: 40, endX: 50, endY: 60)
        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(BezierSegment.self, from: data)

        XCTAssertEqual(decoded.cp1X, 10)
        XCTAssertEqual(decoded.cp1Y, 20)
        XCTAssertEqual(decoded.cp2X, 30)
        XCTAssertEqual(decoded.cp2Y, 40)
        XCTAssertEqual(decoded.endX, 50)
        XCTAssertEqual(decoded.endY, 60)
        XCTAssertEqual(decoded.cp1, CGPoint(x: 10, y: 20))
        XCTAssertEqual(decoded.cp2, CGPoint(x: 30, y: 40))
        XCTAssertEqual(decoded.end, CGPoint(x: 50, y: 60))
    }

    func testDrawBezierTargetEncoding() throws {
        let target = DrawBezierTarget(
            startX: 100, startY: 400,
            segments: [
                BezierSegment(cp1X: 100, cp1Y: 200, cp2X: 300, cp2Y: 200, endX: 300, endY: 400)
            ],
            samplesPerSegment: 30,
            duration: 1.5
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(DrawBezierTarget.self, from: data)

        XCTAssertEqual(decoded.startX, 100)
        XCTAssertEqual(decoded.startY, 400)
        XCTAssertEqual(decoded.startPoint, CGPoint(x: 100, y: 400))
        XCTAssertEqual(decoded.segments.count, 1)
        XCTAssertEqual(decoded.segments[0].endX, 300)
        XCTAssertEqual(decoded.samplesPerSegment, 30)
        XCTAssertEqual(decoded.duration, 1.5)
        XCTAssertNil(decoded.velocity)
    }

    func testDrawBezierTargetWithVelocityEncoding() throws {
        let target = DrawBezierTarget(
            startX: 0, startY: 0,
            segments: [
                BezierSegment(cp1X: 33, cp1Y: 0, cp2X: 66, cp2Y: 0, endX: 100, endY: 0)
            ],
            velocity: 300
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(DrawBezierTarget.self, from: data)

        XCTAssertNil(decoded.duration)
        XCTAssertEqual(decoded.velocity, 300)
        XCTAssertNil(decoded.samplesPerSegment)
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

    func testAllActionMethods() throws {
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
            .waitForIdle,
            .elementNotFound,
            .elementDeallocated
        ]

        for method in methods {
            let result = ActionResult(success: true, method: method)
            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
            XCTAssertEqual(decoded.method, method)
        }
    }

    // MARK: - TypeText Tests

    func testTypeTextTargetEncoding() throws {
        let target = TypeTextTarget(text: "hello", elementTarget: ActionTarget(match: ElementMatcher(identifier: "textField")))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TypeTextTarget.self, from: data)

        XCTAssertEqual(decoded.text, "hello")
        XCTAssertNil(decoded.deleteCount)
        XCTAssertEqual(decoded.elementTarget?.match?.identifier, "textField")
    }

    func testTypeTextTargetWithDeleteCountEncoding() throws {
        let target = TypeTextTarget(text: "world", deleteCount: 5, elementTarget: ActionTarget(match: ElementMatcher(identifier: "input")))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TypeTextTarget.self, from: data)

        XCTAssertEqual(decoded.text, "world")
        XCTAssertEqual(decoded.deleteCount, 5)
        XCTAssertEqual(decoded.elementTarget?.match?.identifier, "input")
    }

    func testClientMessageTypeTextEncoding() throws {
        let message = ClientMessage.typeText(TypeTextTarget(text: "abc", elementTarget: ActionTarget(match: ElementMatcher(identifier: "field"))))
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .typeText(let target) = decoded {
            XCTAssertEqual(target.text, "abc")
            XCTAssertEqual(target.elementTarget?.match?.identifier, "field")
        } else {
            XCTFail("Expected typeText message")
        }
    }

    func testTypeTextActionResult() throws {
        let result = ActionResult(success: true, method: .typeText, value: "hello world")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.method, .typeText)
        XCTAssertEqual(decoded.value, "hello world")
    }

    // MARK: - EditAction Tests

    func testEditActionTargetEncoding() throws {
        let target = EditActionTarget(action: .copy)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(EditActionTarget.self, from: data)

        XCTAssertEqual(decoded.action, .copy)
    }

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

    func testEditActionResult() throws {
        let result = ActionResult(success: true, method: .editAction, message: "Pasted")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.method, .editAction)
        XCTAssertEqual(decoded.message, "Pasted")
    }

    // MARK: - ResignFirstResponder Tests

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

    func testResignFirstResponderActionResult() throws {
        let result = ActionResult(success: true, method: .resignFirstResponder)
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.method, .resignFirstResponder)
    }

    // MARK: - WaitForIdle Tests

    func testWaitForIdleTargetEncoding() throws {
        let target = WaitForIdleTarget(timeout: 10.0)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(WaitForIdleTarget.self, from: data)

        XCTAssertEqual(decoded.timeout, 10.0)
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

    func testWaitForIdleActionResult() throws {
        let result = ActionResult(success: true, method: .waitForIdle, message: "UI is idle")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.method, .waitForIdle)
        XCTAssertEqual(decoded.message, "UI is idle")
    }
}
