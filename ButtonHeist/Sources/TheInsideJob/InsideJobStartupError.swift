#if canImport(UIKit)
#if DEBUG
import Foundation

enum InsideJobStartupError: Error, LocalizedError, Equatable, Sendable {
    case tlsIdentityUnavailable(phase: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .tlsIdentityUnavailable(let phase, let reason):
            return "TLS identity unavailable during \(phase); listener was not started and Bonjour was not published. \(reason)"
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
