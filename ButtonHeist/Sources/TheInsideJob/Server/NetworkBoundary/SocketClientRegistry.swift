import Foundation
import Network

enum SocketClientPhase: Equatable, Sendable {
    case connected(SocketSendBuffer)
    case sending(SocketSendBuffer)

    var sendBuffer: SocketSendBuffer {
        switch self {
        case .connected(let buffer), .sending(let buffer):
            return buffer
        }
    }

    func reserving(byteCount: Int) -> Result<SocketClientPhase, SocketSendBuffer.Rejection> {
        var buffer = sendBuffer
        if let rejection = buffer.reserve(byteCount: byteCount) {
            return .failure(rejection)
        }
        return .success(.sending(buffer))
    }

    func completing(byteCount: Int) -> SocketClientPhase {
        var buffer = sendBuffer
        buffer.complete(byteCount: byteCount)
        return buffer.pendingBytes > 0 ? .sending(buffer) : .connected(buffer)
    }
}

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
        var phase: SocketClientPhase
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
            phase: .connected(SocketSendBuffer())
        )
        return clientId
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

    func phase(for clientId: Int) -> SocketClientPhase? {
        clients[clientId]?.phase
    }

    mutating func reserveSend(clientId: Int, byteCount: Int) -> SendReservation {
        guard var client = clients[clientId] else { return .missingClient }
        switch client.phase.reserving(byteCount: byteCount) {
        case .success(let phase):
            client.phase = phase
            clients[clientId] = client
            return .accepted(connection: client.connection)
        case .failure(let rejection):
            return .rejected(rejection, client: client)
        }
    }

    @discardableResult
    mutating func completeSend(clientId: Int, byteCount: Int) -> Bool {
        guard var client = clients[clientId] else { return false }
        client.phase = client.phase.completing(byteCount: byteCount)
        clients[clientId] = client
        return true
    }
}
