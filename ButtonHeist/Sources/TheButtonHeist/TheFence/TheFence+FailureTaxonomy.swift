import Foundation

import ThePlans
import TheScore

struct FenceFailureDescriptor: Sendable {
    let details: FailureDetails
    let coreMessage: String

    var errorCode: String { details.errorCode }
    var phase: FailurePhase { details.phase }
    var retryable: Bool { details.retryable }
    var hint: String? { details.hint }
}

public extension FenceError {
    internal var failureDescriptor: FenceFailureDescriptor {
        switch self {
        case .invalidRequest(let message):
            return FenceFailureDescriptor(
                details: FailureDetails(code: .requestInvalid),
                coreMessage: message
            )
        case .heistBuildDiagnostics(let diagnostics):
            let message = diagnostics.renderedBuildDiagnosticMessage
            return FenceFailureDescriptor(
                details: diagnostics.heistBuildFailureDetails,
                coreMessage: message
            )
        case .noDeviceFound:
            let message = "No devices found within timeout. Is the app running?"
            return FenceFailureDescriptor(
                details: FailureDetails(code: .discoveryNoDeviceFound),
                coreMessage: message
            )
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            let message = "No device matching '\(filter)'. Available: \(list)"
            return FenceFailureDescriptor(
                details: FailureDetails(code: .discoveryNoMatchingDevice),
                coreMessage: message
            )
        case .ambiguousDeviceTarget(let filter, let matches):
            let list = matches.joined(separator: ", ")
            let message = "Ambiguous device target '\(filter)' (matches: \(list))"
            return FenceFailureDescriptor(
                details: FailureDetails(code: .discoveryAmbiguousDeviceTarget),
                coreMessage: message
            )
        case .connectionTimeout:
            let hint = "Is the app running? Check 'buttonheist list_devices' to see available devices."
            return FenceFailureDescriptor(
                details: FailureDetails(code: .setupTimeout, hint: hint),
                coreMessage: "Connection timed out"
            )
        case .connectionFailed(let message):
            let hint = "Is the app running? Check 'buttonheist list_devices' to see available devices."
            return FenceFailureDescriptor(
                details: FailureDetails(code: .connectionFailed, hint: hint),
                coreMessage: "Connection failed: \(message)"
            )
        case .connectionFailure(let failure):
            return FenceFailureDescriptor(
                details: FailureDetails(code: failure.failureCode, hint: failure.hint),
                coreMessage: failure.message
            )
        case .sessionLocked(let message):
            return FenceFailureDescriptor(
                details: FailureDetails(code: .sessionLocked),
                coreMessage: "Session locked: \(message)"
            )
        case .authFailed(let message):
            let base = "Auth failed: \(message)"
            return FenceFailureDescriptor(
                details: FailureDetails(code: .authFailed),
                coreMessage: base
            )
        case .notConnected:
            return FenceFailureDescriptor(
                details: FailureDetails(code: .connectionNotConnected),
                coreMessage: "Not connected to device."
            )
        case .actionTimeout:
            return FenceFailureDescriptor(
                details: FailureDetails(code: .requestTimeout),
                coreMessage: "Command timed out waiting for a response from the app."
            )
        case .actionFailed(let message):
            let displayMessage = "Action failed: \(message)"
            return FenceFailureDescriptor(
                details: FailureDetails(code: .requestActionFailed),
                coreMessage: displayMessage
            )
        case .serverError(let serverError):
            let displayMessage = "Action failed: \(serverError.message)"
            return FenceFailureDescriptor(
                details: serverError.failureDetails,
                coreMessage: displayMessage
            )
        }
    }

    var errorCode: String {
        failureDescriptor.errorCode
    }

    var phase: FailurePhase {
        failureDescriptor.phase
    }

    var retryable: Bool {
        failureDescriptor.retryable
    }

    var hint: String? {
        failureDescriptor.hint
    }

    internal var buildDiagnostics: [HeistBuildDiagnostic] {
        guard case .heistBuildDiagnostics(let diagnostics) = self else { return [] }
        return diagnostics
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
