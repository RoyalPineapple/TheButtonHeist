import Foundation
import Network

/// Actor-owned client table for `SimpleSocketServer`.
///
/// The server decides transport policy; this registry owns per-client mutable
/// facts: identity allocation, authentication phase, send-buffer accounting,
/// and rate-limit windows.
struct SocketClientRegistry {
    struct Client {
        let connection: NWConnection
        var authentication: SocketClientAuthentication
        var rateLimiter: SocketRateLimiter
        var sendBuffer: SocketSendBuffer
    }

    enum InboundMessageDecision: Equatable, Sendable {
        case accepted(authenticated: Bool)
        case rateLimited(authenticated: Bool, shouldNotify: Bool)
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

    mutating func insert(
        connection: NWConnection,
        authentication: SocketClientAuthentication
    ) -> Int {
        insert(connection: connection) { _ in authentication }
    }

    mutating func insert(
        connection: NWConnection,
        makeAuthentication: (Int) -> SocketClientAuthentication
    ) -> Int {
        nextClientId += 1
        let clientId = nextClientId
        clients[nextClientId] = Client(
            connection: connection,
            authentication: makeAuthentication(clientId),
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

    func authentication(for clientId: Int) -> SocketClientAuthentication? {
        clients[clientId]?.authentication
    }

    @discardableResult
    mutating func markAuthenticated(_ clientId: Int) -> Bool {
        guard var client = clients[clientId],
              client.authentication.markAuthenticated() else { return false }
        clients[clientId] = client
        return true
    }

    @discardableResult
    mutating func markApprovalPending(_ clientId: Int) -> Bool {
        guard var client = clients[clientId],
              client.authentication.markApprovalPending() else { return false }
        clients[clientId] = client
        return true
    }

    func isAuthenticated(_ clientId: Int) -> Bool {
        clients[clientId]?.authentication.isAuthenticated == true
    }

    var authenticatedClientIds: [Int] {
        clients.compactMap { clientId, client in
            client.authentication.isAuthenticated ? clientId : nil
        }
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
        let authenticated = client.authentication.isAuthenticated
        if client.rateLimiter.recordMessage(at: now) {
            let shouldNotify = client.rateLimiter.markNotifiedIfNeeded()
            clients[clientId] = client
            return .rateLimited(authenticated: authenticated, shouldNotify: shouldNotify)
        }
        clients[clientId] = client
        return .accepted(authenticated: authenticated)
    }
}
