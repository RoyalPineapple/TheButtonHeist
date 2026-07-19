import Foundation

extension ClientAdmission {
    struct SessionAdmission: Sendable {
        let clientId: Int
        let owner: SessionOwner
        let respond: ResponseHandler
    }
}

extension ClientAdmission.Authentication {
    /// Per-client authentication lifecycle owned by `ClientAdmission.Reducer`.
    enum State: Equatable, Sendable {
        case connected(address: ClientNetworkAddress)
        case helloValidated(address: ClientNetworkAddress)
        case authenticated(address: ClientNetworkAddress)

        var address: ClientNetworkAddress {
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

    enum Event: Equatable, Sendable {
        case helloValidationRequested
        case authenticationCompletionRequested
    }

    enum Outcome: Equatable, Sendable {
        case helloValidated
        case authenticated
    }

    enum Rejection: Equatable, Sendable {
        case missingHello
        case helloAlreadyValidated
        case alreadyAuthenticated
    }

    enum Transition: Equatable, Sendable {
        case advanced(State, outcome: Outcome)
        case rejected(Rejection, state: State)
        case missingClient
    }

    struct Reducer: Equatable {
        func reduce(_ state: State, event: Event) -> Transition {
            switch (state, event) {
            case (.connected(let address), .helloValidationRequested):
                return .advanced(.helloValidated(address: address), outcome: .helloValidated)

            case (.helloValidated(let address), .authenticationCompletionRequested):
                return .advanced(.authenticated(address: address), outcome: .authenticated)

            case (.connected, .authenticationCompletionRequested):
                return .rejected(.missingHello, state: state)

            case (.helloValidated, .helloValidationRequested):
                return .rejected(.helloAlreadyValidated, state: state)

            case (.authenticated, .helloValidationRequested),
                 (.authenticated, .authenticationCompletionRequested):
                return .rejected(.alreadyAuthenticated, state: state)
            }
        }
    }
}
