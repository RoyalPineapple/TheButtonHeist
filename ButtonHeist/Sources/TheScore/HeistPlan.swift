import Foundation

// MARK: - Heist Plan

/// Canonical ordered automation contract.
///
/// Swift DSL source, dynamic agent JSON, recordings, and playback all converge
/// on this value. The Swift DSL itself is future work; `HeistPlan` is the
/// product contract.
public struct HeistPlan: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public let version: Int
    public let steps: [HeistStep]

    public init(
        version: Int = HeistPlan.currentVersion,
        steps: [HeistStep]
    ) {
        self.version = version
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, steps
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist plan")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported heist plan version \(decodedVersion). " +
                    "This Button Heist build supports version \(Self.currentVersion)."
            )
        }
        version = decodedVersion
        steps = try container.decode([HeistStep].self, forKey: .steps)
        guard !steps.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .steps,
                in: container,
                debugDescription: "HeistPlan requires at least one step"
            )
        }
    }
}

extension HeistPlan: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("heistPlan", [
            ScoreDescription.valueField("version", version),
            "steps=\(steps.count)",
        ].compactMap { $0 })
    }
}

// MARK: - Heist Step

public enum HeistStep: Codable, Sendable, Equatable {
    case action(ActionStep)
    case wait(WaitStep)
    case conditional(ConditionalStep)
    case waitForCases(WaitForCasesStep)
    case forEach(ForEachStep)
    case warn(WarnStep)
    case fail(FailStep)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, action, wait, conditional, waitForCases = "wait_for_cases", forEach = "for_each", warn, fail
    }

    private enum StepType: String, Codable {
        case action
        case wait
        case conditional
        case waitForCases = "wait_for_cases"
        case forEach = "for_each"
        case warn
        case fail
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        switch type {
        case .action:
            try decoder.rejectUnknownKeys(allowed: ["type", "action"], typeName: "action heist step")
            self = .action(try container.decode(ActionStep.self, forKey: .action))
        case .wait:
            try decoder.rejectUnknownKeys(allowed: ["type", "wait"], typeName: "wait heist step")
            self = .wait(try container.decode(WaitStep.self, forKey: .wait))
        case .conditional:
            try decoder.rejectUnknownKeys(allowed: ["type", "conditional"], typeName: "conditional heist step")
            self = .conditional(try container.decode(ConditionalStep.self, forKey: .conditional))
        case .waitForCases:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.waitForCases.stringValue],
                typeName: "wait_for_cases heist step"
            )
            self = .waitForCases(try container.decode(WaitForCasesStep.self, forKey: .waitForCases))
        case .forEach:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.forEach.stringValue],
                typeName: "for_each heist step"
            )
            self = .forEach(try container.decode(ForEachStep.self, forKey: .forEach))
        case .warn:
            try decoder.rejectUnknownKeys(allowed: ["type", "warn"], typeName: "warn heist step")
            self = .warn(try container.decode(WarnStep.self, forKey: .warn))
        case .fail:
            try decoder.rejectUnknownKeys(allowed: ["type", "fail"], typeName: "fail heist step")
            self = .fail(try container.decode(FailStep.self, forKey: .fail))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let step):
            try container.encode(StepType.action, forKey: .type)
            try container.encode(step, forKey: .action)
        case .wait(let step):
            try container.encode(StepType.wait, forKey: .type)
            try container.encode(step, forKey: .wait)
        case .conditional(let step):
            try container.encode(StepType.conditional, forKey: .type)
            try container.encode(step, forKey: .conditional)
        case .waitForCases(let step):
            try container.encode(StepType.waitForCases, forKey: .type)
            try container.encode(step, forKey: .waitForCases)
        case .forEach(let step):
            try container.encode(StepType.forEach, forKey: .type)
            try container.encode(step, forKey: .forEach)
        case .warn(let step):
            try container.encode(StepType.warn, forKey: .type)
            try container.encode(step, forKey: .warn)
        case .fail(let step):
            try container.encode(StepType.fail, forKey: .type)
            try container.encode(step, forKey: .fail)
        }
    }
}

extension HeistStep: CustomStringConvertible {
    public var description: String {
        switch self {
        case .action(let step): return step.description
        case .wait(let step): return step.description
        case .conditional(let step): return step.description
        case .waitForCases(let step): return step.description
        case .forEach(let step): return step.description
        case .warn(let step): return step.description
        case .fail(let step): return step.description
        }
    }
}

// MARK: - Step Payloads

public struct ActionStep: Codable, Sendable, Equatable {
    public let command: ClientMessage
    public let expectation: WaitStep?

    public init(command: ClientMessage, expectation: WaitStep? = nil) throws {
        guard command.isHeistActionCommand else {
            throw HeistPlanError.unsupportedActionCommand(command.wireType.rawValue)
        }
        self.command = command
        self.expectation = expectation
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command, expectation
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "action step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            command: try container.decode(ClientMessage.self, forKey: .command),
            expectation: try container.decodeIfPresent(WaitStep.self, forKey: .expectation)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(expectation, forKey: .expectation)
    }
}

extension ActionStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("action", [
            "command=\(command.wireType.rawValue)",
            expectation.map { "expect=\($0)" },
        ].compactMap { $0 })
    }
}

public struct WaitStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
    }

    public let predicate: AccessibilityPredicate
    /// Seconds. `0` means immediate predicate evaluation.
    public let timeout: Double

    public init(predicate: AccessibilityPredicate, timeout: Double = 0) {
        self.predicate = predicate
        self.timeout = timeout
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
            timeout: decodedTimeout
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(timeout, forKey: .timeout)
    }
}

extension WaitStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("wait", [
            predicate.description,
            "timeout=\(ScoreDescription.decimal(timeout))",
        ])
    }
}

public struct ConditionalStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cases
        case elseSteps = "else_steps"
    }

    public let cases: [PredicateCase]
    public let elseSteps: [HeistStep]?

    public init(cases: [PredicateCase], elseSteps: [HeistStep]? = nil) throws {
        guard !cases.isEmpty else {
            throw HeistPlanError.emptyPredicateCases("conditional")
        }
        self.cases = cases
        self.elseSteps = elseSteps
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "conditional step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            cases: try container.decode([PredicateCase].self, forKey: .cases),
            elseSteps: try container.decodeIfPresent([HeistStep].self, forKey: .elseSteps)
        )
    }
}

extension ConditionalStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("if", [
            "cases=\(cases.count)",
            elseSteps.map { "else=\($0.count)" },
        ].compactMap { $0 })
    }
}

public struct WaitForCasesStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case timeout, cases
        case elseSteps = "else_steps"
    }

    public let timeout: Double
    public let cases: [PredicateCase]
    public let elseSteps: [HeistStep]?

    public init(
        timeout: Double,
        cases: [PredicateCase],
        elseSteps: [HeistStep]? = nil
    ) throws {
        guard timeout >= 0 else {
            throw HeistPlanError.negativeTimeout(timeout)
        }
        guard !cases.isEmpty else {
            throw HeistPlanError.emptyPredicateCases("wait_for_cases")
        }
        self.timeout = timeout
        self.cases = cases
        self.elseSteps = elseSteps
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "wait_for_cases step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTimeout = try container.decode(Double.self, forKey: .timeout)
        if decodedTimeout < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .timeout,
                in: container,
                debugDescription: "wait_for_cases timeout must be non-negative"
            )
        }
        try self.init(
            timeout: decodedTimeout,
            cases: try container.decode([PredicateCase].self, forKey: .cases),
            elseSteps: try container.decodeIfPresent([HeistStep].self, forKey: .elseSteps)
        )
    }
}

extension WaitForCasesStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("waitForCases", [
            "timeout=\(ScoreDescription.decimal(timeout))",
            "cases=\(cases.count)",
            elseSteps.map { "else=\($0.count)" },
        ].compactMap { $0 })
    }
}

public struct PredicateCase: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, steps
    }

    public let predicate: AccessibilityPredicate
    public let steps: [HeistStep]

    public init(predicate: AccessibilityPredicate, steps: [HeistStep]) {
        self.predicate = predicate
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "predicate case")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(AccessibilityPredicate.self, forKey: .predicate),
            steps: try container.decode([HeistStep].self, forKey: .steps)
        )
    }
}

extension PredicateCase: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("case", [
            predicate.description,
            "steps=\(steps.count)",
        ])
    }
}

public struct ForEachStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case matching, limit, steps
    }

    public let matching: ElementPredicate
    public let limit: Int
    public let steps: [HeistStep]

    public init(
        matching: ElementPredicate,
        limit: Int,
        steps: [HeistStep]
    ) throws {
        guard matching.hasPredicates else {
            throw HeistPlanError.emptyForEachPredicate
        }
        guard limit > 0 else {
            throw HeistPlanError.invalidForEachLimit(limit)
        }
        guard !steps.isEmpty else {
            throw HeistPlanError.emptyForEachSteps
        }
        self.matching = matching
        self.limit = limit
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "for_each step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            matching: try container.decode(ElementPredicate.self, forKey: .matching),
            limit: try container.decode(Int.self, forKey: .limit),
            steps: try container.decode([HeistStep].self, forKey: .steps)
        )
    }
}

extension ForEachStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("forEach", [
            matching.description,
            "limit=\(limit)",
            "steps=\(steps.count)",
        ])
    }
}

public struct WarnStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case message
    }

    public let message: String

    public init(message: String) {
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "warn step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(message: try container.decode(String.self, forKey: .message))
    }
}

extension WarnStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("warn", [ScoreDescription.quoted(message)])
    }
}

public struct FailStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case message
    }

    public let message: String

    public init(message: String) {
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "fail step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(message: try container.decode(String.self, forKey: .message))
    }
}

public enum HeistPlanError: Error, Sendable, Equatable {
    case unsupportedActionCommand(String)
    case emptyPredicateCases(String)
    case negativeTimeout(Double)
    case emptyForEachPredicate
    case invalidForEachLimit(Int)
    case emptyForEachSteps
}

public extension ClientMessage {
    var isHeistActionCommand: Bool {
        switch self {
        case .activate, .increment, .decrement, .performCustomAction, .rotor,
             .oneFingerTap, .longPress, .swipe, .drag, .typeText, .editAction,
             .setPasteboard, .scroll, .scrollToVisible, .elementSearch,
             .scrollToEdge, .resignFirstResponder:
            return true
        case .clientHello, .authenticate, .requestInterface, .ping, .status,
             .getPasteboard, .requestScreen, .wait, .heistPlan:
            return false
        }
    }
}

extension FailStep: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("fail", [ScoreDescription.quoted(message)])
    }
}
