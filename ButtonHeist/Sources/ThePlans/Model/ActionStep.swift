import Foundation

public struct ActionExpectationWaiver: NonBlankStringValue {
    public let reason: String

    public init(validating reason: String) throws {
        self.reason = try validateNonBlank(reason, kind: "expectation waiver")
    }

    public var description: String {
        reason
    }
}

public struct ActionExpectationTimeoutPolicy: Sendable, Equatable {
    public static let `default` = Self()

    public let standard: WaitTimeout
    public let screenTransition: WaitTimeout

    public init(
        standard: WaitTimeout = 1,
        screenTransition: WaitTimeout = 10
    ) {
        self.standard = standard
        self.screenTransition = screenTransition
    }

    public func timeout(for predicate: AccessibilityPredicate) -> WaitTimeout {
        guard case .screenChanged = predicate.core else {
            return standard
        }
        return screenTransition
    }
}

public struct ActionExpectation: Codable, Sendable, Equatable {
    public enum Timeout: Sendable, Equatable {
        case sessionDefault
        case explicit(WaitTimeout)
    }

    public let predicate: AccessibilityPredicate
    public let timeout: Timeout

    public init(
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout? = nil
    ) {
        self.predicate = predicate
        self.timeout = timeout.map(Timeout.explicit) ?? .sessionDefault
    }

    public init(predicate: AccessibilityPredicate, timeout: Timeout) {
        self.predicate = predicate
        self.timeout = timeout
    }

    public init(_ step: WaitStep) throws {
        guard step.elseBody == nil else {
            throw HeistPlanBuildError.planStructure(
                path: "$.expectation.else_body",
                message: "action expectations do not support an else body"
            )
        }
        self.init(predicate: step.predicate, timeout: .explicit(step.timeout))
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "action expectation")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
            timeout: try container.decodeIfPresent(WaitTimeout.self, forKey: .timeout)
                .map(Timeout.explicit) ?? .sessionDefault
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        if case .explicit(let timeout) = timeout {
            try container.encode(timeout, forKey: .timeout)
        }
    }

    package func resolvingTimeout(using policy: ActionExpectationTimeoutPolicy) -> Self {
        switch timeout {
        case .sessionDefault:
            return Self(predicate: predicate, timeout: .explicit(policy.timeout(for: predicate)))
        case .explicit:
            return self
        }
    }

    package var resolvedStep: WaitStep {
        guard case .explicit(let timeout) = timeout else {
            preconditionFailure("TheFence must resolve action expectation timeouts before dispatch")
        }
        return WaitStep(predicate: predicate, timeout: timeout)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
    }
}

public enum ActionExpectationPolicy: Sendable, Equatable {
    case `default`
    case expect(ActionExpectation)
    case waived(ActionExpectationWaiver)

    package var expectedExpectation: ActionExpectation? {
        guard case .expect(let expectation) = self else { return nil }
        return expectation
    }

    package var expectedStep: WaitStep? {
        guard case .expect(let expectation) = self else { return nil }
        return expectation.resolvedStep
    }

    public var waiver: ActionExpectationWaiver? {
        guard case .waived(let waiver) = self else { return nil }
        return waiver
    }

    public var requiresAuthoredExpectation: Bool {
        self == .default
    }

    package func resolvingTimeout(using policy: ActionExpectationTimeoutPolicy) -> Self {
        guard case .expect(let expectation) = self else { return self }
        return .expect(expectation.resolvingTimeout(using: policy))
    }
}

extension ActionExpectationPolicy: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case expectation
        case waiver = "without_expectation"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "action expectation policy")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try Self.decode(
            from: container,
            expectationKey: .expectation,
            waiverKey: .waiver,
            ambiguousError: DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "action expectation policy cannot include both expectation and without_expectation"
            ))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encode(to: &container, expectationKey: .expectation, waiverKey: .waiver)
    }

    fileprivate static func decode<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        expectationKey: Key,
        waiverKey: Key,
        ambiguousError: Error
    ) throws -> Self {
        let expectation = try container.decodeIfPresent(ActionExpectation.self, forKey: expectationKey)
        let waiver = try container.decodeIfPresent(ActionExpectationWaiver.self, forKey: waiverKey)
        switch (expectation, waiver) {
        case (.none, .none): return .default
        case (.some(let expectation), .none): return .expect(expectation)
        case (.none, .some(let waiver)): return .waived(waiver)
        case (.some, .some): throw ambiguousError
        }
    }

    fileprivate func encode<Key: CodingKey>(
        to container: inout KeyedEncodingContainer<Key>,
        expectationKey: Key,
        waiverKey: Key
    ) throws {
        switch self {
        case .default: break
        case .expect(let expectation): try container.encode(expectation, forKey: expectationKey)
        case .waived(let waiver): try container.encode(waiver, forKey: waiverKey)
        }
    }
}

public struct ActionStep: Codable, Sendable, Equatable {
    public let command: HeistActionCommand
    public let expectationPolicy: ActionExpectationPolicy

    public init(
        command: HeistActionCommand,
        expectationPolicy: ActionExpectationPolicy = .default
    ) {
        self.command = command
        self.expectationPolicy = expectationPolicy
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command, expectation
        case expectationWaiver = "without_expectation"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "action step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let expectationPolicy = try ActionExpectationPolicy.decode(
            from: container,
            expectationKey: .expectation,
            waiverKey: .expectationWaiver,
            ambiguousError: DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "action step cannot include both expectation and without_expectation"
            ))
        )
        self.init(
            command: try container.decode(HeistActionCommand.self, forKey: .command),
            expectationPolicy: expectationPolicy
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try expectationPolicy.encode(
            to: &container,
            expectationKey: .expectation,
            waiverKey: .expectationWaiver
        )
    }

    public static func == (lhs: ActionStep, rhs: ActionStep) -> Bool {
        lhs.command == rhs.command
            && lhs.expectationPolicy == rhs.expectationPolicy
    }
}
