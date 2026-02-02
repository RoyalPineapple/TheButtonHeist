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

    func testTapTargetWithElementEncoding() throws {
        let target = TapTarget(elementTarget: ActionTarget(identifier: "button"))
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TapTarget.self, from: data)

        XCTAssertEqual(decoded.elementTarget?.identifier, "button")
        XCTAssertNil(decoded.pointX)
        XCTAssertNil(decoded.pointY)
    }

    func testTapTargetWithCoordinatesEncoding() throws {
        let target = TapTarget(pointX: 100.5, pointY: 200.5)
        let data = try JSONEncoder().encode(target)
        let decoded = try JSONDecoder().decode(TapTarget.self, from: data)

        XCTAssertNil(decoded.elementTarget)
        XCTAssertEqual(decoded.pointX, 100.5)
        XCTAssertEqual(decoded.pointY, 200.5)
        XCTAssertEqual(decoded.point, CGPoint(x: 100.5, y: 200.5))
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

    func testAllActionMethods() throws {
        let methods: [ActionMethod] = [
            .accessibilityActivate,
            .accessibilityIncrement,
            .accessibilityDecrement,
            .syntheticTap,
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
