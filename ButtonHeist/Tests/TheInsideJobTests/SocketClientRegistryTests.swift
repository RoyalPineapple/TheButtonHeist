import XCTest
import Network
@testable import TheInsideJob

final class SocketClientRegistryTests: XCTestCase {
    func testRegistryOwnsClientIdentity() {
        var registry = SocketClientRegistry()

        let clientId = registry.insert(connection: makeConnection())

        XCTAssertEqual(clientId, 1)
        XCTAssertEqual(registry.count, 1)
        XCTAssertNotNil(registry.client(clientId))
    }

    func testRegistryOwnsSendBufferReservation() {
        var registry = SocketClientRegistry()
        let clientId = registry.insert(connection: makeConnection())

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

    func testRegistryExposesTypedClientSendPhases() {
        var registry = SocketClientRegistry()
        let clientId = registry.insert(connection: makeConnection())

        XCTAssertEqual(registry.phase(for: clientId), .connected(SocketSendBuffer()))

        guard case .accepted = registry.reserveSend(clientId: clientId, byteCount: 10) else {
            return XCTFail("Expected accepted send reservation")
        }
        XCTAssertEqual(
            registry.phase(for: clientId),
            .sending(SocketSendBuffer(pendingBytes: 10))
        )

        XCTAssertTrue(registry.completeSend(clientId: clientId, byteCount: 10))
        XCTAssertEqual(registry.phase(for: clientId), .connected(SocketSendBuffer()))
    }

    func testCompleteSendReportsMissingClientAfterDisconnect() {
        var registry = SocketClientRegistry()
        let clientId = registry.insert(connection: makeConnection())

        guard case .accepted = registry.reserveSend(clientId: clientId, byteCount: 10) else {
            return XCTFail("Expected accepted send reservation")
        }
        _ = registry.remove(clientId)

        XCTAssertFalse(registry.completeSend(clientId: clientId, byteCount: 10))
        XCTAssertNil(registry.phase(for: clientId))
    }

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: .tcp
        )
    }
}
