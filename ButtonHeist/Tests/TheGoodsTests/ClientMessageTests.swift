import XCTest
 import TheGoods

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
            elementTarget: ActionTarget(identifier: "nameField")
        )
        let message = ClientMessage.typeText(target)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ClientMessage.self, from: data)

        if case .typeText(let decodedTarget) = decoded {
            XCTAssertEqual(decodedTarget.text, "Hello")
            XCTAssertEqual(decodedTarget.elementTarget?.identifier, "nameField")
        } else {
            XCTFail("Expected typeText, got \(decoded)")
        }
    }
}
