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
        self = .configured(explicitToken ?? SessionTokenGenerator.generate())
    }

    var token: SessionAuthToken {
        switch self {
        case .configured(let token): return token
        }
    }

    var invalidTokenMessage: ServerErrorMessage {
        "Invalid token. Retry with the configured token."
    }

    var configuredTokenRecoveryHint: ServerErrorRecoveryHint {
        "Retry with the configured token."
    }

    func owner(driverId: DriverID?) -> SessionOwner {
        driverId.map(SessionOwner.driver) ?? .token(token)
    }
}
