import XCTest
import Network
@testable import ButtonHeist

/// `@unchecked Sendable` justification: all mutable storage is protected by `lock`.
private final class SendContentRecorder: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    private let lock = NSLock()
    private var messagesStorage: [ClientMessage] = []

    var messages: [ClientMessage] {
        lock.withLock { messagesStorage }
    }

    func capture(content: Data, completion: NWConnection.SendCompletion) {
        if case .contentProcessed(let handler) = completion {
            handler(nil)
        }
        let envelope = try? JSONDecoder().decode(RequestEnvelope.self, from: Data(content.dropLast()))
        guard let message = envelope?.message else { return }
        lock.withLock {
            messagesStorage.append(message)
        }
    }
}

/// Tests for the auth flow using direct message injection.
/// Exercises the auth paths without real TCP connections.
final class AuthFlowTests: XCTestCase {

    private func makeDummyDevice() -> DiscoveredDevice {
        DiscoveredDevice(
            id: "mock",
            name: "MockApp#test",
            endpoint: NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1)
        )
    }

    private func encode(_ message: ServerMessage) throws -> Data {
        try JSONEncoder().encode(ResponseEnvelope(message: message))
    }

    private func encode(_ message: ServerMessage, buttonHeistVersion version: String) throws -> Data {
        try JSONEncoder().encode(ResponseEnvelope(buttonHeistVersion: version, message: message))
    }

    // MARK: - Tests

    @ButtonHeistActor
    func testAuthRequiredTriggersAuthenticate() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "test-secret-token")
        conn.simulateConnected()

        // Feeding authRequired should trigger send(.authenticate(...)) internally.
        // Without a real NWConnection, send() is a no-op (guards on connection != nil).
        // We verify this doesn't crash and the token is preserved.
        try conn.handleMessage(encode(.authRequired))

        XCTAssertEqual(conn.token, "test-secret-token")
    }

    @ButtonHeistActor
    func testProtocolMismatchNamesBothSidesAndDoesNotReportServerClosed() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "test-secret-token")
        conn.simulateConnected()

        var protocolMismatchPayload: ProtocolMismatchPayload?
        var disconnectReasons: [DisconnectReason] = []
        conn.onEvent = { event in
            switch event {
            case .message(.protocolMismatch(let payload), _, _):
                protocolMismatchPayload = payload
            case .disconnected(let reason):
                disconnectReasons.append(reason)
            default:
                break
            }
        }

        conn.handleMessage(try encode(.serverHello, buttonHeistVersion: "0.0.0"))

        XCTAssertEqual(protocolMismatchPayload?.serverButtonHeistVersion, "0.0.0")
        XCTAssertEqual(protocolMismatchPayload?.clientButtonHeistVersion, buttonHeistVersion)
        XCTAssertEqual(disconnectReasons.count, 1)
        guard case .protocolMismatch(let message) = disconnectReasons.first else {
            return XCTFail("Expected protocol mismatch, got \(String(describing: disconnectReasons.first))")
        }
        XCTAssertTrue(message.contains("Button Heist version mismatch"))
        XCTAssertTrue(message.contains("app/Inside Job is 0.0.0"))
        XCTAssertTrue(message.contains("client/CLI/MCP is \(buttonHeistVersion)"))
    }

    @ButtonHeistActor
    func testEmptyTokenStillSendsAuthenticate() async throws {
        // When token is empty, DeviceConnection still sends .authenticate
        // (this triggers the UI approval flow on the server side)
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.simulateConnected()

        try conn.handleMessage(encode(.authRequired))

        // Token should remain empty (no crash, no mutation)
        XCTAssertEqual(conn.token, "")
    }

    @ButtonHeistActor
    func testAuthApprovedUpdatesToken() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.simulateConnected()

        var approvedToken: String?
        conn.onEvent = { event in
            if case .message(.authApproved(let payload), _, _) = event {
                approvedToken = payload.token
            }
        }

        let approvalToken = "auto-generated-uuid-token"
        try conn.handleMessage(encode(.authApproved(AuthApprovedPayload(token: approvalToken))))

        XCTAssertEqual(approvedToken, approvalToken)
        XCTAssertEqual(conn.token, approvalToken)
    }

    @ButtonHeistActor
    func testAuthApprovedFollowedByInfo() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.simulateConnected()

        var connectedFired = false
        var receivedInfo: ServerInfo?
        conn.onEvent = { event in
            switch event {
            case .connected:
                connectedFired = true
            case .message(.info(let info), _, _):
                receivedInfo = info
            default:
                break
            }
        }

        // Simulate approval then info (the normal success flow)
        try conn.handleMessage(encode(.authApproved(AuthApprovedPayload(token: "new-token"))))

        let info = ServerInfo(
            appName: "TestApp",
            bundleIdentifier: "com.test",
            deviceName: "Test",
            systemVersion: "18.0",
            screenWidth: 393,
            screenHeight: 852
        )
        try conn.handleMessage(encode(.info(info)))

        XCTAssertTrue(connectedFired, "onEvent(.connected) should fire after receiving info")
        XCTAssertEqual(receivedInfo?.appName, "TestApp")
    }

    @ButtonHeistActor
    func testAuthDeniedFiresCallbackAndDisconnects() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.simulateConnected()

        var authFailedReason: String?
        var disconnectReason: DisconnectReason?
        conn.onEvent = { event in
            switch event {
            case .message(.error(let serverError), _, _) where serverError.kind == .authFailure:
                authFailedReason = serverError.message
            case .disconnected(let reason):
                disconnectReason = reason
            default:
                break
            }
        }

        try conn.handleMessage(encode(
            .error(ServerError(kind: .authFailure, message: "Connection denied by user"))
        ))

        XCTAssertEqual(authFailedReason, "Connection denied by user")
        assertDeviceConnectionDisconnected(conn)
        if case .authFailed(let reason) = disconnectReason {
            XCTAssertEqual(reason, "Connection denied by user")
        } else {
            XCTFail("Expected authFailed disconnect reason")
        }
    }

    @ButtonHeistActor
    func testAuthApprovalPendingIsNonTerminalStatus() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.simulateConnected()

        var pendingPayload: AuthApprovalPendingPayload?
        var disconnected = false
        conn.onEvent = { event in
            switch event {
            case .message(.authApprovalPending(let payload), _, _):
                pendingPayload = payload
            case .disconnected:
                disconnected = true
            default:
                break
            }
        }

        let payload = AuthApprovalPendingPayload()
        try conn.handleMessage(encode(.authApprovalPending(payload)))

        XCTAssertEqual(pendingPayload, payload)
        assertDeviceConnectionConnected(conn)
        XCTAssertFalse(disconnected)
    }

    @ButtonHeistActor
    func testAuthApprovalPendingErrorDisconnectsWithDistinctReason() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.simulateConnected()

        var serverError: ServerError?
        var disconnectReason: DisconnectReason?
        conn.onEvent = { event in
            switch event {
            case .message(.error(let error), _, _):
                serverError = error
            case .disconnected(let reason):
                disconnectReason = reason
            default:
                break
            }
        }

        try conn.handleMessage(encode(.error(ServerError(
            kind: .authApprovalPending,
            message: "Approval timed out — user did not respond to the approval prompt on the device."
        ))))

        XCTAssertEqual(serverError?.kind, .authApprovalPending)
        assertDeviceConnectionDisconnected(conn)
        XCTAssertEqual(
            disconnectReason,
            .authApprovalPending("Approval timed out — user did not respond to the approval prompt on the device.")
        )
    }

    @ButtonHeistActor
    func testAuthRequiredOnlyUsesAuthenticate() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "my-token")
        conn.simulateConnected()
        let sentMessages = SendContentRecorder()
        conn.sendContent = { _, content, completion in
            sentMessages.capture(content: content, completion: completion)
        }

        try conn.handleMessage(encode(.authRequired))

        guard case .authenticate(let payload) = sentMessages.messages.first else {
            return XCTFail("Expected authRequired to send authenticate")
        }
        XCTAssertEqual(payload.token, "my-token")
        XCTAssertEqual(sentMessages.messages.count, 1)
    }

    @ButtonHeistActor
    func testPassiveModeDoesNotAutoAuthenticateOnAuthRequired() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.simulateConnected()
        conn.autoRespondToAuthRequired = false

        var receivedAuthRequired = false
        let sentMessages = SendContentRecorder()
        conn.onEvent = { event in
            if case .message(.authRequired, _, _) = event {
                receivedAuthRequired = true
            }
        }
        conn.sendContent = { _, content, completion in
            sentMessages.capture(content: content, completion: completion)
        }

        try conn.handleMessage(encode(.authRequired))

        XCTAssertTrue(receivedAuthRequired)
        XCTAssertTrue(sentMessages.messages.isEmpty, "Passive probes must not send auth replies")
    }
}
