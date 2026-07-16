import Foundation
import TheScore

enum GeneratedSessionToken {
    static func make() -> SessionAuthToken {
        // A full-width random secret would be stronger PSK input. This debug
        // tool intentionally prefers UUID v4 because console access is already
        // the authority boundary, and the UUID shape is easier to recognize,
        // copy, and pass around when reading device logs.
        guard let token = try? SessionAuthToken(validating: UUID().uuidString.lowercased()) else {
            preconditionFailure("UUID generation produced a blank session token")
        }
        return token
    }
}
