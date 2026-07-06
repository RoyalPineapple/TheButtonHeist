import XCTest
import ThePlans
 import TheScore

// MARK: - Integration Tests

final class MessageIntegrationTests: XCTestCase {

    /// Test that a typical client-server message exchange encodes/decodes correctly
    func testClientServerExchange() throws {
        // 1. Client requests the current interface
        let clientMsg = ClientMessage.requestInterface(InterfaceQuery())
        let clientData = try JSONEncoder().encode(clientMsg)

        // 2. Server receives and decodes
        let decodedClientMsg = try JSONDecoder().decode(ClientMessage.self, from: clientData)
        if case .requestInterface = decodedClientMsg { } else {
            XCTFail("Server should receive requestInterface message")
        }

        // 3. Server sends info
        let serverInfo = ServerInfo(
            appName: "IntegrationTest",
            bundleIdentifier: "com.test.integration",
            deviceName: "Test Device",
            systemVersion: "17.0",
            screenWidth: 390,
            screenHeight: 844,
            instanceId: "integration-session",
            instanceIdentifier: "integration",
            listeningPort: 49152,
            tlsActive: true
        )
        let serverMsg = ServerMessage.info(serverInfo)
        let serverData = try JSONEncoder().encode(serverMsg)

        // 4. Client receives and decodes
        let decodedServerMsg = try JSONDecoder().decode(ServerMessage.self, from: serverData)
        if case .info(let info) = decodedServerMsg {
            XCTAssertEqual(info.appName, "IntegrationTest")
        } else {
            XCTFail("Client should receive info message")
        }
    }

    /// Test snapshot payload with multiple elements
    func testLargeSnapshotPayload() throws {
        let elements = (0..<100).map { i -> HeistElement in
            let value: String? = i % 2 == 0 ? "Value" : nil
            let actions: [ElementAction] = i % 3 == 0 ? [.activate] : []
            return HeistElement(
                description: "Element \(i)",
                label: "Label \(i)",
                value: value,
                identifier: "element_\(i)",
                frameX: Double(i * 10), frameY: Double(i * 5),
                frameWidth: 100, frameHeight: 44,
                actions: actions
            )
        }

        let payload = makeTestInterface(elements: elements, timestamp: Date())
        let message = ServerMessage.interface(payload)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ServerMessage.self, from: data)

        if case .interface(let decodedPayload) = decoded {
            XCTAssertEqual(decodedPayload.projectedElements.count, 100)
            XCTAssertEqual(decodedPayload.projectedElements[50].label, "Label 50")
        } else {
            XCTFail("Expected interface message")
        }
    }

    /// Test all message types round-trip in sequence
    func testAllMessageTypesSequence() throws {
        let clientMessages: [ClientMessage] = [
            .requestInterface(InterfaceQuery()),
            .ping,
            .status,
            .requestScreen()
        ]

        for msg in clientMessages {
            let data = try JSONEncoder().encode(msg)
            _ = try JSONDecoder().decode(ClientMessage.self, from: data)
        }

        let serverMessages: [ServerMessage] = [
            .info(ServerInfo(
                appName: "Test", bundleIdentifier: "com.test",
                deviceName: "Device", systemVersion: "17.0", screenWidth: 390, screenHeight: 844,
                instanceId: "test-session", instanceIdentifier: "test", listeningPort: 49152, tlsActive: true
            )),
            .interface(Interface(timestamp: Date(), tree: [])),
            .pong(),
            .status(StatusPayload(
                identity: StatusIdentity(
                    appName: "Test",
                    bundleIdentifier: "com.test",
                    appBuild: "1",
                    deviceName: "Device",
                    systemVersion: "17.0",
                    buttonHeistVersion: buttonHeistVersion
                ),
                session: StatusSession(active: false, watchersAllowed: false, activeConnections: 0)
            )),
            .error(ServerError(kind: .general, message: "Test error")),
            .screen(ScreenPayload(pngData: "base64data", width: 390, height: 844, interface: Interface(timestamp: Date(), tree: [])))
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
            let pongMsg = ServerMessage.pong()
            let pongData = try JSONEncoder().encode(pongMsg)
            let decodedPong = try JSONDecoder().decode(ServerMessage.self, from: pongData)

            if case .pong = decodedPong {
            } else {
                XCTFail("Expected pong response")
            }
        } else {
            XCTFail("Expected ping message")
        }
    }

    /// Test repeated interface responses
    func testInterfaceResponseSequence() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for i in 0..<5 {
            let element = HeistElement(
                description: "Update \(i)",
                label: "Label \(i)",
                value: nil,
                identifier: nil,
                frameX: 0, frameY: 0, frameWidth: 100, frameHeight: 44,
                actions: []
            )
            let payload = makeTestInterface(elements: [element], timestamp: Date())
            let msg = ServerMessage.interface(payload)

            let data = try encoder.encode(msg)
            let decoded = try decoder.decode(ServerMessage.self, from: data)

            if case .interface(let decodedPayload) = decoded {
                XCTAssertEqual(decodedPayload.projectedElements[0].label, "Label \(i)")
            } else {
                XCTFail("Expected interface update \(i)")
            }
        }
    }

    /// Test error handling
    func testErrorMessageFlow() throws {
        let errorMessages = [
            "Connection failed",
            "Invalid request",
            "Server busy",
            "Timeout",
        ]

        for errorMsg in errorMessages {
            let msg = ServerMessage.error(ServerError(kind: .general, message: errorMsg))
            let data = try JSONEncoder().encode(msg)
            let decoded = try JSONDecoder().decode(ServerMessage.self, from: data)

            if case .error(let serverError) = decoded {
                XCTAssertEqual(serverError.kind, .general)
                XCTAssertEqual(serverError.message, errorMsg)
            } else {
                XCTFail("Expected error message")
            }
        }
    }

    func testErrorMessageRejectsEmptyMessageOnDecode() {
        let json = #"{"type":"error","payload":{"kind":"general","message":""}}"#

        XCTAssertThrowsError(try JSONDecoder().decode(ServerMessage.self, from: Data(json.utf8))) { error in
            XCTAssertTrue("\(error)".contains("server error message must not be empty"), "\(error)")
        }
    }
}
