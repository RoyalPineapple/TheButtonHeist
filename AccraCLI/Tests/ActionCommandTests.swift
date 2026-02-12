import XCTest
import Foundation
@testable import AccraCore

final class ActionCommandTests: XCTestCase {

    // MARK: - Message Encoding Tests

    func testActionTargetEncoding() throws {
        let target = ActionTarget(identifier: "testButton", traversalIndex: 5)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(ActionTarget.self, from: data)

        XCTAssertEqual(decoded.identifier, "testButton")
        XCTAssertEqual(decoded.traversalIndex, 5)
    }

    func testTouchTapTargetWithElementEncoding() throws {
        let target = TouchTapTarget(elementTarget: ActionTarget(identifier: "button"))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TouchTapTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.identifier, "button")
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
        let target = LongPressTarget(elementTarget: ActionTarget(identifier: "btn"), duration: 1.5)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(LongPressTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.identifier, "btn")
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
            elementTarget: ActionTarget(identifier: "list"),
            direction: .up, distance: 300
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(SwipeTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.identifier, "list")
        XCTAssertEqual(decoded.direction, .up)
        XCTAssertEqual(decoded.distance, 300)
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
            elementTarget: ActionTarget(identifier: "slider"),
            endX: 300, endY: 200, duration: 0.8
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(DragTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.identifier, "slider")
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
            elementTarget: ActionTarget(identifier: "item"),
            actionName: "Delete"
        )
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(CustomActionTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget.identifier, "item")
        XCTAssertEqual(decoded.actionName, "Delete")
    }

    func testClientMessageActionEncoding() throws {
        let activateMessage = ClientMessage.activate(ActionTarget(identifier: "btn"))
        let data = try JSONEncoder().encode(activateMessage)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .activate(let target) = decoded {
            XCTAssertEqual(target.identifier, "btn")
        } else {
            XCTFail("Expected activate message")
        }
    }

    func testActionResultEncoding() throws {
        let result = ActionResult(
            success: true,
            method: .accessibilityActivate,
            message: nil
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)

        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.method, .accessibilityActivate)
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
        let target = PinchTarget(elementTarget: ActionTarget(identifier: "mapView"), scale: 2.0, spread: 80, duration: 0.3)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(PinchTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.identifier, "mapView")
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
        let target = RotateTarget(elementTarget: ActionTarget(identifier: "imageView"), angle: 1.57, radius: 50, duration: 0.8)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(RotateTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.identifier, "imageView")
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
        let target = TwoFingerTapTarget(elementTarget: ActionTarget(identifier: "zoomControl"), spread: 60)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TwoFingerTapTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.identifier, "zoomControl")
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

    func testAllActionMethods() throws {
        let methods: [ActionMethod] = [
            .accessibilityActivate,
            .accessibilityIncrement,
            .accessibilityDecrement,
            .syntheticTap,
            .syntheticLongPress,
            .syntheticSwipe,
            .syntheticDrag,
            .syntheticPinch,
            .syntheticRotate,
            .syntheticTwoFingerTap,
            .customAction,
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
}
