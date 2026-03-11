import XCTest
 import TheScore

final class ServerMessageTests: XCTestCase {

    func testInfoEncodeDecode() throws {
        let info = ServerInfo(
            protocolVersion: "1.0",
            appName: "TestApp",
            bundleIdentifier: "com.test.app",
            deviceName: "iPhone",
            systemVersion: "17.0",
            screenWidth: 390,
            screenHeight: 844
        )
        let message = ServerMessage.info(info)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .info(let decodedInfo) = decoded {
            XCTAssertEqual(decodedInfo.protocolVersion, "1.0")
            XCTAssertEqual(decodedInfo.appName, "TestApp")
            XCTAssertEqual(decodedInfo.bundleIdentifier, "com.test.app")
        } else {
            XCTFail("Expected info, got \(decoded)")
        }
    }

    func testStatusEncodeDecode() throws {
        let payload = StatusPayload(
            identity: StatusIdentity(
                appName: "ReachableApp",
                bundleIdentifier: "com.test.reachable",
                appBuild: "42",
                deviceName: "iPhone",
                systemVersion: "18.0",
                buttonHeistVersion: "5.0"
            ),
            session: StatusSession(
                active: true,
                watchersAllowed: false,
                activeConnections: 1
            )
        )
        let message = ServerMessage.status(payload)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .status(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.identity.appName, "ReachableApp")
            XCTAssertEqual(decodedPayload.identity.bundleIdentifier, "com.test.reachable")
            XCTAssertEqual(decodedPayload.session.active, true)
            XCTAssertEqual(decodedPayload.session.activeConnections, 1)
        } else {
            XCTFail("Expected status, got \(decoded)")
        }
    }

    func testInterfaceEncodeDecode() throws {
        let element = HeistElement(
            order: 0,
            description: "Button",
            label: "Submit",
            value: nil,
            identifier: "submit_btn",
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let payload = Interface(timestamp: Date(), elements: [element])
        let message = ServerMessage.interface(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .interface(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.elements.count, 1)
            XCTAssertEqual(decodedPayload.elements[0].label, "Submit")
        } else {
            XCTFail("Expected interface, got \(decoded)")
        }
    }

    func testPongEncodeDecode() throws {
        let message = ServerMessage.pong
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .pong = decoded {
            // Success
        } else {
            XCTFail("Expected pong, got \(decoded)")
        }
    }

    func testErrorEncodeDecode() throws {
        let message = ServerMessage.error("Connection failed")
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .error(let errorMsg) = decoded {
            XCTAssertEqual(errorMsg, "Connection failed")
        } else {
            XCTFail("Expected error, got \(decoded)")
        }
    }

    // MARK: - ActionResult Tests

    func testActionResultWithValue() throws {
        let result = ActionResult(success: true, method: .typeText, value: "Hello World")
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertTrue(decodedResult.success)
            XCTAssertEqual(decodedResult.method, .typeText)
            XCTAssertEqual(decodedResult.value, "Hello World")
            XCTAssertNil(decodedResult.message)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultWithoutValue() throws {
        let result = ActionResult(success: true, method: .syntheticTap)
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertTrue(decodedResult.success)
            XCTAssertEqual(decodedResult.method, .syntheticTap)
            XCTAssertNil(decodedResult.value)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testActionResultWithoutOptionalFieldsFromExplicitJSON() throws {
        let json = """
        {"type":"actionResult","payload":{"success":true,"method":"syntheticTap"}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let result) = decoded {
            XCTAssertTrue(result.success)
            XCTAssertEqual(result.method, .syntheticTap)
            XCTAssertNil(result.value)
            XCTAssertNil(result.message)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testScreenEncodeDecode() throws {
        let payload = ScreenPayload(
            pngData: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            width: 390,
            height: 844
        )
        let message = ServerMessage.screen(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .screen(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.pngData, payload.pngData)
            XCTAssertEqual(decodedPayload.width, 390)
            XCTAssertEqual(decodedPayload.height, 844)
        } else {
            XCTFail("Expected screen, got \(decoded)")
        }
    }
}
