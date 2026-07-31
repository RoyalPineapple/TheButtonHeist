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

public struct ActionExpectationTimeoutPolicy: Codable, Sendable, Equatable {
    public static let `default` = Self()

    public let standard: WaitTimeout
    public let screenTransition: WaitTimeout

    public init(
        standard: WaitTimeout = 3,
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

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case standard
        case screenTransition = "screen_transition"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: CodingKeys.self,
            typeName: "action expectation timeout policy"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        standard = try container.decode(WaitTimeout.self, forKey: .standard)
        screenTransition = try container.decode(WaitTimeout.self, forKey: .screenTransition)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(standard, forKey: .standard)
        try container.encode(screenTransition, forKey: .screenTransition)
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

    package func waitStep(using policy: ActionExpectationTimeoutPolicy) -> WaitStep {
        let timeout = switch timeout {
        case .sessionDefault:
            policy.timeout(for: predicate)
        case .explicit(let timeout):
            timeout
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

    public var waiver: ActionExpectationWaiver? {
        guard case .waived(let waiver) = self else { return nil }
        return waiver
    }

    public var requiresAuthoredExpectation: Bool {
        self == .default
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
        let expectation = try container.decodeIfPresent(ActionExpectation.self, forKey: .expectation)
        let waiver = try container.decodeIfPresent(ActionExpectationWaiver.self, forKey: .expectationWaiver)
        let expectationPolicy: ActionExpectationPolicy
        switch (expectation, waiver) {
        case (.none, .none):
            expectationPolicy = .default
        case (.some(let expectation), .none):
            expectationPolicy = .expect(expectation)
        case (.none, .some(let waiver)):
            expectationPolicy = .waived(waiver)
        case (.some, .some):
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "action step cannot include both expectation and without_expectation"
            ))
        }
        self.init(
            command: try container.decode(HeistActionCommand.self, forKey: .command),
            expectationPolicy: expectationPolicy
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        switch expectationPolicy {
        case .default:
            break
        case .expect(let expectation):
            try container.encode(expectation, forKey: .expectation)
        case .waived(let waiver):
            try container.encode(waiver, forKey: .expectationWaiver)
        }
    }

    public static func == (lhs: ActionStep, rhs: ActionStep) -> Bool {
        lhs.command == rhs.command
            && lhs.expectationPolicy == rhs.expectationPolicy
    }
}
