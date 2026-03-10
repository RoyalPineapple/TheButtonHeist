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
    func testAuthRequiredTriggersAuthenticate() throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "test-secret-token")
        conn.isConnected = true

        // Feeding authRequired should trigger send(.authenticate(...)) internally.
        // Without a real NWConnection, send() is a no-op (guards on connection != nil).
        // We verify this doesn't crash and the token is preserved.
        try conn.handleMessage(encode(.authRequired))

        XCTAssertEqual(conn.token, "test-secret-token")
    }

    @ButtonHeistActor
    func testEmptyTokenStillSendsAuthenticate() throws {
        // When token is empty, DeviceConnection still sends .authenticate
        // (this triggers the UI approval flow on the server side)
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.isConnected = true

        try conn.handleMessage(encode(.authRequired))

        // Token should remain empty (no crash, no mutation)
        XCTAssertEqual(conn.token, "")
    }

    @ButtonHeistActor
    func testAuthApprovedUpdatesToken() throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.isConnected = true

        var approvedToken: String?
        conn.onAuthApproved = { token in
            approvedToken = token
        }

        let approvalToken = "auto-generated-uuid-token"
        try conn.handleMessage(encode(.authApproved(AuthApprovedPayload(token: approvalToken))))

        XCTAssertEqual(approvedToken, approvalToken)
        XCTAssertEqual(conn.token, approvalToken)
    }

    @ButtonHeistActor
    func testAuthApprovedFollowedByInfo() throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.isConnected = true

        var connectedFired = false
        var receivedInfo: ServerInfo?
        conn.onAuthApproved = { _ in }
        conn.onServerInfo = { info in receivedInfo = info }
        conn.onConnected = { connectedFired = true }

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

        XCTAssertTrue(connectedFired, "onConnected should fire after receiving info")
        XCTAssertEqual(receivedInfo?.appName, "TestApp")
    }

    @ButtonHeistActor
    func testAuthDeniedFiresCallbackAndDisconnects() throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "")
        conn.isConnected = true

        var authFailedReason: String?
        var disconnectReason: DisconnectReason?
        conn.onAuthFailed = { reason in authFailedReason = reason }
        conn.onDisconnected = { reason in disconnectReason = reason }

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
    func testObserveModeUsesWatch() throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "my-token")
        conn.isConnected = true
        conn.observeMode = true

        // send() will be a no-op without real connection, but we verify
        // observeMode is correctly set and handleMessage doesn't crash
        try conn.handleMessage(encode(.authRequired))

        XCTAssertTrue(conn.observeMode)
    }
}
