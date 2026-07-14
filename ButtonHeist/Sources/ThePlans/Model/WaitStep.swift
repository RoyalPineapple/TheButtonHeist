import Foundation

public let immediateTimeout: Double = 0
public let defaultWaitTimeout: Double = 30

public struct WaitStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
        case elseBody = "else_body"
    }

    public let predicate: AccessibilityPredicate
    /// Seconds. `0` means immediate predicate evaluation.
    public let timeout: Double
    public let elseBody: [HeistStep]?

    public init(
        predicate: AccessibilityPredicate,
        timeout: Double = defaultWaitTimeout,
        elseBody: [HeistStep]? = nil
    ) {
        self.predicate = predicate
        self.timeout = timeout
        self.elseBody = elseBody
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "wait step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTimeout = try container.decode(Double.self, forKey: .timeout)
        guard decodedTimeout >= 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .timeout,
                in: container,
                debugDescription: "wait step timeout must be non-negative"
            )
        }
        self.init(
            predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
            timeout: decodedTimeout,
            elseBody: try container.decodeIfPresent([HeistStep].self, forKey: .elseBody)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(timeout, forKey: .timeout)
        try container.encodeIfPresent(elseBody, forKey: .elseBody)
    }
}

package struct ResolvedWaitStep: Sendable, Equatable {
    package let predicate: ResolvedAccessibilityPredicate
    package let timeout: Double

    package init(predicate: ResolvedAccessibilityPredicate, timeout: Double = defaultWaitTimeout) {
        self.predicate = predicate
        self.timeout = timeout
    }
}

package extension WaitStep {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedWaitStep {
        ResolvedWaitStep(predicate: try predicate.resolve(in: environment), timeout: timeout)
    }
}
