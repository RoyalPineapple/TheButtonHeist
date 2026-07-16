import Foundation
import TheScore

enum SessionOwner: Equatable, Sendable {
    case driver(DriverID)
    case token(SessionAuthToken)
}

/// Source of truth for session token lifecycle and token-derived auth behavior.
enum SessionTokenSource: Sendable {
    case configured(SessionAuthToken)

    init(explicitToken: SessionAuthToken?) {
        self = .configured(explicitToken ?? GeneratedSessionToken.make())
    }

    var token: SessionAuthToken {
        switch self {
        case .configured(let token): return token
        }
    }

    var invalidTokenMessage: String {
        "Invalid token. \(configuredTokenRecoveryHint)"
    }

    var configuredTokenRecoveryHint: String {
        "Retry with the configured token."
    }

    func owner(driverId: DriverID?) -> SessionOwner {
        driverId.map(SessionOwner.driver) ?? .token(token)
    }
}
