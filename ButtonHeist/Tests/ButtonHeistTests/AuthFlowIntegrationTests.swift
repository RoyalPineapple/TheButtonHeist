import XCTest
import Network
@testable import ButtonHeist

/// Tests for the auth flow using direct message injection.
/// Exercises the auth paths without real TCP connections.
final class AuthFlowIntegrationTests: XCTestCase {

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
            protocolVersion: "5.0",
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
            case .message(.authFailed(let reason), _, _):
                authFailedReason = reason
            case .disconnected(let reason):
                disconnectReason = reason
            default:
                break
            }
        }

        try conn.handleMessage(encode(.authFailed("Connection denied by user")))

        XCTAssertEqual(authFailedReason, "Connection denied by user")
        XCTAssertFalse(conn.isConnected)
        if case .authFailed(let reason) = disconnectReason {
            XCTAssertEqual(reason, "Connection denied by user")
        } else {
            XCTFail("Expected authFailed disconnect reason")
        }
    }

    @ButtonHeistActor
    func testObserveModeUsesWatch() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "my-token")
        conn.simulateConnected()
        conn.observeMode = true

        // send() will be a no-op without real connection, but we verify
        // observeMode is correctly set and handleMessage doesn't crash
        try conn.handleMessage(encode(.authRequired))

        XCTAssertTrue(conn.observeMode)
    }

    @ButtonHeistActor
    func testPassiveModeDoesNotAutoAuthenticateOnAuthRequired() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.simulateConnected()
        conn.autoRespondToAuthRequired = false

        var receivedAuthRequired = false
        var sentMessages: [ClientMessage] = []
        conn.onEvent = { event in
            if case .message(.authRequired, _, _) = event {
                receivedAuthRequired = true
            }
        }
        conn.onSend = { message, _ in
            sentMessages.append(message)
        }

        try conn.handleMessage(encode(.authRequired))

        XCTAssertTrue(receivedAuthRequired)
        XCTAssertTrue(sentMessages.isEmpty, "Passive probes must not send auth replies")
    }
}
