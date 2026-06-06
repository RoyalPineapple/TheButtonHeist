import Foundation

/// Actor-owned client table for `TheMuscle`.
///
/// **Ownership.** Auth/admission source of truth, owned by `TheMuscleAdmission`.
/// Key: `clientId: Int` (allocated by the transport). Tracks each client's
/// `ClientAuthenticationState` phase. Lifetime: per connected client, from
/// connect to disconnect. Invalidation: `remove(_:)` on disconnect, `removeAll()`
/// on teardown. This is the admission security boundary — it is not the
/// transport's `SocketClientRegistry` (which owns socket facts under the same
/// key) and must stay separate per the no-auth-in-transport rule. See
/// `docs/DATA-OWNERSHIP.md`.
struct TheMuscleClientRegistry {
    private var clients: [Int: ClientAuthenticationState] = [:]

    var hasPendingApproval: Bool {
        clients.values.contains { phase in
            if case .pendingApproval = phase { return true }
            return false
        }
    }

    mutating func registerAddress(_ clientId: Int, address: String) {
        clients[clientId] = .connected(address: address)
    }

    mutating func removeAll() {
        clients.removeAll()
    }

    mutating func remove(_ clientId: Int) -> ClientAuthenticationState? {
        clients.removeValue(forKey: clientId)
    }

    func contains(_ clientId: Int) -> Bool {
        clients[clientId] != nil
    }

    func phase(for clientId: Int) -> ClientAuthenticationState? {
        clients[clientId]
    }

    mutating func markHelloValidated(_ clientId: Int) -> ClientAuthenticationState? {
        guard let phase = clients[clientId] else { return nil }
        clients[clientId] = .helloValidated(address: phase.address)
        return phase
    }

    mutating func beginApproval(
        _ clientId: Int,
        address: String,
        respond: @escaping ClientAuthenticationState.ResponseHandler,
        driverId: String?
    ) {
        clients[clientId] = .pendingApproval(address: address, respond: respond, driverId: driverId)
    }

    mutating func authenticate(_ clientId: Int, address: String) {
        clients[clientId] = .authenticated(address: address)
    }

    mutating func restoreHelloValidated(_ clientId: Int, address: String) {
        clients[clientId] = .helloValidated(address: address)
    }
}
