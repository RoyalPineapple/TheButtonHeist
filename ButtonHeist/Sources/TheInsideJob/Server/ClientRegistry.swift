import Foundation

extension ClientAdmission {
    private enum ClientRegistration {
        case unregistered
        case registered(Authentication.State)
    }

    private struct Client {
        var registration: ClientRegistration
        var rateLimiter: RateLimiter
    }

    enum MessageAdmission: Equatable, Sendable {
        case accepted
        case rateLimited(shouldNotify: Bool)
    }

    /// Auth/admission source of truth owned by `ClientAdmission.Reducer`.
    struct Registry {
    private var clients: [Int: Client] = [:]

    mutating func registerAddress(_ clientId: Int, address: ClientNetworkAddress) {
        let rateLimiter = clients[clientId]?.rateLimiter ?? RateLimiter()
        clients[clientId] = Client(
            registration: .registered(.connected(address: address)),
            rateLimiter: rateLimiter
        )
    }

    mutating func removeAll() {
        clients.removeAll()
    }

    mutating func remove(_ clientId: Int) -> Authentication.State? {
        guard let client = clients.removeValue(forKey: clientId) else { return nil }
        guard case .registered(let state) = client.registration else { return nil }
        return state
    }

    func contains(_ clientId: Int) -> Bool {
        guard let client = clients[clientId] else { return false }
        guard case .registered = client.registration else { return false }
        return true
    }

    func state(for clientId: Int) -> Authentication.State? {
        guard let client = clients[clientId] else { return nil }
        guard case .registered(let state) = client.registration else { return nil }
        return state
    }

    mutating func recordMessage(_ clientId: Int, at now: Date) -> MessageAdmission {
        var client = clients[clientId] ?? Client(
            registration: .unregistered,
            rateLimiter: RateLimiter()
        )
        guard client.rateLimiter.recordMessage(at: now) else {
            clients[clientId] = client
            return .accepted
        }

        let shouldNotify = client.rateLimiter.markNotifiedIfNeeded()
        clients[clientId] = client
        return .rateLimited(shouldNotify: shouldNotify)
    }

    mutating func validateHello(_ clientId: Int) -> Authentication.Transition {
        reduce(.validateHello, for: clientId)
    }

    mutating func completeAuthentication(_ clientId: Int) -> Authentication.Transition {
        reduce(.completeAuthentication, for: clientId)
    }

    private mutating func reduce(
        _ event: Authentication.Event,
        for clientId: Int
    ) -> Authentication.Transition {
        guard let client = clients[clientId] else { return .missingClient }
        guard case .registered(let currentState) = client.registration else { return .missingClient }
        let transition = Authentication.Reducer().reduce(currentState, event: event)

        switch transition {
        case .advanced(let state, effect: _):
            var updatedClient = client
            updatedClient.registration = .registered(state)
            clients[clientId] = updatedClient
        case .rejected:
            break
        case .missingClient:
            preconditionFailure("Authentication reducer cannot lose a registered client.")
        }
        return transition
    }
}
}
