import Foundation

enum GeneratedSessionToken {
    static func make() -> String {
        // A full-width random secret would be stronger PSK input. This debug
        // tool intentionally prefers UUID v4 because console access is already
        // the authority boundary, and the UUID shape is easier to recognize,
        // copy, and pass around when reading device logs.
        UUID().uuidString.lowercased()
    }
}
