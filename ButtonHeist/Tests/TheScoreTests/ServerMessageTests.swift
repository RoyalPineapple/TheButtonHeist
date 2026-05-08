import XCTest
 import TheScore

final class ServerMessageTests: XCTestCase {

    func testInfoEncodeDecode() throws {
        let info = ServerInfo(
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
            description: "Button",
            label: "Submit",
            value: nil,
            identifier: "submit_btn",
            frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 44,
            actions: [.activate]
        )
        let payload = Interface(timestamp: Date(), tree: [.element(element)])
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

    func testActionResultWithErrorKind() throws {
        let result = ActionResult(
            success: false,
            method: .syntheticTap,
            message: "Element not found",
            errorKind: .elementNotFound
        )
        let message = ServerMessage.actionResult(result)
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

        if case .actionResult(let decodedResult) = decoded {
            XCTAssertFalse(decodedResult.success)
            XCTAssertEqual(decodedResult.errorKind, .elementNotFound)
            XCTAssertEqual(decodedResult.message, "Element not found")
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    func testErrorKindAllCasesRoundTrip() throws {
        for kind in ErrorKind.allCases {
            let result = ActionResult(success: false, method: .syntheticTap, errorKind: kind)
            let data = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
            XCTAssertEqual(decoded.errorKind, kind, "Round-trip failed for \(kind)")
        }
    }

    func testActionResultWithoutErrorKindDecodesAsNil() throws {
        let json = """
        {"type":"actionResult","payload":{"success":false,"method":"syntheticTap","message":"fail"}}
        """
        let decoded = try JSONDecoder().decode(ServerMessage.self, from: Data(json.utf8))

        if case .actionResult(let result) = decoded {
            XCTAssertFalse(result.success)
            XCTAssertNil(result.errorKind)
        } else {
            XCTFail("Expected actionResult, got \(decoded)")
        }
    }

    // MARK: - ResponseEnvelope backgroundDelta

    func testResponseEnvelopeWithoutBackgroundDelta() throws {
        let envelope = ResponseEnvelope(requestId: "r-1", message: .pong)
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "r-1")
        XCTAssertNil(decoded.backgroundDelta)
        if case .pong = decoded.message {
            // Success
        } else {
            XCTFail("Expected pong, got \(decoded.message)")
        }
    }

    func testResponseEnvelopeWithBackgroundDelta() throws {
        let delta = InterfaceDelta(kind: .screenChanged, elementCount: 5)
        let envelope = ResponseEnvelope(requestId: "r-2", message: .pong, backgroundDelta: delta)
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)

        XCTAssertEqual(decoded.requestId, "r-2")
        XCTAssertNotNil(decoded.backgroundDelta)
        XCTAssertEqual(decoded.backgroundDelta?.kind, .screenChanged)
        XCTAssertEqual(decoded.backgroundDelta?.elementCount, 5)
    }

    func testResponseEnvelopeBackgroundDeltaBackwardCompatible() throws {
        // Envelopes from older servers (no backgroundDelta field) should decode cleanly
        let envelope = ResponseEnvelope(requestId: "compat-1", message: .pong)
        let data = try JSONEncoder().encode(envelope)

        // Re-encode without backgroundDelta by stripping it from the JSON
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "backgroundDelta")
        let strippedData = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: strippedData)
        XCTAssertNil(decoded.backgroundDelta)
        XCTAssertEqual(decoded.requestId, "compat-1")
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
