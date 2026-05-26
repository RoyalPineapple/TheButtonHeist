import Foundation

/// Source of truth for session token lifecycle and token-derived auth behavior.
enum SessionTokenSource: Sendable {
    case configured(String)
    case generated(String)

    init(explicitToken: String?) {
        if let explicitToken {
            self = .configured(explicitToken)
        } else {
            self = .generated(UUID().uuidString)
        }
    }

    var token: String {
        switch self {
        case .configured(let token), .generated(let token): return token
        }
    }

    var uiApprovalPayload: String? {
        switch self {
        case .configured: return nil
        case .generated(let token): return token
        }
    }

    var allowsUIApproval: Bool {
        uiApprovalPayload != nil
    }

    var invalidTokenMessage: String {
        switch self {
        case .configured:
            return "Invalid token. Retry with the configured token."
        case .generated:
            return "Invalid token. Retry without a token to request a fresh session."
        }
    }

    func effectiveDriverId(driverId: String?) -> String {
        if let driverId, !driverId.isEmpty {
            return "driver:\(driverId)"
        }
        return "token:\(token)"
    }
}
