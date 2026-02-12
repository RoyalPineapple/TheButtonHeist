import XCTest
 import TheGoods

// MARK: - Integration Tests

final class MessageIntegrationTests: XCTestCase {

    /// Test that a typical client-server message exchange encodes/decodes correctly
    func testClientServerExchange() throws {
        // 1. Client sends subscribe
        let clientMsg = ClientMessage.subscribe
        let clientData = try JSONEncoder().encode(clientMsg)

        // 2. Server receives and decodes
        let decodedClientMsg = try JSONDecoder().decode(ClientMessage.self, from: clientData)
        if case .subscribe = decodedClientMsg { } else {
            XCTFail("Server should receive subscribe message")
        }

        // 3. Server sends info
        let serverInfo = ServerInfo(
            protocolVersion: protocolVersion,
            appName: "IntegrationTest",
            bundleIdentifier: "com.test.integration",
            deviceName: "Test Device",
            systemVersion: "17.0",
            screenWidth: 390,
            screenHeight: 844
        )
        let serverMsg = ServerMessage.info(serverInfo)
        let serverData = try JSONEncoder().encode(serverMsg)

        // 4. Client receives and decodes
        let decodedServerMsg = try JSONDecoder().decode(ServerMessage.self, from: serverData)
        if case .info(let info) = decodedServerMsg {
            XCTAssertEqual(info.protocolVersion, protocolVersion)
        } else {
            XCTFail("Client should receive info message")
        }
    }

    /// Test hierarchy payload with multiple elements
    func testLargeHierarchyPayload() throws {
        let elements = (0..<100).map { i in
            AccessibilityElementData(
                traversalIndex: i,
                description: "Element \(i)",
                label: "Label \(i)",
                value: i % 2 == 0 ? "Value" : nil,
                traits: i % 3 == 0 ? ["button"] : [],
                identifier: "element_\(i)",
                hint: nil,
                frameX: Double(i * 10), frameY: Double(i * 5),
                frameWidth: 100, frameHeight: 44,
                activationPointX: Double(i * 10 + 50), activationPointY: Double(i * 5 + 22),
                customActions: []
            )
        }

        let payload = HierarchyPayload(timestamp: Date(), elements: elements)
        let message = ServerMessage.hierarchy(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .hierarchy(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.elements.count, 100)
            XCTAssertEqual(decodedPayload.elements[50].traversalIndex, 50)
        } else {
            XCTFail("Expected hierarchy message")
        }
    }

    /// Test all message types round-trip in sequence
    func testAllMessageTypesSequence() throws {
        let clientMessages: [ClientMessage] = [
            .subscribe,
            .requestHierarchy,
            .ping,
            .unsubscribe,
            .requestScreenshot
        ]

        for msg in clientMessages {
            let data = try JSONEncoder().encode(msg)
            _ = try JSONDecoder().decode(ClientMessage.self, from: data)
        }

        let serverMessages: [ServerMessage] = [
            .info(ServerInfo(
                protocolVersion: "1.0", appName: "Test", bundleIdentifier: "com.test",
                deviceName: "Device", systemVersion: "17.0", screenWidth: 390, screenHeight: 844
            )),
            .hierarchy(HierarchyPayload(timestamp: Date(), elements: [])),
            .pong,
            .error("Test error"),
            .screenshot(ScreenshotPayload(pngData: "base64data", width: 390, height: 844))
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for msg in serverMessages {
            let data = try encoder.encode(msg)
            _ = try decoder.decode(ServerMessage.self, from: data)
        }
    }

    /// Test ping-pong exchange
    func testPingPongExchange() throws {
        // Client sends ping
        let pingMsg = ClientMessage.ping
        let pingData = try JSONEncoder().encode(pingMsg)
        let decodedPing = try JSONDecoder().decode(ClientMessage.self, from: pingData)

        if case .ping = decodedPing {
            // Server responds with pong
            let pongMsg = ServerMessage.pong
            let pongData = try JSONEncoder().encode(pongMsg)
            let decodedPong = try JSONDecoder().decode(ServerMessage.self, from: pongData)

            if case .pong = decodedPong {
                // Success
            } else {
                XCTFail("Expected pong response")
            }
        } else {
            XCTFail("Expected ping message")
        }
    }

    /// Test full subscription flow
    func testSubscriptionFlow() throws {
        // 1. Client subscribes
        let subscribeData = try JSONEncoder().encode(ClientMessage.subscribe)
        let decodedSubscribe = try JSONDecoder().decode(ClientMessage.self, from: subscribeData)
        if case .subscribe = decodedSubscribe { } else {
            XCTFail("Expected subscribe message")
        }

        // 2. Server sends hierarchy updates
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for i in 0..<5 {
            let element = AccessibilityElementData(
                traversalIndex: 0,
                description: "Update \(i)",
                label: "Label \(i)",
                value: nil,
                traits: [],
                identifier: nil,
                hint: nil,
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
                activationPointX: 50, activationPointY: 22,
                customActions: []
            )
            let payload = HierarchyPayload(timestamp: Date(), elements: [element])
            let msg = ServerMessage.hierarchy(payload)

            let data = try encoder.encode(msg)
            let decoded = try decoder.decode(ServerMessage.self, from: data)

            if case .hierarchy(let decodedPayload) = decoded {
                XCTAssertEqual(decodedPayload.elements[0].label, "Label \(i)")
            } else {
                XCTFail("Expected hierarchy update \(i)")
            }
        }

        // 3. Client unsubscribes
        let unsubscribeData = try JSONEncoder().encode(ClientMessage.unsubscribe)
        let decodedUnsubscribe = try JSONDecoder().decode(ClientMessage.self, from: unsubscribeData)
        if case .unsubscribe = decodedUnsubscribe { } else {
            XCTFail("Expected unsubscribe message")
        }
    }

    /// Test error handling
    func testErrorMessageFlow() throws {
        let errorMessages = [
            "Connection failed",
            "Invalid request",
            "Server busy",
            "Timeout",
            ""  // Empty error message
        ]

        for errorMsg in errorMessages {
            let msg = ServerMessage.error(errorMsg)
            let data = try JSONEncoder().encode(msg)
            let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

            if case .error(let decodedError) = decoded {
                XCTAssertEqual(decodedError, errorMsg)
            } else {
                XCTFail("Expected error message")
            }
        }
    }
}
