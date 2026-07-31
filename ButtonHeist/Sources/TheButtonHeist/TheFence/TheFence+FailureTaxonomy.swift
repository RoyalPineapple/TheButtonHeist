import Foundation

import ThePlans
import TheScore

public extension FenceError {
    internal var diagnosticFailure: DiagnosticFailure {
        switch self {
        case .invalidRequest(let message):
            return DiagnosticFailure(message: message, details: FailureDetails(code: .requestInvalid))
        case .heistBuildDiagnostics(let diagnostics):
            return DiagnosticFailure(
                message: diagnostics.renderedBuildDiagnosticMessage,
                details: diagnostics.heistBuildFailureDetails,
                buildDiagnostics: diagnostics
            )
        case .noDeviceFound:
            return DiagnosticFailure(
                message: "No devices found within timeout. Is the app running?",
                details: FailureDetails(code: .discoveryNoDeviceFound)
            )
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            return DiagnosticFailure(
                message: "No device matching '\(filter)'. Available: \(list)",
                details: FailureDetails(code: .discoveryNoMatchingDevice)
            )
        case .ambiguousDeviceTarget(let filter, let matches):
            return DiagnosticFailure(
                message: "Ambiguous device target '\(filter)' (matches: \(matches.joined(separator: ", ")))",
                details: FailureDetails(code: .discoveryAmbiguousDeviceTarget)
            )
        case .connectionTimeout:
            return DiagnosticFailure(
                message: "Connection timed out",
                details: FailureDetails(code: .setupTimeout, hint: HandoffConnectionError.recoveryHint)
            )
        case .connectionFailed(let message):
            return DiagnosticFailure(
                message: "Connection failed: \(message)",
                details: FailureDetails(code: .connectionFailed, hint: HandoffConnectionError.recoveryHint)
            )
        case .connectionFailure(let failure):
            return DiagnosticFailure(message: failure.message, details: failure.details)
        case .sessionLocked(let message):
            return DiagnosticFailure(
                message: "Session locked: \(message)",
                details: FailureDetails(code: .sessionLocked)
            )
        case .authFailed(let message):
            return DiagnosticFailure(
                message: "Auth failed: \(message)",
                details: FailureDetails(code: .authFailed)
            )
        case .notConnected:
            return DiagnosticFailure(
                message: "Not connected to device.",
                details: FailureDetails(code: .connectionNotConnected)
            )
        case .actionTimeout:
            return DiagnosticFailure(
                message: "Command timed out waiting for a response from the app.",
                details: FailureDetails(code: .requestTimeout)
            )
        case .actionFailed(let message):
            return DiagnosticFailure(
                message: "Action failed: \(message)",
                details: FailureDetails(code: .requestActionFailed)
            )
        case .serverError(let serverError):
            return DiagnosticFailure(
                message: "Action failed: \(serverError.message)",
                details: serverError.failureDetails
            )
        }
    }

    var coreMessage: String {
        diagnosticFailure.message
    }

    var failureDetails: FailureDetails {
        diagnosticFailure.details
    }

}

private extension Array where Element == HeistBuildDiagnostic {
    var primaryBuildDiagnostic: HeistBuildDiagnostic? {
        first(where: { $0.kind == .error }) ?? first
    }

    var renderedBuildDiagnosticMessage: String {
        guard !isEmpty else { return "Heist planning failed." }
        return map(\.renderedMessage).joined(separator: "\n")
    }

    var heistBuildFailureDetails: FailureDetails {
        guard let primary = primaryBuildDiagnostic else {
            return FailureDetails(code: .requestInvalid)
        }
        return FailureDetails(
            code: .requestInvalid,
            hint: primary.hint
        )
    }
}
