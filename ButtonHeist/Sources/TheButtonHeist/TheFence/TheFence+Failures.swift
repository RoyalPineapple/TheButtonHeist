import Foundation

import TheScore

/// Stable client-side phase for connection and request failures.
///
/// This is not part of the wire protocol. It classifies existing local errors
/// so CLI/MCP surfaces and tests can reason about failures without parsing
/// human messages.
public enum FailurePhase: String, Sendable, Equatable, CaseIterable {
    case discovery
    case setup
    case transport
    case authentication = "auth"
    case session
    case request
    case recording
    case protocolNegotiation = "protocol"
    case tls
    case client
    case server
}

/// Typed connection-attempt failure preserved from the lower-level disconnect cause.
public struct ConnectionFailure: Equatable, Sendable {
    public let message: String
    public let errorCode: String
    public let phase: FailurePhase
    public let retryable: Bool
    public let hint: String?

    public init(
        message: String,
        errorCode: String,
        phase: FailurePhase,
        retryable: Bool,
        hint: String?
    ) {
        self.message = message
        self.errorCode = errorCode
        self.phase = phase
        self.retryable = retryable
        self.hint = hint
    }
}

extension ConnectionFailure {
    init(disconnectReason reason: DisconnectReason) {
        self.init(
            message: reason.connectionFailureMessage,
            errorCode: reason.failureCode,
            phase: reason.phase,
            retryable: reason.retryable,
            hint: reason.hint
        )
    }
}

/// Errors thrown by TheFence during command dispatch, connection, and action execution.
public enum FenceError: Error, LocalizedError {
    case invalidRequest(String)
    case noDeviceFound
    case noMatchingDevice(filter: String, available: [String])
    case connectionTimeout
    case connectionFailed(String)
    case connectionFailure(ConnectionFailure)
    case sessionLocked(String)
    case authFailed(String)
    case authApprovalPending(String)
    case notConnected
    case actionTimeout
    case actionFailed(String)
    case serverError(ServerError)

    private static let actionTimeoutRecoveryHint =
        "The app may be busy on its main thread, processing a long-running UI update, " +
        "or sending a large response. The connection is preserved; retry the command on the same session."

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
                  Hint: Is the app running? Check 'buttonheist list' to see available devices.
                """
        case .connectionFailed(let message):
            return """
                Connection failed: \(message)
                  Hint: Is the app running? Check 'buttonheist list' to see available devices.
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
                Auth approval pending: \(message)
                  Waiting for approval on the device. Tap Allow on the iOS device to continue.
                """
        case .notConnected:
            return """
                Not connected to device.
                  The previous connection may have closed or timed out.
                  Hint: Check that the app is running, then retry the command. Use 'buttonheist list' to see available devices.
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

    public var errorCode: String {
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

    public var phase: FailurePhase {
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

    public var retryable: Bool {
        switch self {
        case .noDeviceFound, .connectionTimeout, .connectionFailed, .sessionLocked,
             .notConnected, .actionTimeout:
            return true
        case .connectionFailure(let failure):
            return failure.retryable
        case .authApprovalPending:
            return true
        case .invalidRequest, .noMatchingDevice, .authFailed, .actionFailed:
            return false
        case .serverError(let serverError):
            return serverError.retryable
        }
    }

    public var hint: String? {
        switch self {
        case .invalidRequest:
            return "Fix the request shape or arguments before retrying."
        case .noDeviceFound:
            return "Start the app and confirm it advertises a Button Heist session."
        case .noMatchingDevice:
            return "Check the device filter or target name against 'buttonheist list'."
        case .connectionTimeout:
            return "Is the app running? Check 'buttonheist list' to see available devices."
        case .connectionFailed:
            return "Is the app running? Check 'buttonheist list' to see available devices."
        case .connectionFailure(let failure):
            return failure.hint
        case .sessionLocked:
            return "Wait for the current driver to disconnect or for the session to time out. " +
                "If this is your own stale session, retry with the same BUTTONHEIST_DRIVER_ID or restart the app."
        case .authFailed(let message):
            return Self.authFailureRecoveryHint(for: message)
        case .authApprovalPending:
            return "Waiting for approval on the device. Tap Allow on the iOS device to continue."
        case .notConnected:
            return "Check that the app is running, then retry the command. Use 'buttonheist list' to see available devices."
        case .actionTimeout:
            return Self.actionTimeoutRecoveryHint
        case .actionFailed:
            return nil
        case .serverError(let serverError):
            return serverError.hint
        }
    }

    fileprivate static func authFailureRecoveryHint(for message: String) -> String? {
        if message.localizedCaseInsensitiveContains("configured token") {
            return "Retry with the configured token."
        }
        if message.localizedCaseInsensitiveContains("retry without") {
            return "Retry without --token to request a fresh session."
        }
        return nil
    }
}

public extension ServerError {
    var errorCode: String {
        kind.errorCode
    }

    var phase: FailurePhase {
        kind.phase
    }

    var retryable: Bool {
        kind.retryable
    }

    var hint: String? {
        if kind == .authFailure {
            return FenceError.authFailureRecoveryHint(for: message)
        }
        return kind.hint
    }
}

private extension ErrorKind {
    var errorCode: String {
        switch self {
        case .elementNotFound:
            return "request.element_not_found"
        case .timeout:
            return "request.timeout"
        case .unsupported:
            return "request.unsupported"
        case .inputError:
            return "request.input_error"
        case .validationError:
            return "request.validation_error"
        case .actionFailed:
            return "request.action_failed"
        case .authFailure:
            return "auth.failed"
        case .authApprovalPending:
            return "auth.approval_pending"
        case .recording:
            return "recording.failed"
        case .general:
            return "server.general"
        }
    }

    var phase: FailurePhase {
        switch self {
        case .elementNotFound, .timeout, .unsupported, .inputError,
             .validationError, .actionFailed:
            return .request
        case .authFailure, .authApprovalPending:
            return .authentication
        case .recording:
            return .recording
        case .general:
            return .server
        }
    }

    var retryable: Bool {
        switch self {
        case .timeout:
            return true
        case .authApprovalPending:
            return true
        case .elementNotFound, .unsupported, .inputError, .validationError,
             .actionFailed, .authFailure, .recording, .general:
            return false
        }
    }

    var hint: String? {
        switch self {
        case .elementNotFound:
            return "Refresh the interface and verify the target's accessibility properties."
        case .timeout:
            return "The request timed out; retry on the same session if the app is responsive."
        case .unsupported:
            return "Use a supported command or target for this element."
        case .inputError:
            return "Fix the request input before retrying."
        case .validationError:
            return "Fix the request so it satisfies the server-side validation rules."
        case .actionFailed:
            return nil
        case .authFailure:
            return nil
        case .authApprovalPending:
            return "Waiting for approval on the device. Tap Allow on the iOS device to continue."
        case .recording:
            return "Stop any in-progress recording and retry after resolving the recording error."
        case .general:
            return nil
        }
    }
}

extension FenceError {
    init(_ connectionError: TheHandoff.ConnectionError) {
        switch connectionError {
        case .connectionFailed(let message): self = .connectionFailed(message)
        case .disconnected(.authFailed(let reason)): self = .authFailed(reason)
        case .disconnected(.authApprovalPending(let message)): self = .authApprovalPending(message)
        case .disconnected(.sessionLocked(let message)): self = .sessionLocked(message)
        case .disconnected(let reason): self = .connectionFailure(ConnectionFailure(disconnectReason: reason))
        case .timeout: self = .connectionTimeout
        case .noDeviceFound: self = .noDeviceFound
        case .noMatchingDevice(let filter, let available): self = .noMatchingDevice(filter: filter, available: available)
        }
    }

    init(_ sendFailure: DeviceSendFailure) {
        switch sendFailure {
        case .notConnected:
            self = .notConnected
        case .encodingFailed(let message):
            self = .actionFailed("Failed to send request: \(message)")
        case .transportFailed(let message):
            self = .actionFailed("Transport send failed: \(message)")
        }
    }
}
