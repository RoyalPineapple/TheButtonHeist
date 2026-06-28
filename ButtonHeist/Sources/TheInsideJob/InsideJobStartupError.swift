#if canImport(UIKit)
#if DEBUG
import Foundation

enum InsideJobStartupError: Error, LocalizedError, Equatable, Sendable {
    case tokenRequired(phase: InsideJobRuntimeStartPhase)

    var errorDescription: String? {
        switch self {
        case .tokenRequired(phase: .startup):
            return """
            InsideJob token required during startup; listener was not started and Bonjour was not published. \
            Set INSIDEJOB_TOKEN, InsideJobToken, or call TheInsideJob.configure(token:).
            """
        case .tokenRequired(phase: .resume):
            return """
            InsideJob token required during resume; listener was not started and Bonjour was not published. \
            Set INSIDEJOB_TOKEN, InsideJobToken, or call TheInsideJob.configure(token:).
            """
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
