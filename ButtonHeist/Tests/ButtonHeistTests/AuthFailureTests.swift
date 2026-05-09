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
/// Validates that the auth-failure error fires correctly and isn't swallowed by the subsequent disconnect.
final class AuthFailureTests: XCTestCase {

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
    func testAuthFailedCallbackFires() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "wrong-token")
        conn.simulateConnected()

        var authFailedReason: String?
        conn.onEvent = { event in
            if case .message(.error(let serverError), _, _) = event,
               serverError.kind == .authFailure {
                authFailedReason = serverError.message
            }
        }

        try conn.handleMessage(encode(
            .error(ServerError(kind: .authFailure, message: "Invalid token. Retry without a token to request a fresh session."))
        ))

        XCTAssertNotNil(authFailedReason)
        XCTAssertTrue(authFailedReason!.contains("Invalid token"))
    }

    @ButtonHeistActor
    func testAuthFailedFiresBeforeDisconnected() async throws {
        let conn = DeviceConnection(device: makeDummyDevice(), token: "wrong-token")
        conn.simulateConnected()

        let callOrder = CallOrder()
        conn.onEvent = { event in
            switch event {
            case .message(.error(let serverError), _, _) where serverError.kind == .authFailure:
                callOrder.append("authFailed")
            case .disconnected:
                callOrder.append("disconnected")
            default:
                break
            }
        }

        try conn.handleMessage(encode(
            .error(ServerError(kind: .authFailure, message: "Invalid token. Retry without a token to request a fresh session."))
        ))

        XCTAssertEqual(callOrder.first, "authFailed", "authFailed should fire before disconnected")
    }
}
