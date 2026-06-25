import Foundation

/// Source of truth for session token lifecycle and token-derived auth behavior.
enum SessionTokenSource: Sendable {
    case configured(String)

    init(explicitToken: String?) {
        self = .configured(explicitToken ?? GeneratedSessionToken.make())
    }

    var token: String {
        switch self {
        case .configured(let token): return token
        }
    }

    var invalidTokenMessage: String {
        "Invalid token. \(configuredTokenRecoveryHint)"
    }

    var emptyTokenMessage: String {
        "Token is required. \(configuredTokenRecoveryHint)"
    }

    var configuredTokenRecoveryHint: String {
        "Retry with the configured token."
    }

    func effectiveDriverId(driverId: String?) -> String {
        if let driverId, !driverId.isEmpty {
            return "driver:\(driverId)"
        }
        return "token:\(token)"
    }
}
