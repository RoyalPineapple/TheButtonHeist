#if canImport(UIKit)
#if DEBUG
import Foundation

enum InsideJobStartupError: Error, LocalizedError, Equatable, Sendable {
    case tokenRequired(phase: String)

    var errorDescription: String? {
        switch self {
        case .tokenRequired(let phase):
            return """
            InsideJob token required during \(phase); listener was not started and Bonjour was not published. \
            Set INSIDEJOB_TOKEN, InsideJobToken, or call TheInsideJob.configure(token:).
            """
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
