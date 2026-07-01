import Foundation

import ButtonHeistSupport

/// Actor-owned client table for `TheMuscle`.
///
/// **Ownership.** Auth/admission source of truth, owned by `TheMuscleAdmission`.
/// Key: `clientId: Int` (allocated by the transport). Tracks each client's
/// `ClientAuthenticationState` phase. Lifetime: per connected client, from
/// connect to disconnect. Invalidation: `remove(_:)` on disconnect, `removeAll()`
/// on teardown. This is the admission security boundary — it is not the
/// transport's `SocketClientRegistry` (which owns socket facts under the same
/// key) and must stay separate per the no-auth-in-transport rule. See
/// `docs/ARCHITECTURE.md#state-has-one-owner`.
struct TheMuscleClientRegistry {
    private var clients: [Int: StateDriver<ClientAuthenticationMachine>] = [:]

    mutating func registerAddress(_ clientId: Int, address: String) {
        clients[clientId] = StateDriver(
            initial: .connected(address: address),
            machine: ClientAuthenticationMachine()
        )
    }

    mutating func removeAll() {
        clients.removeAll()
    }

    mutating func remove(_ clientId: Int) -> ClientAuthenticationState? {
        clients.removeValue(forKey: clientId)?.state
    }

    func contains(_ clientId: Int) -> Bool {
        clients[clientId] != nil
    }

    func phase(for clientId: Int) -> ClientAuthenticationState? {
        clients[clientId]?.state
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
        guard var driver = clients[clientId] else { return .missingClient }
        let change = driver.send(event)
        clients[clientId] = driver

        switch change {
        case .changed(let state, _):
            guard let effect = change.singleEffect else {
                preconditionFailure("ClientAuthenticationMachine must emit exactly one effect.")
            }
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
