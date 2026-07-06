import Foundation

/// Machine-readable failure metadata for formatting and diagnostics.
public struct FailureDetails: Equatable, Sendable {
    /// Typed stable failure code for grouping similar failures.
    public let code: KnownFailureCode
    /// Short recovery hint that can be surfaced separately from the message.
    public let hint: String?

    /// Raw JSON/API boundary projection of `code`.
    public var errorCode: String { code.rawValue }
    /// Broad lifecycle phase where the failure occurred.
    public var phase: FailurePhase { code.phase }
    /// Whether retrying the same operation can reasonably succeed.
    public var retryable: Bool { code.retryable }

    /// Creates failure metadata from the typed failure taxonomy.
    public init(code: KnownFailureCode, hint: String? = nil) {
        self.code = code
        self.hint = hint ?? code.defaultHint
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
        failureDescriptor.coreMessage
    }

    /// Machine-readable metadata for this failure.
    public var failureDetails: FailureDetails {
        failureDescriptor.details
    }
}
