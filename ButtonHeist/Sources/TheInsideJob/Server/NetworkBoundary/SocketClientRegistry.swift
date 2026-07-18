import Foundation
import Network

/// Actor-owned client table for `SimpleSocketServer`.
///
/// The server decides transport policy; this registry owns per-client socket
/// facts: identity allocation and send-buffer accounting.
///
/// **Ownership.** Transport source of truth, owned by `SimpleSocketServer`.
/// Key: `clientId: Int` (this registry allocates it via `nextClientId`).
/// Lifetime: per socket connection. Invalidation: `removeAndCancel(_:)` on close,
/// `cancelAll()` on teardown. It owns `NWConnection` + send-buffer state only — auth
/// state lives in `ClientAdmission.Registry` under the same key, deliberately
/// separate so transport never owns auth semantics. See `docs/ARCHITECTURE.md#state-has-one-owner`.
struct SocketClientRegistry {
    struct Client {
        let connection: NWConnection
        var sendBuffer = SocketSendBuffer()
    }

    enum ConnectionAdmission {
        case registered(clientId: Int)
        case atCapacity
        case ownershipUnavailable
    }

    struct SendReservation: Sendable {
        let clientId: Int
        let connection: NWConnection
        fileprivate let bufferReservation: SocketSendBuffer.Reservation

        var byteCount: Int { bufferReservation.byteCount }
    }

    enum SendAdmission {
        case accepted(SendReservation)
        case rejected(SocketSendBuffer.Rejection, client: Client)
        case missingClient
    }

    enum SendCompletion: Equatable, Sendable {
        case completed
        case clientDisconnected
    }

    private(set) var clients: [Int: Client] = [:]
    private var nextClientId = 0

    var count: Int { clients.count }

    mutating func admitConnection(
        _ connection: NWConnection,
        capacity: Int,
        transferOwnership: () -> Bool
    ) -> ConnectionAdmission {
        guard clients.count < capacity else { return .atCapacity }
        guard transferOwnership() else { return .ownershipUnavailable }

        nextClientId += 1
        let clientId = nextClientId
        clients[clientId] = Client(connection: connection)
        return .registered(clientId: clientId)
    }

    @discardableResult
    mutating func removeAndCancel(_ clientId: Int) -> Bool {
        guard let client = clients.removeValue(forKey: clientId) else { return false }
        client.connection.cancel()
        return true
    }

    mutating func cancelAll() {
        let connectedClients = Array(clients.values)
        clients.removeAll()
        connectedClients.forEach { $0.connection.cancel() }
    }

    func client(_ clientId: Int) -> Client? {
        clients[clientId]
    }

    func pendingSendBytes(for clientId: Int) -> Int? {
        clients[clientId]?.sendBuffer.pendingBytes
    }

    mutating func reserveSend(clientId: Int, byteCount: Int) -> SendAdmission {
        guard var client = clients[clientId] else { return .missingClient }
        switch client.sendBuffer.reserve(byteCount: byteCount) {
        case .success(let bufferReservation):
            clients[clientId] = client
            return .accepted(SendReservation(
                clientId: clientId,
                connection: client.connection,
                bufferReservation: bufferReservation
            ))
        case .failure(let rejection):
            return .rejected(rejection, client: client)
        }
    }

    mutating func completeSend(_ reservation: SendReservation) -> SendCompletion {
        guard var client = clients[reservation.clientId],
              client.connection === reservation.connection
        else {
            return .clientDisconnected
        }
        precondition(
            client.sendBuffer.complete(reservation.bufferReservation),
            "A send reservation may be completed exactly once"
        )
        clients[reservation.clientId] = client
        return .completed
    }
}
