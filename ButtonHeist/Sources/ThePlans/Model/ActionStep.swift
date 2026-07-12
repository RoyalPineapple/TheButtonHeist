import Foundation

public struct ActionExpectationWaiver: Codable, Sendable, Equatable, CustomStringConvertible {
    public let reason: String

    public init(_ reason: String) throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HeistPlanError.emptyExpectationWaiver
        }
        self.reason = trimmed
    }

    public var description: String {
        reason
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(reason)
    }
}

public struct ActionExpectation: Codable, Sendable, Equatable {
    public let step: WaitStep

    public init(predicate: AccessibilityPredicateExpr, timeout: Double = defaultWaitTimeout) {
        self.step = WaitStep(predicate: predicate, timeout: timeout)
    }

    @_disfavoredOverload
    public init(predicate: AccessibilityPredicate, timeout: Double = defaultWaitTimeout) {
        self.init(predicate: .predicate(predicate), timeout: timeout)
    }

    public init(_ step: WaitStep) throws {
        guard step.elseBody == nil else {
            throw HeistPlanError.expectationElseBodyUnsupported
        }
        self.step = step
    }

    public init(from decoder: Decoder) throws {
        try self.init(WaitStep(from: decoder))
    }

    public func encode(to encoder: Encoder) throws {
        try step.encode(to: encoder)
    }
}

public enum ActionExpectationPolicy: Sendable, Equatable {
    case `default`
    case expect(ActionExpectation)
    case waived(ActionExpectationWaiver)

    public var expectedStep: WaitStep? {
        guard case .expect(let expectation) = self else { return nil }
        return expectation.step
    }

    public var waiver: ActionExpectationWaiver? {
        guard case .waived(let waiver) = self else { return nil }
        return waiver
    }

    public var requiresAuthoredExpectation: Bool {
        self == .default
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
    let expectationValidationDiagnostics: [HeistBuildDiagnostic]

    public init(
        command: HeistActionCommand,
        expectationPolicy: ActionExpectationPolicy = .default,
        expectationValidationDiagnostics: [HeistBuildDiagnostic] = []
    ) throws {
        self.command = command
        self.expectationPolicy = expectationPolicy
        self.expectationValidationDiagnostics = expectationValidationDiagnostics
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
            ambiguousError: HeistPlanError.ambiguousExpectationContract
        )
        try self.init(
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
