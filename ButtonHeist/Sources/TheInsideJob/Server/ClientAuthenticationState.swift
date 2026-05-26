import Foundation

/// Per-client authentication lifecycle owned by `TheMuscle`.
///
/// This is the single typed phase enum for the ButtonHeist auth flow:
/// connected -> helloValidated -> pendingApproval | authenticated.
enum ClientAuthenticationState: Sendable {
    typealias ResponseHandler = @Sendable (Data) -> Void

    case connected(address: String)
    case helloValidated(address: String)
    case pendingApproval(address: String, respond: ResponseHandler, driverId: String?)
    case authenticated(address: String, driverIdentity: String)

    var address: String {
        switch self {
        case .connected(let address),
             .helloValidated(let address),
             .pendingApproval(let address, _, _),
             .authenticated(let address, _):
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

    var driverIdentity: String? {
        if case .authenticated(_, let identity) = self { return identity }
        return nil
    }
}
