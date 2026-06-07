import Foundation

extension FenceError: LocalizedError {
    static let actionTimeoutRecoveryHint =
        "The app may be busy on its main thread, processing a long-running UI update, " +
        "or sending a large response. The connection is preserved; retry the command on the same session."
    static let legacyAuthApprovalRecoveryHint =
        "Received a legacy auth-approval response from the app. Rebuild or reinstall " +
        "the app, then retry with the configured token."

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return message
        case .noDeviceFound:
            return "No devices found within timeout. Is the app running?"
        case .noMatchingDevice(let filter, let available):
            let list = available.isEmpty ? "(none)" : available.joined(separator: ", ")
            return "No device matching '\(filter)'. Available: \(list)"
        case .connectionTimeout:
            return """
                Connection timed out
                  Hint: Is the app running? Check 'buttonheist list_devices' to see available devices.
                """
        case .connectionFailed(let message):
            return """
                Connection failed: \(message)
                  Hint: Is the app running? Check 'buttonheist list_devices' to see available devices.
                """
        case .connectionFailure(let failure):
            return failure.message
        case .sessionLocked(let message):
            return """
                Session locked: \(message)
                  Another driver is currently connected. Wait for it to disconnect
                  or for the session to time out.
                  If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID
                  or restart the app to release it.
                """
        case .authFailed(let message):
            let base = "Auth failed: \(message)"
            guard let hint = Self.authFailureRecoveryHint(for: message) else { return base }
            return """
                \(base)
                  \(hint)
                """
        case .authApprovalPending(let message):
            return """
                Legacy auth approval response: \(message)
                  \(Self.legacyAuthApprovalRecoveryHint)
                """
        case .notConnected:
            return """
                Not connected to device.
                  The previous connection may have closed or timed out.
                  Hint: Check that the app is running, then retry the command. Use 'buttonheist list_devices' to see available devices.
                """
        case .actionTimeout:
            return """
                Command timed out waiting for a response from the app.
                  \(Self.actionTimeoutRecoveryHint)
                """
        case .actionFailed(let message):
            return "Action failed: \(message)"
        case .serverError(let serverError):
            return "Action failed: \(serverError.message)"
        }
    }

    static func authFailureRecoveryHint(for message: String) -> String? {
        if message.localizedCaseInsensitiveContains("configured token") {
            return "Retry with the configured token."
        }
        if message.localizedCaseInsensitiveContains("retry without") {
            return "Retry without --token to request a fresh session."
        }
        return nil
    }
}
