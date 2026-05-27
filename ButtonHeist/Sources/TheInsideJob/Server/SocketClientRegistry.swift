import Foundation
import Network

/// Actor-owned client table for `SimpleSocketServer`.
///
/// The server decides transport policy; this registry owns per-client mutable
/// facts: identity allocation, send-buffer accounting, and rate-limit windows.
struct SocketClientRegistry {
    struct Client {
        let connection: NWConnection
        var rateLimiter: SocketRateLimiter
        var sendBuffer: SocketSendBuffer
    }

    enum InboundMessageDecision: Equatable, Sendable {
        case accepted
        case rateLimited(shouldNotify: Bool)
        case missingClient
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
            rateLimiter: SocketRateLimiter(),
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

    mutating func recordInboundMessage(clientId: Int, at now: Date = Date()) -> InboundMessageDecision {
        guard var client = clients[clientId] else { return .missingClient }
        if client.rateLimiter.recordMessage(at: now) {
            let shouldNotify = client.rateLimiter.markNotifiedIfNeeded()
            clients[clientId] = client
            return .rateLimited(shouldNotify: shouldNotify)
        }
        clients[clientId] = client
        return .accepted
    }
}
