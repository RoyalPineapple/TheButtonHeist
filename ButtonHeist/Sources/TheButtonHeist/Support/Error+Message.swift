import Foundation

/// Machine-readable failure metadata for formatting and diagnostics.
public struct FailureDetails: Equatable, Sendable {
    /// Stable error code for grouping similar failures.
    public let errorCode: String
    /// Broad lifecycle phase where the failure occurred.
    public let phase: FailurePhase
    /// Whether retrying the same operation can reasonably succeed.
    public let retryable: Bool
    /// Short recovery hint that can be surfaced separately from the message.
    public let hint: String?

    /// Creates failure metadata from the typed failure taxonomy.
    public init(errorCode: String, phase: FailurePhase, retryable: Bool, hint: String?) {
        self.errorCode = errorCode
        self.phase = phase
        self.retryable = retryable
        self.hint = hint
    }
}

extension Error {
    /// Extract the best available user-facing error message.
    /// Prefers `LocalizedError.errorDescription`, falls back to `localizedDescription`.
    public var displayMessage: String {
        if let localized = self as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return localizedDescription
    }
}

extension FenceError {
    /// The concise message to show when `failureDetails` carries recovery guidance separately.
    public var coreMessage: String {
        switch self {
        case .connectionTimeout:
            return "Connection timed out"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .connectionFailure(let failure):
            return failure.message
        case .sessionLocked(let message):
            return "Session locked: \(message)"
        case .authFailed(let message):
            return "Auth failed: \(message)"
        case .notConnected:
            return "Not connected to device."
        case .actionTimeout:
            return "Command timed out waiting for a response from the app."
        case .invalidRequest, .noDeviceFound, .noMatchingDevice, .actionFailed, .serverError:
            return displayMessage
        }
    }

    /// Machine-readable metadata for this failure.
    public var failureDetails: FailureDetails {
        FailureDetails(
            errorCode: errorCode,
            phase: phase,
            retryable: retryable,
            hint: hint
        )
    }
}
