import Foundation

import ButtonHeistSupport

/// Per-client authentication lifecycle owned by `TheMuscle`.
///
/// This is the single typed phase enum for the ButtonHeist auth flow:
/// connected -> helloValidated -> authenticated.
enum ClientAuthenticationState: Equatable, Sendable {
    case connected(address: String)
    case helloValidated(address: String)
    case authenticated(address: String)

    var address: String {
        switch self {
        case .connected(let address),
             .helloValidated(let address),
             .authenticated(let address):
            return address
        }
    }

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }

    var hasCompletedHello: Bool {
        if case .connected = self { return false }
        return true
    }
}

struct ClientAuthenticationMachine: SimpleStateMachine, Equatable {
    enum Event: Equatable, Sendable {
        case validateHello
        case completeAuthentication
    }

    enum Effect: Equatable, Sendable {
        case helloValidated
        case authenticated
    }

    enum Rejection: Equatable, Sendable {
        case missingHello
        case helloAlreadyValidated
        case alreadyAuthenticated
    }

    func advance(
        _ state: ClientAuthenticationState,
        with event: Event
    ) -> StateChange<ClientAuthenticationState, Effect, Rejection> {
        switch (state, event) {
        case (.connected(let address), .validateHello):
            return .changed(to: .helloValidated(address: address), effects: [.helloValidated])

        case (.helloValidated(let address), .completeAuthentication):
            return .changed(to: .authenticated(address: address), effects: [.authenticated])

        case (.connected, .completeAuthentication):
            return .rejected(.missingHello, stayingIn: state)

        case (.helloValidated, .validateHello):
            return .rejected(.helloAlreadyValidated, stayingIn: state)

        case (.authenticated, .validateHello),
             (.authenticated, .completeAuthentication):
            return .rejected(.alreadyAuthenticated, stayingIn: state)
        }
    }
}
