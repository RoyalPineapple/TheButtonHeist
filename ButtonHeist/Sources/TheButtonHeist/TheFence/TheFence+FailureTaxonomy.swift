import Foundation

import ThePlans
import TheScore

struct FenceFailureDescriptor: Sendable {
    let details: FailureDetails
    let coreMessage: String
    let displayMessage: String

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
                coreMessage: message,
                displayMessage: message
            )
        case .heistBuildDiagnostics(let diagnostics):
            let message = diagnostics.renderedBuildDiagnosticMessage
            return FenceFailureDescriptor(
                details: diagnostics.heistBuildFailureDetails,
                coreMessage: message,
                displayMessage: message
            )
        case .noDeviceFound:
            let message = "No devices found within timeout. Is the app running?"
            return FenceFailureDescriptor(
                details: FailureDetails(code: .discoveryNoDeviceFound),
                coreMessage: message,
                displayMessage: message
            )
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            let message = "No device matching '\(filter)'. Available: \(list)"
            return FenceFailureDescriptor(
                details: FailureDetails(code: .discoveryNoMatchingDevice),
                coreMessage: message,
                displayMessage: message
            )
        case .connectionTimeout:
            let hint = "Is the app running? Check 'buttonheist list_devices' to see available devices."
            return FenceFailureDescriptor(
                details: FailureDetails(code: .setupTimeout, hint: hint),
                coreMessage: "Connection timed out",
                displayMessage: """
                    Connection timed out
                      Hint: \(hint)
                    """
            )
        case .connectionFailed(let message):
            let hint = "Is the app running? Check 'buttonheist list_devices' to see available devices."
            return FenceFailureDescriptor(
                details: FailureDetails(code: .connectionFailed, hint: hint),
                coreMessage: "Connection failed: \(message)",
                displayMessage: """
                    Connection failed: \(message)
                      Hint: \(hint)
                    """
            )
        case .connectionFailure(let failure):
            return FenceFailureDescriptor(
                details: FailureDetails(
                    code: failure.failureCode,
                    phase: failure.phase,
                    retryable: failure.retryable,
                    hint: failure.hint
                ),
                coreMessage: failure.message,
                displayMessage: failure.message
            )
        case .sessionLocked(let message):
            return FenceFailureDescriptor(
                details: FailureDetails(code: .sessionLocked),
                coreMessage: "Session locked: \(message)",
                displayMessage: """
                    Session locked: \(message)
                      Another driver is currently connected. Wait for it to disconnect
                      or for the session to time out.
                      If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID
                      or restart the app to release it.
                    """
            )
        case .authFailed(let message):
            let base = "Auth failed: \(message)"
            return FenceFailureDescriptor(
                details: FailureDetails(code: .authFailed),
                coreMessage: base,
                displayMessage: base
            )
        case .notConnected:
            return FenceFailureDescriptor(
                details: FailureDetails(code: .connectionNotConnected),
                coreMessage: "Not connected to device.",
                displayMessage: """
                    Not connected to device.
                      The previous connection may have closed or timed out.
                      Hint: Check that the app is running, then retry the command. Use 'buttonheist list_devices' to see available devices.
                    """
            )
        case .actionTimeout:
            return FenceFailureDescriptor(
                details: FailureDetails(code: .requestTimeout),
                coreMessage: "Command timed out waiting for a response from the app.",
                displayMessage: """
                    Command timed out waiting for a response from the app.
                      \(Self.actionTimeoutRecoveryHint)
                    """
            )
        case .actionFailed(let message):
            let displayMessage = "Action failed: \(message)"
            return FenceFailureDescriptor(
                details: FailureDetails(code: .requestActionFailed),
                coreMessage: displayMessage,
                displayMessage: displayMessage
            )
        case .serverError(let serverError):
            let displayMessage = "Action failed: \(serverError.message)"
            return FenceFailureDescriptor(
                details: serverError.failureDescriptor.details,
                coreMessage: displayMessage,
                displayMessage: displayMessage
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
            code: FailureCode(boundaryRawValue: primary.code.rawValue),
            phase: .request,
            retryable: false,
            hint: primary.hint
        )
    }
}
