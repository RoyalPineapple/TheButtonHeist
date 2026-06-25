import Foundation

import TheScore

struct FenceFailureDescriptor: Sendable {
    let errorCode: String
    let phase: FailurePhase
    let retryable: Bool
    let hint: String?
    let coreMessage: String
    let displayMessage: String
}

public extension FenceError {
    internal var failureDescriptor: FenceFailureDescriptor {
        switch self {
        case .invalidRequest(let message):
            return FenceFailureDescriptor(
                errorCode: "request.invalid",
                phase: .request,
                retryable: false,
                hint: "Fix the request shape or arguments before retrying.",
                coreMessage: message,
                displayMessage: message
            )
        case .noDeviceFound:
            let message = "No devices found within timeout. Is the app running?"
            return FenceFailureDescriptor(
                errorCode: "discovery.no_device_found",
                phase: .discovery,
                retryable: true,
                hint: "Start the app and confirm it advertises a Button Heist session.",
                coreMessage: message,
                displayMessage: message
            )
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            let message = "No device matching '\(filter)'. Available: \(list)"
            return FenceFailureDescriptor(
                errorCode: "discovery.no_matching_device",
                phase: .discovery,
                retryable: false,
                hint: "Check the device filter or target name against 'buttonheist list_devices'.",
                coreMessage: message,
                displayMessage: message
            )
        case .connectionTimeout:
            let hint = "Is the app running? Check 'buttonheist list_devices' to see available devices."
            return FenceFailureDescriptor(
                errorCode: "setup.timeout",
                phase: .setup,
                retryable: true,
                hint: hint,
                coreMessage: "Connection timed out",
                displayMessage: """
                    Connection timed out
                      Hint: \(hint)
                    """
            )
        case .connectionFailed(let message):
            let hint = "Is the app running? Check 'buttonheist list_devices' to see available devices."
            return FenceFailureDescriptor(
                errorCode: "connection.failed",
                phase: .transport,
                retryable: true,
                hint: hint,
                coreMessage: "Connection failed: \(message)",
                displayMessage: """
                    Connection failed: \(message)
                      Hint: \(hint)
                    """
            )
        case .connectionFailure(let failure):
            return FenceFailureDescriptor(
                errorCode: failure.errorCode,
                phase: failure.phase,
                retryable: failure.retryable,
                hint: failure.hint,
                coreMessage: failure.message,
                displayMessage: failure.message
            )
        case .sessionLocked(let message):
            return FenceFailureDescriptor(
                errorCode: "session.locked",
                phase: .session,
                retryable: true,
                hint: "Wait for the current driver to disconnect or for the session to time out. " +
                    "If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID or restart the app.",
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
                errorCode: "auth.failed",
                phase: .authentication,
                retryable: false,
                hint: nil,
                coreMessage: base,
                displayMessage: base
            )
        case .notConnected:
            return FenceFailureDescriptor(
                errorCode: "connection.not_connected",
                phase: .request,
                retryable: true,
                hint: "Check that the app is running, then retry the command. Use 'buttonheist list_devices' to see available devices.",
                coreMessage: "Not connected to device.",
                displayMessage: """
                    Not connected to device.
                      The previous connection may have closed or timed out.
                      Hint: Check that the app is running, then retry the command. Use 'buttonheist list_devices' to see available devices.
                    """
            )
        case .actionTimeout:
            return FenceFailureDescriptor(
                errorCode: "request.timeout",
                phase: .request,
                retryable: true,
                hint: Self.actionTimeoutRecoveryHint,
                coreMessage: "Command timed out waiting for a response from the app.",
                displayMessage: """
                    Command timed out waiting for a response from the app.
                      \(Self.actionTimeoutRecoveryHint)
                    """
            )
        case .actionFailed(let message):
            let displayMessage = "Action failed: \(message)"
            return FenceFailureDescriptor(
                errorCode: "request.action_failed",
                phase: .request,
                retryable: false,
                hint: nil,
                coreMessage: displayMessage,
                displayMessage: displayMessage
            )
        case .serverError(let serverError):
            let displayMessage = "Action failed: \(serverError.message)"
            return FenceFailureDescriptor(
                errorCode: serverError.errorCode,
                phase: serverError.phase,
                retryable: serverError.retryable,
                hint: serverError.hint,
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
}
