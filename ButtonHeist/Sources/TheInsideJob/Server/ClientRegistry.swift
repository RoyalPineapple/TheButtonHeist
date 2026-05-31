import Foundation

/// Actor-owned client table for `TheMuscle`.
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
