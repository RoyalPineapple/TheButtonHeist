import Foundation
import Network

/// Actor-owned client table for `SimpleSocketServer`.
///
/// The server decides transport policy; this registry owns per-client socket
/// facts: identity allocation and send-buffer accounting.
///
/// **Ownership.** Transport source of truth, owned by `SimpleSocketServer`.
/// Key: `clientId: Int` (this registry allocates it via `nextClientId`).
/// Lifetime: per socket connection. Invalidation: `remove(_:)` on close,
/// `drain()` on teardown. It owns `NWConnection` + send-buffer state only — auth
/// phase lives in `TheMuscleClientRegistry` under the same key, deliberately
/// separate so transport never owns auth semantics. See `docs/DATA-OWNERSHIP.md`.
struct SocketClientRegistry {
    struct Client {
        let connection: NWConnection
        var sendBuffer: SocketSendBuffer
    }

    enum SendReservation {
        case accepted(connection: NWConnection)
        case rejected(SocketSendBuffer.Rejection, client: Client)
        case missingClient
    }

    private(set) var clients: [Int: Client] = [:]
    private var nextClientId = 0

    var count: Int { clients.count }

    mutating func insert(connection: NWConnection) -> Int {
        nextClientId += 1
        let clientId = nextClientId
        clients[nextClientId] = Client(
            connection: connection,
            sendBuffer: SocketSendBuffer()
        )
        return clientId
    }

    mutating func drain() -> [Client] {
        let removed = Array(clients.values)
        clients.removeAll()
        return removed
    }

    mutating func remove(_ clientId: Int) -> Client? {
        clients.removeValue(forKey: clientId)
    }

    func client(_ clientId: Int) -> Client? {
        clients[clientId]
    }

    mutating func reserveSend(clientId: Int, byteCount: Int) -> SendReservation {
        guard var client = clients[clientId] else { return .missingClient }
        if let rejection = client.sendBuffer.reserve(byteCount: byteCount) {
            return .rejected(rejection, client: client)
        }
        clients[clientId] = client
        return .accepted(connection: client.connection)
    }

    mutating func completeSend(clientId: Int, byteCount: Int) {
        guard var client = clients[clientId] else { return }
        client.sendBuffer.complete(byteCount: byteCount)
        clients[clientId] = client
    }
}
