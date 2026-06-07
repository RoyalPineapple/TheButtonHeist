import Foundation

import TheScore

public extension FenceError {
    var errorCode: String {
        switch self {
        case .invalidRequest:
            return "request.invalid"
        case .noDeviceFound:
            return "discovery.no_device_found"
        case .noMatchingDevice:
            return "discovery.no_matching_device"
        case .connectionTimeout:
            return "setup.timeout"
        case .connectionFailed:
            return "connection.failed"
        case .connectionFailure(let failure):
            return failure.errorCode
        case .sessionLocked:
            return "session.locked"
        case .authFailed:
            return "auth.failed"
        case .authApprovalPending:
            return "auth.approval_pending"
        case .notConnected:
            return "connection.not_connected"
        case .actionTimeout:
            return "request.timeout"
        case .actionFailed:
            return "request.action_failed"
        case .serverError(let serverError):
            return serverError.errorCode
        }
    }

    var phase: FailurePhase {
        switch self {
        case .invalidRequest, .notConnected, .actionTimeout, .actionFailed:
            return .request
        case .noDeviceFound, .noMatchingDevice:
            return .discovery
        case .connectionTimeout:
            return .setup
        case .connectionFailed:
            return .transport
        case .connectionFailure(let failure):
            return failure.phase
        case .sessionLocked:
            return .session
        case .authFailed, .authApprovalPending:
            return .authentication
        case .serverError(let serverError):
            return serverError.phase
        }
    }

    var retryable: Bool {
        switch self {
        case .noDeviceFound, .connectionTimeout, .connectionFailed, .sessionLocked,
             .notConnected, .actionTimeout:
            return true
        case .connectionFailure(let failure):
            return failure.retryable
        case .invalidRequest, .noMatchingDevice, .authFailed, .authApprovalPending, .actionFailed:
            return false
        case .serverError(let serverError):
            return serverError.retryable
        }
    }

    var hint: String? {
        switch self {
        case .invalidRequest:
            return "Fix the request shape or arguments before retrying."
        case .noDeviceFound:
            return "Start the app and confirm it advertises a Button Heist session."
        case .noMatchingDevice:
            return "Check the device filter or target name against 'buttonheist list_devices'."
        case .connectionTimeout:
            return "Is the app running? Check 'buttonheist list_devices' to see available devices."
        case .connectionFailed:
            return "Is the app running? Check 'buttonheist list_devices' to see available devices."
        case .connectionFailure(let failure):
            return failure.hint
        case .sessionLocked:
            return "Wait for the current driver to disconnect or for the session to time out. " +
                "If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID or restart the app."
        case .authFailed(let message):
            return Self.authFailureRecoveryHint(for: message)
        case .authApprovalPending:
            return Self.legacyAuthApprovalRecoveryHint
        case .notConnected:
            return "Check that the app is running, then retry the command. Use 'buttonheist list_devices' to see available devices."
        case .actionTimeout:
            return Self.actionTimeoutRecoveryHint
        case .actionFailed:
            return nil
        case .serverError(let serverError):
            return serverError.hint
        }
    }
}
