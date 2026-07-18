import XCTest
import Network
@testable import TheInsideJob

final class SocketClientRegistryTests: XCTestCase {
    func testConnectionAdmissionTransfersOwnershipAndRegistersClientAtomically() throws {
        var registry = SocketClientRegistry()
        let connection = makeConnection()
        var didTransferOwnership = false

        let clientId = try XCTUnwrap(registeredClientId(from: registry.admitConnection(
            connection,
            capacity: 1,
            transferOwnership: {
                didTransferOwnership = true
                return true
            }
        )))

        XCTAssertTrue(didTransferOwnership)
        XCTAssertEqual(clientId, 1)
        XCTAssertEqual(registry.count, 1)
        XCTAssertTrue(registry.client(clientId)?.connection === connection)
    }

    func testConnectionAdmissionDoesNotTransferOwnershipWhenAtCapacity() throws {
        var registry = SocketClientRegistry()
        _ = try XCTUnwrap(registeredClientId(from: registry.admitConnection(
            makeConnection(),
            capacity: 1,
            transferOwnership: { true }
        )))
        var didTransferOwnership = false

        let admission = registry.admitConnection(
            makeConnection(),
            capacity: 1,
            transferOwnership: {
                didTransferOwnership = true
                return true
            }
        )

        guard case .atCapacity = admission else {
            return XCTFail("Expected capacity rejection")
        }
        XCTAssertFalse(didTransferOwnership)
        XCTAssertEqual(registry.count, 1)
    }

    func testConnectionAdmissionDoesNotRegisterWithoutOwnership() {
        var registry = SocketClientRegistry()

        let admission = registry.admitConnection(
            makeConnection(),
            capacity: 1,
            transferOwnership: { false }
        )

        guard case .ownershipUnavailable = admission else {
            return XCTFail("Expected ownership rejection")
        }
        XCTAssertEqual(registry.count, 0)
    }

    func testRegistryOwnsSendReservationProof() throws {
        var registry = SocketClientRegistry()
        let connection = makeConnection()
        let clientId = try registeredClient(in: &registry, connection: connection)

        guard case .accepted(let reservation) = registry.reserveSend(clientId: clientId, byteCount: 10) else {
            return XCTFail("Expected accepted send reservation")
        }

        XCTAssertEqual(reservation.clientId, clientId)
        XCTAssertTrue(reservation.connection === connection)
        XCTAssertEqual(reservation.byteCount, 10)
        XCTAssertEqual(registry.pendingSendBytes(for: clientId), 10)
        XCTAssertEqual(registry.completeSend(reservation), .completed)
        XCTAssertEqual(registry.pendingSendBytes(for: clientId), 0)

        guard case .rejected(.payloadTooLarge(let byteCount, let maxBytes)) =
            registry.reserveSend(clientId: clientId, byteCount: SocketSendBuffer.defaultMaxPendingBytes + 1)
        else {
            return XCTFail("Expected payloadTooLarge rejection")
        }
        XCTAssertEqual(byteCount, SocketSendBuffer.defaultMaxPendingBytes + 1)
        XCTAssertEqual(maxBytes, SocketSendBuffer.defaultMaxPendingBytes)
    }

    func testRegistryAccumulatesConcurrentReservationProofs() throws {
        var registry = SocketClientRegistry()
        let clientId = try registeredClient(in: &registry)

        guard case .accepted(let first) = registry.reserveSend(clientId: clientId, byteCount: 10),
              case .accepted(let second) = registry.reserveSend(clientId: clientId, byteCount: 20)
        else {
            return XCTFail("Expected accepted send reservations")
        }

        XCTAssertEqual(registry.pendingSendBytes(for: clientId), 30)
        XCTAssertEqual(registry.completeSend(second), .completed)
        XCTAssertEqual(registry.pendingSendBytes(for: clientId), 10)
        XCTAssertEqual(registry.completeSend(first), .completed)
        XCTAssertEqual(registry.pendingSendBytes(for: clientId), 0)
    }

    func testCompleteSendReportsDisconnectedClient() throws {
        var registry = SocketClientRegistry()
        let clientId = try registeredClient(in: &registry)

        guard case .accepted(let reservation) = registry.reserveSend(clientId: clientId, byteCount: 10) else {
            return XCTFail("Expected accepted send reservation")
        }
        XCTAssertTrue(registry.removeAndCancel(clientId))

        XCTAssertEqual(registry.completeSend(reservation), .clientDisconnected)
        XCTAssertNil(registry.pendingSendBytes(for: clientId))
    }

    func testRemoveAndCancelIsTotalForRegisteredAndMissingClients() throws {
        var registry = SocketClientRegistry()
        let clientId = try registeredClient(in: &registry)

        XCTAssertTrue(registry.removeAndCancel(clientId))
        XCTAssertFalse(registry.removeAndCancel(clientId))
        XCTAssertEqual(registry.count, 0)
    }

    func testCancelAllClearsEveryOwnedSocket() throws {
        var registry = SocketClientRegistry()
        _ = try registeredClient(in: &registry)
        _ = try registeredClient(in: &registry)

        registry.cancelAll()

        XCTAssertEqual(registry.count, 0)
    }

    private func registeredClient(
        in registry: inout SocketClientRegistry,
        connection: NWConnection? = nil
    ) throws -> Int {
        let admission = registry.admitConnection(
            connection ?? makeConnection(),
            capacity: .max,
            transferOwnership: { true }
        )
        return try XCTUnwrap(registeredClientId(from: admission))
    }

    private func registeredClientId(
        from admission: SocketClientRegistry.ConnectionAdmission
    ) -> Int? {
        guard case .registered(let clientId) = admission else { return nil }
        return clientId
    }

    private func makeConnection() -> NWConnection {
        NWConnection(
            host: .ipv6(.loopback),
            port: NWEndpoint.Port(rawValue: 9)!,
            using: .tcp
        )
    }
}
