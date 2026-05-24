import XCTest
import Network
@testable import TheInsideJob

final class SocketClientRegistryTests: XCTestCase {
    private let inertDeadline: @Sendable () -> Task<Void, Never> = {
        Task {}
    }

    func testRegistryOwnsClientIdentityAndAuthentication() {
        var registry = SocketClientRegistry()

        let clientId = registry.insert(
            connection: makeConnection(),
            authentication: .awaitingAuthentication(deadline: inertDeadline())
        )

        XCTAssertEqual(clientId, 1)
        XCTAssertEqual(registry.count, 1)
        XCTAssertFalse(registry.isAuthenticated(clientId))
        XCTAssertTrue(registry.markApprovalPending(clientId))
        XCTAssertEqual(registry.authentication(for: clientId), .awaitingApproval(deadline: inertDeadline()))
        XCTAssertTrue(registry.markAuthenticated(clientId))
        XCTAssertTrue(registry.isAuthenticated(clientId))
        XCTAssertEqual(registry.authenticatedClientIds, [clientId])
    }

    func testRegistryOwnsSendBufferReservation() {
        var registry = SocketClientRegistry()
        let clientId = registry.insert(
            connection: makeConnection(),
            authentication: .awaitingAuthentication(deadline: inertDeadline())
        )

        guard case .accepted = registry.reserveSend(clientId: clientId, byteCount: 10) else {
            return XCTFail("Expected accepted send reservation")
        }
        registry.completeSend(clientId: clientId, byteCount: 10)

        guard case .rejected(.payloadTooLarge(let byteCount, let maxBytes), _) =
            registry.reserveSend(clientId: clientId, byteCount: SocketSendBuffer.defaultMaxPendingBytes + 1)
        else {
            return XCTFail("Expected payloadTooLarge rejection")
        }
        XCTAssertEqual(byteCount, SocketSendBuffer.defaultMaxPendingBytes + 1)
        XCTAssertEqual(maxBytes, SocketSendBuffer.defaultMaxPendingBytes)
    }

    func testRegistryOwnsRateLimitWindowAndNotification() {
        var registry = SocketClientRegistry()
        let clientId = registry.insert(
            connection: makeConnection(),
            authentication: .awaitingAuthentication(deadline: inertDeadline())
        )
        let now = Date()

        for _ in 0..<SocketRateLimiter.defaultMaxMessagesPerSecond {
            XCTAssertEqual(
                registry.recordInboundMessage(clientId: clientId, at: now),
                .accepted(authenticated: false)
            )
        }

        XCTAssertEqual(
            registry.recordInboundMessage(clientId: clientId, at: now),
            .rateLimited(authenticated: false, shouldNotify: true)
        )
        XCTAssertEqual(
            registry.recordInboundMessage(clientId: clientId, at: now),
            .rateLimited(authenticated: false, shouldNotify: false)
        )
        XCTAssertEqual(
            registry.recordInboundMessage(clientId: clientId, at: now.addingTimeInterval(1.1)),
            .accepted(authenticated: false)
        )
    }

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: .tcp
        )
    }
}
