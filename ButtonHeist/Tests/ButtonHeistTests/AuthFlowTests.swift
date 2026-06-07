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
    func testAuthRequiredIsEmittedToHandoff() async throws {
        let conn = DeviceConnection(device: makeDummyDevice())
        conn.simulateConnected()

        var receivedAuthRequired = false
        conn.onEvent = { event in
            if case .message(.authRequired, _) = event {
                receivedAuthRequired = true
            }
        }

        try conn.handleMessage(encode(.authRequired))

        XCTAssertTrue(receivedAuthRequired)
    }

    @ButtonHeistActor
    func testProtocolMismatchEmitsPayloadWithoutDisconnectingTransport() async throws {
        let conn = DeviceConnection(device: makeDummyDevice())
        conn.simulateConnected()

        var protocolMismatchPayload: ProtocolMismatchPayload?
        var disconnected = false
        conn.onEvent = { event in
            switch event {
            case .message(.protocolMismatch(let payload), _):
                protocolMismatchPayload = payload
            case .disconnected:
                disconnected = true
            default:
                break
            }
        }

        conn.handleMessage(try encode(.serverHello, buttonHeistVersion: "0.0.0"))

        XCTAssertEqual(protocolMismatchPayload?.serverButtonHeistVersion, "0.0.0")
        XCTAssertEqual(protocolMismatchPayload?.clientButtonHeistVersion, buttonHeistVersion)
        assertDeviceConnectionConnected(conn)
        XCTAssertFalse(disconnected)
    }

    @ButtonHeistActor
    func testAuthApprovedEmitsTokenForHandoff() async throws {
        let conn = DeviceConnection(device: makeDummyDevice())
        conn.simulateConnected()

        var approvedToken: String?
        conn.onEvent = { event in
            if case .message(.authApproved(let payload), _) = event {
                approvedToken = payload.token
            }
        }

        let approvalToken = "auto-generated-uuid-token"
        try conn.handleMessage(encode(.authApproved(AuthApprovedPayload(token: approvalToken))))

        XCTAssertEqual(approvedToken, approvalToken)
    }

    @ButtonHeistActor
    func testAuthApprovedFollowedByInfo() async throws {
        let conn = DeviceConnection(device: makeDummyDevice())
        conn.simulateConnected()

        var connectedFired = false
        var receivedInfo: ServerInfo?
        conn.onEvent = { event in
            switch event {
            case .connected:
                connectedFired = true
            case .message(.info(let info), _):
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
            screenHeight: 852,
            instanceId: "test-session",
            instanceIdentifier: "test",
            listeningPort: 49152,
            tlsActive: true
        )
        try conn.handleMessage(encode(.info(info)))

        XCTAssertTrue(connectedFired, "onEvent(.connected) should fire after receiving info")
        XCTAssertEqual(receivedInfo?.appName, "TestApp")
    }

    @ButtonHeistActor
    func testAuthDeniedEmitsErrorWithoutDisconnectingTransport() async throws {
        let conn = DeviceConnection(device: makeDummyDevice())
        conn.simulateConnected()

        var authFailedReason: String?
        var disconnected = false
        conn.onEvent = { event in
            switch event {
            case .message(.error(let serverError), _) where serverError.kind == .authFailure:
                authFailedReason = serverError.message
            case .disconnected:
                disconnected = true
            default:
                break
            }
        }

        try conn.handleMessage(encode(
            .error(ServerError(kind: .authFailure, message: "Connection denied by user"))
        ))

        XCTAssertEqual(authFailedReason, "Connection denied by user")
        assertDeviceConnectionConnected(conn)
        XCTAssertFalse(disconnected)
    }

    @ButtonHeistActor
    func testAuthApprovalPendingIsNonTerminalStatus() async throws {
        let conn = DeviceConnection(device: makeDummyDevice())
        conn.simulateConnected()

        var pendingPayload: AuthApprovalPendingPayload?
        var disconnected = false
        conn.onEvent = { event in
            switch event {
            case .message(.authApprovalPending(let payload), _):
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
    func testAuthApprovalPendingErrorEmitsErrorWithoutDisconnectingTransport() async throws {
        let conn = DeviceConnection(device: makeDummyDevice())
        conn.simulateConnected()

        var serverError: ServerError?
        var disconnected = false
        conn.onEvent = { event in
            switch event {
            case .message(.error(let error), _):
                serverError = error
            case .disconnected:
                disconnected = true
            default:
                break
            }
        }

        try conn.handleMessage(encode(.error(ServerError(
            kind: .authApprovalPending,
            message: "Legacy server is waiting for UI approval."
        ))))

        XCTAssertEqual(serverError?.kind, .authApprovalPending)
        assertDeviceConnectionConnected(conn)
        XCTAssertFalse(disconnected)
    }

    @ButtonHeistActor
    func testAuthRequiredDoesNotSendFromConnection() async throws {
        let conn = DeviceConnection(device: makeDummyDevice())
        conn.simulateConnected()

        var receivedAuthRequired = false
        let sentMessages = SendContentRecorder()
        conn.onEvent = { event in
            if case .message(.authRequired, _) = event {
                receivedAuthRequired = true
            }
        }
        conn.sendContent = { _, content, completion in
            sentMessages.capture(content: content, completion: completion)
        }

        try conn.handleMessage(encode(.authRequired))

        XCTAssertTrue(receivedAuthRequired)
        XCTAssertTrue(sentMessages.messages.isEmpty, "Transport must not own auth replies")
    }
}
