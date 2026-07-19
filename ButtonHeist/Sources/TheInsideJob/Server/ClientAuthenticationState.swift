import Foundation

extension ClientAdmission.Authentication {
    struct Proof {
        let clientId: Int
        let address: ClientNetworkAddress
        let owner: SessionOwner
        let respond: ClientAdmission.ResponseHandler
        let source: Source
    }

    enum Source {
        case token
    }

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

    enum Transition: Equatable, Sendable {
        case advanced(State, effect: Effect)
        case rejected(Rejection, state: State)
        case missingClient
    }

    struct Reducer: Equatable {
        func reduce(_ state: State, event: Event) -> Transition {
            switch (state, event) {
            case (.connected(let address), .validateHello):
                return .advanced(.helloValidated(address: address), effect: .helloValidated)

            case (.helloValidated(let address), .completeAuthentication):
                return .advanced(.authenticated(address: address), effect: .authenticated)

            case (.connected, .completeAuthentication):
                return .rejected(.missingHello, state: state)

            case (.helloValidated, .validateHello):
                return .rejected(.helloAlreadyValidated, state: state)

            case (.authenticated, .validateHello),
                 (.authenticated, .completeAuthentication):
                return .rejected(.alreadyAuthenticated, state: state)
            }
        }
    }
}
