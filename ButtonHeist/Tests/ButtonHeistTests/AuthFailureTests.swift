import XCTest
import Network
@testable import ButtonHeist

/// Thread-safe ordered log for tracking callback invocation order.
private final class CallOrder: @unchecked Sendable {
    private var entries: [String] = []
    private let lock = NSLock()

    var first: String? {
        lock.withLock { entries.first }
    }

    func append(_ entry: String) {
        lock.withLock { entries.append(entry) }
    }
}

/// Tests for auth failure handling using direct message injection.
/// Validates that authFailed fires correctly and isn't swallowed by the subsequent disconnect.
final class AuthFailureTests: XCTestCase {

    private func makeDummyDevice() -> DiscoveredDevice {
        DiscoveredDevice(
            id: "mock",
            name: "MockApp#test",
            endpoint: NWEndpoint.hostPort(host: .ipv6(.loopback), port: 1)
        )
    }

    private func encode(_ message: ServerMessage) -> Data {
        // swiftlint:disable:next force_try
        try! JSONEncoder().encode(ResponseEnvelope(message: message))
    }

    // MARK: - Tests

    @ButtonHeistActor
    func testAuthFailedCallbackFires() {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "wrong-token")
        conn.isConnected = true

        var authFailedReason: String?
        conn.onAuthFailed = { reason in
            authFailedReason = reason
        }

        conn.handleMessage(encode(.authFailed("Invalid token. Retry without a token to request a fresh session.")))

        XCTAssertNotNil(authFailedReason)
        XCTAssertTrue(authFailedReason!.contains("Invalid token"))
    }

    @ButtonHeistActor
    func testAuthFailedFiresBeforeDisconnected() {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "wrong-token")
        conn.isConnected = true

        let callOrder = CallOrder()
        conn.onAuthFailed = { _ in
            callOrder.append("authFailed")
        }
        conn.onDisconnected = { _ in
            callOrder.append("disconnected")
        }

        conn.handleMessage(encode(.authFailed("Invalid token. Retry without a token to request a fresh session.")))

        XCTAssertEqual(callOrder.first, "authFailed", "authFailed should fire before disconnected")
    }
}
