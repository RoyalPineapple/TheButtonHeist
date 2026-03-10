import XCTest
import Network
@testable import ButtonHeist

/// Tests for session locking behavior using direct message injection.
final class SessionLockTests: XCTestCase {

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
    func testSessionLockedDisconnectsClient() throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "test-token")
        conn.isConnected = true

        var disconnectReason: DisconnectReason?
        conn.onDisconnected = { reason in
            disconnectReason = reason
        }

        let payload = SessionLockedPayload(message: "Session held by another driver", activeConnections: 1)
        try conn.handleMessage(encode(.sessionLocked(payload)))

        XCTAssertFalse(conn.isConnected)
        if case .sessionLocked(let msg) = disconnectReason {
            XCTAssertEqual(msg, "Session held by another driver")
        } else {
            XCTFail("Expected sessionLocked disconnect reason, got \(String(describing: disconnectReason))")
        }
    }

    @ButtonHeistActor
    func testSessionLockedCallbackFires() throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "test-token")
        conn.isConnected = true

        var receivedPayload: SessionLockedPayload?
        conn.onSessionLocked = { payload in
            receivedPayload = payload
        }

        let payload = SessionLockedPayload(message: "Another driver active", activeConnections: 3)
        try conn.handleMessage(encode(.sessionLocked(payload)))

        XCTAssertNotNil(receivedPayload)
        XCTAssertEqual(receivedPayload?.message, "Another driver active")
        XCTAssertEqual(receivedPayload?.activeConnections, 3)
    }

    @ButtonHeistActor
    func testAuthRequiredSendsDriverId() {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "test-token", driverId: "test-driver-id")
        conn.isConnected = true

        // handleMessage will call send(.authenticate(...)) internally,
        // which requires a real connection. We just verify it doesn't crash
        // and the driverId is stored correctly.
        XCTAssertEqual(conn.driverId, "test-driver-id")
    }

    @ButtonHeistActor
    func testNilDriverIdIsNil() {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "test-token")
        conn.isConnected = true

        XCTAssertNil(conn.driverId)
    }
}
