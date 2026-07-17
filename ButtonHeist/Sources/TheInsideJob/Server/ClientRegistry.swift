import Foundation

/// Actor-owned client table for `TheMuscle`.
///
/// **Ownership.** Auth/admission source of truth, owned by `TheMuscleAdmission`.
/// Key: `clientId: Int` (allocated by the transport). Tracks each client's
/// authentication phase and message rate limiter. Lifetime: per connected client, from
/// connect to disconnect. Invalidation: `remove(_:)` on disconnect, `removeAll()`
/// on teardown. This is the admission security boundary — it is not the
/// transport's `SocketClientRegistry` (which owns socket facts under the same
/// key) and must stay separate per the no-auth-in-transport rule. See
/// `docs/ARCHITECTURE.md#state-has-one-owner`.
struct TheMuscleClientRegistry {
    private enum ClientRegistration {
        case unregistered
        case registered(ClientAuthenticationState)
    }

    private struct Client {
        var registration: ClientRegistration
        var rateLimiter: MessageRateLimiter
    }

    enum MessageAdmission: Equatable, Sendable {
        case accepted
        case rateLimited(shouldNotify: Bool)
    }

    private var clients: [Int: Client] = [:]

    mutating func registerAddress(_ clientId: Int, address: String) {
        let rateLimiter = clients[clientId]?.rateLimiter ?? MessageRateLimiter()
        clients[clientId] = Client(
            registration: .registered(.connected(address: address)),
            rateLimiter: rateLimiter
        )
    }

    mutating func removeAll() {
        clients.removeAll()
    }

    mutating func remove(_ clientId: Int) -> ClientAuthenticationState? {
        guard let client = clients.removeValue(forKey: clientId) else { return nil }
        guard case .registered(let state) = client.registration else { return nil }
        return state
    }

    func contains(_ clientId: Int) -> Bool {
        guard let client = clients[clientId] else { return false }
        guard case .registered = client.registration else { return false }
        return true
    }

    func phase(for clientId: Int) -> ClientAuthenticationState? {
        guard let client = clients[clientId] else { return nil }
        guard case .registered(let state) = client.registration else { return nil }
        return state
    }

    mutating func recordMessage(_ clientId: Int, at now: Date) -> MessageAdmission {
        var client = clients[clientId] ?? Client(
            registration: .unregistered,
            rateLimiter: MessageRateLimiter()
        )
        guard client.rateLimiter.recordMessage(at: now) else {
            clients[clientId] = client
            return .accepted
        }

        let shouldNotify = client.rateLimiter.markNotifiedIfNeeded()
        clients[clientId] = client
        return .rateLimited(shouldNotify: shouldNotify)
    }

    mutating func validateHello(_ clientId: Int) -> ClientAuthenticationTransition {
        send(.validateHello, to: clientId)
    }

    mutating func completeAuthentication(_ clientId: Int) -> ClientAuthenticationTransition {
        send(.completeAuthentication, to: clientId)
    }

    private mutating func send(
        _ event: ClientAuthenticationMachine.Event,
        to clientId: Int
    ) -> ClientAuthenticationTransition {
        guard let client = clients[clientId] else { return .missingClient }
        guard case .registered(let currentState) = client.registration else { return .missingClient }
        let transition = ClientAuthenticationMachine().advance(currentState, with: event)

        switch transition {
        case .advanced(let state, let effect):
            var updatedClient = client
            updatedClient.registration = .registered(state)
            clients[clientId] = updatedClient
            return .advanced(state, effect: effect)
        case .rejected(let rejection, let state):
            return .rejected(rejection, state: state)
        }
    }
}

enum ClientAuthenticationTransition: Equatable, Sendable {
    case advanced(ClientAuthenticationState, effect: ClientAuthenticationMachine.Effect)
    case rejected(ClientAuthenticationMachine.Rejection, state: ClientAuthenticationState)
    case missingClient
}
