import XCTest
import Network
import TheScore
@testable import Wheelman

/// Integration tests for the auth flow over real TCP connections.
/// These exercise the approval path introduced in the connection approval feature.
final class AuthFlowIntegrationTests: XCTestCase {

    private var server: SimpleSocketServer!

    override func setUp() {
        super.setUp()
        server = SimpleSocketServer()
    }

    override func tearDown() {
        server.stop()
        server = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Start the server on loopback and return the port.
    private func startServer() throws -> UInt16 {
        try server.start(port: 0, bindToLoopback: true)
    }

    /// Create a raw NWConnection to the server on loopback.
    private func connectClient(port: UInt16) -> NWConnection {
        let connection = NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        return connection
    }

    /// Send a newline-delimited JSON message over a connection.
    private func sendMessage(_ message: ClientMessage, over connection: NWConnection) {
        guard var data = try? JSONEncoder().encode(message) else {
            XCTFail("Failed to encode message")
            return
        }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                XCTFail("Send error: \(error)")
            }
        })
    }

    /// Receive raw data from a connection (up to 65536 bytes).
    private func receiveData(from connection: NWConnection, timeout: TimeInterval = 5.0) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let deadline = DispatchTime.now() + timeout
            let workItem = DispatchWorkItem {
                continuation.resume(throwing: NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Receive timed out"]))
            }
            DispatchQueue.global().asyncAfter(deadline: deadline, execute: workItem)

            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, _, error in
                workItem.cancel()
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: NSError(domain: "test", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                }
            }
        }
    }

    /// Decode a ServerMessage from raw data (strips newline delimiter).
    private func decodeServerMessage(from data: Data) throws -> ServerMessage {
        var messageData = data
        // Strip newline delimiters and extract first message
        if let newlineIndex = messageData.firstIndex(of: 0x0A) {
            messageData = Data(messageData.prefix(upTo: newlineIndex))
        }
        return try JSONDecoder().decode(ServerMessage.self, from: messageData)
    }

    // MARK: - Tests

    func testSuccessfulTokenAuth() async throws {
        let port = try startServer()
        let authToken = "test-secret-token"

        // Set up server to handle auth
        let clientConnected = expectation(description: "client connected")
        let clientAuthenticated = expectation(description: "client authenticated")

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            // Send authRequired
            let msg = ServerMessage.authRequired
            if let data = try? JSONEncoder().encode(msg) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { clientId, data, respond in
            guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data),
                  case .authenticate(let payload) = message else {
                XCTFail("Expected authenticate message")
                return
            }

            XCTAssertEqual(payload.token, authToken)
            self.server.markAuthenticated(clientId)

            // Send info to confirm auth
            let info = ServerInfo(
                protocolVersion: "3.0",
                appName: "TestApp",
                bundleIdentifier: "com.test",
                deviceName: "Test",
                systemVersion: "18.0",
                screenWidth: 393,
                screenHeight: 852
            )
            if let data = try? JSONEncoder().encode(ServerMessage.info(info)) {
                respond(data)
            }
            clientAuthenticated.fulfill()
        }

        // Connect client
        let conn = connectClient(port: port)
        conn.start(queue: .global())

        // Wait for connection and auth
        await fulfillment(of: [clientConnected], timeout: 5.0)

        // Send authenticate with token
        sendMessage(.authenticate(AuthenticatePayload(token: authToken)), over: conn)

        await fulfillment(of: [clientAuthenticated], timeout: 5.0)

        // Receive the authRequired and info messages
        let data = try await receiveData(from: conn)
        // The data should contain at least the authRequired message
        XCTAssertGreaterThan(data.count, 0)

        conn.cancel()
    }

    func testEmptyTokenTriggersUnauthenticatedCallback() async throws {
        let port = try startServer()

        let clientConnected = expectation(description: "client connected")
        let emptyTokenReceived = expectation(description: "empty token received")

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            let msg = ServerMessage.authRequired
            if let data = try? JSONEncoder().encode(msg) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { _, data, _ in
            guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data),
                  case .authenticate(let payload) = message else {
                XCTFail("Expected authenticate message")
                return
            }

            // Verify empty token was sent (this is the trigger for UI approval)
            XCTAssertTrue(payload.token.isEmpty, "Expected empty token for UI approval flow")
            emptyTokenReceived.fulfill()
        }

        let conn = connectClient(port: port)
        conn.start(queue: .global())

        await fulfillment(of: [clientConnected], timeout: 5.0)

        // Send authenticate with empty token (simulating no-token client)
        sendMessage(.authenticate(AuthenticatePayload(token: "")), over: conn)

        await fulfillment(of: [emptyTokenReceived], timeout: 5.0)

        conn.cancel()
    }

    func testAuthApprovedFlowEndToEnd() async throws {
        let port = try startServer()
        let approvalToken = "auto-generated-uuid-token"

        let clientConnected = expectation(description: "client connected")
        let emptyTokenReceived = expectation(description: "empty token received")
        let authenticatedMessageReceived = expectation(description: "authenticated message received")

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            let msg = ServerMessage.authRequired
            if let data = try? JSONEncoder().encode(msg) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { clientId, data, respond in
            guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data),
                  case .authenticate(let payload) = message else {
                return
            }

            if payload.token.isEmpty {
                emptyTokenReceived.fulfill()

                // Simulate UI approval: mark authenticated, send authApproved, then info
                self.server.markAuthenticated(clientId)
                let approved = ServerMessage.authApproved(AuthApprovedPayload(token: approvalToken))
                if let data = try? JSONEncoder().encode(approved) {
                    respond(data)
                }

                // Send info after approval
                let info = ServerInfo(
                    protocolVersion: "3.0",
                    appName: "TestApp",
                    bundleIdentifier: "com.test",
                    deviceName: "Test",
                    systemVersion: "18.0",
                    screenWidth: 393,
                    screenHeight: 852
                )
                if let data = try? JSONEncoder().encode(ServerMessage.info(info)) {
                    self.server.send(data, to: clientId)
                }
            }
        }

        server.onDataReceived = { _, _, _ in
            // This callback means the client is authenticated and can send messages
            authenticatedMessageReceived.fulfill()
        }

        let conn = connectClient(port: port)
        conn.start(queue: .global())

        await fulfillment(of: [clientConnected], timeout: 5.0)

        // Send empty token to trigger approval flow
        sendMessage(.authenticate(AuthenticatePayload(token: "")), over: conn)

        await fulfillment(of: [emptyTokenReceived], timeout: 5.0)

        // Receive the authRequired and authApproved messages
        let data = try await receiveData(from: conn)
        XCTAssertGreaterThan(data.count, 0)

        // Parse all messages from the received data
        var buffer = data
        var receivedAuthApproved = false
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let msgData = Data(buffer.prefix(upTo: newlineIndex))
            buffer = Data(buffer.suffix(from: buffer.index(after: newlineIndex)))
            if !msgData.isEmpty, let msg = try? JSONDecoder().decode(ServerMessage.self, from: msgData) {
                if case .authApproved(let payload) = msg {
                    XCTAssertEqual(payload.token, approvalToken)
                    receivedAuthApproved = true
                }
            }
        }

        // May need to receive more data if authApproved is in a separate packet
        if !receivedAuthApproved {
            let moreData = try await receiveData(from: conn)
            var moreBuffer = moreData
            while let newlineIndex = moreBuffer.firstIndex(of: 0x0A) {
                let msgData = Data(moreBuffer.prefix(upTo: newlineIndex))
                moreBuffer = Data(moreBuffer.suffix(from: moreBuffer.index(after: newlineIndex)))
                if !msgData.isEmpty, let msg = try? JSONDecoder().decode(ServerMessage.self, from: msgData) {
                    if case .authApproved(let payload) = msg {
                        XCTAssertEqual(payload.token, approvalToken)
                        receivedAuthApproved = true
                    }
                }
            }
        }

        XCTAssertTrue(receivedAuthApproved, "Expected to receive authApproved message with token")

        // Now send a message as an authenticated client
        sendMessage(.ping, over: conn)

        await fulfillment(of: [authenticatedMessageReceived], timeout: 5.0)

        conn.cancel()
    }

    func testAuthDeniedDisconnects() async throws {
        let port = try startServer()

        let clientConnected = expectation(description: "client connected")
        let emptyTokenReceived = expectation(description: "empty token received")
        let clientDisconnected = expectation(description: "client disconnected")
        // removeClient can be called multiple times (from disconnect + .cancelled state handler)
        clientDisconnected.assertForOverFulfill = false

        server.onClientConnected = { clientId in
            clientConnected.fulfill()
            let msg = ServerMessage.authRequired
            if let data = try? JSONEncoder().encode(msg) {
                self.server.send(data, to: clientId)
            }
        }

        server.onUnauthenticatedData = { clientId, data, respond in
            guard let message = try? JSONDecoder().decode(ClientMessage.self, from: data),
                  case .authenticate(let payload) = message else {
                return
            }

            if payload.token.isEmpty {
                emptyTokenReceived.fulfill()

                // Simulate UI denial: send authFailed and disconnect
                let failed = ServerMessage.authFailed("Connection denied by user")
                if let data = try? JSONEncoder().encode(failed) {
                    respond(data)
                }

                // Disconnect after a brief delay (matching TheInsideJob behavior)
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                    self.server.disconnect(clientId: clientId)
                }
            }
        }

        server.onClientDisconnected = { _ in
            clientDisconnected.fulfill()
        }

        let conn = connectClient(port: port)
        conn.start(queue: .global())

        await fulfillment(of: [clientConnected], timeout: 5.0)

        // Send empty token
        sendMessage(.authenticate(AuthenticatePayload(token: "")), over: conn)

        await fulfillment(of: [emptyTokenReceived], timeout: 5.0)

        // Receive authFailed
        let data = try await receiveData(from: conn)
        var buffer = data
        var receivedAuthFailed = false
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let msgData = Data(buffer.prefix(upTo: newlineIndex))
            buffer = Data(buffer.suffix(from: buffer.index(after: newlineIndex)))
            if !msgData.isEmpty, let msg = try? JSONDecoder().decode(ServerMessage.self, from: msgData) {
                if case .authFailed(let reason) = msg {
                    XCTAssertEqual(reason, "Connection denied by user")
                    receivedAuthFailed = true
                }
            }
        }

        if !receivedAuthFailed {
            // Check remaining buffer for the authRequired message first
            if !buffer.isEmpty, let msg = try? JSONDecoder().decode(ServerMessage.self, from: buffer) {
                if case .authFailed(let reason) = msg {
                    XCTAssertEqual(reason, "Connection denied by user")
                    receivedAuthFailed = true
                }
            }
        }

        // authFailed may be in a separate packet after authRequired
        if !receivedAuthFailed {
            let moreData = try await receiveData(from: conn)
            var moreBuffer = moreData
            while let newlineIndex = moreBuffer.firstIndex(of: 0x0A) {
                let msgData = Data(moreBuffer.prefix(upTo: newlineIndex))
                moreBuffer = Data(moreBuffer.suffix(from: moreBuffer.index(after: newlineIndex)))
                if !msgData.isEmpty, let msg = try? JSONDecoder().decode(ServerMessage.self, from: msgData) {
                    if case .authFailed(let reason) = msg {
                        XCTAssertEqual(reason, "Connection denied by user")
                        receivedAuthFailed = true
                    }
                }
            }
        }

        XCTAssertTrue(receivedAuthFailed, "Expected to receive authFailed message")

        // Server should disconnect the client
        await fulfillment(of: [clientDisconnected], timeout: 5.0)

        conn.cancel()
    }
}
