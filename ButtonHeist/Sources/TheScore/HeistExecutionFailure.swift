import Foundation

/// One warning emitted by a `Warn(...)` heist step.
public struct HeistExecutionWarning: Codable, Sendable, Equatable {
    public let path: String
    public let message: String

    public init(
        path: String,
        message: String
    ) {
        self.path = path
        self.message = message
    }
}

public struct HeistFailureDetail: Codable, Sendable, Equatable {
    public let category: HeistFailureCategory
    public let contract: String
    public let observed: String
    public let expected: String?
    public let activationTrace: ActivationTrace?

    public init(
        category: HeistFailureCategory,
        contract: String,
        observed: String,
        expected: String? = nil
    ) {
        self.init(
            category: category,
            contract: contract,
            observed: observed,
            expected: expected,
            activationTrace: nil
        )
    }

    public init(
        category: HeistFailureCategory,
        contract: String,
        observed: String,
        expected: String? = nil,
        activationTrace: ActivationTrace?
    ) {
        self.category = category
        self.contract = contract
        self.observed = observed
        self.expected = expected
        self.activationTrace = activationTrace
    }
}

public enum HeistFailureCategory: String, Codable, Sendable, Equatable {
    case validation
    case runtimeUnavailable
    case targetResolution
    case action
    case expectation
    case wait
    case invocation
    case loop
    case explicitFailure
}
