import Foundation

/// Per-client authentication lifecycle owned by `TheMuscle`.
///
/// This is the single typed phase enum for the ButtonHeist auth flow:
/// connected -> helloValidated -> authenticated.
enum ClientAuthenticationState: Sendable {
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
