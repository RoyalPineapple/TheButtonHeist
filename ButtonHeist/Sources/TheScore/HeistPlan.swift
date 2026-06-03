import Foundation

// MARK: - Heist Plan

/// Canonical ordered automation contract.
///
/// Swift DSL source, dynamic agent JSON, recordings, and playback all converge
/// on this value. DSL syntax is source authoring; `HeistPlan` is the product
/// contract executed by the runtime.
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

// MARK: - Heist Step

public enum HeistStep: Codable, Sendable, Equatable {
    case action(ActionStep)
    case wait(WaitStep)
    case conditional(ConditionalStep)
    case waitForCases(WaitForCasesStep)
    case forEachElement(ForEachElementStep)
    case forEachString(ForEachStringStep)
    case warn(WarnStep)
    case fail(FailStep)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, action, wait, conditional, waitForCases = "wait_for_cases"
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case warn, fail
    }

    private enum StepType: String, Codable {
        case action
        case wait
        case conditional
        case waitForCases = "wait_for_cases"
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
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
        case .forEachElement:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.forEachElement.stringValue],
                typeName: "for_each_element heist step"
            )
            self = .forEachElement(try container.decode(ForEachElementStep.self, forKey: .forEachElement))
        case .forEachString:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.forEachString.stringValue],
                typeName: "for_each_string heist step"
            )
            self = .forEachString(try container.decode(ForEachStringStep.self, forKey: .forEachString))
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
        case .forEachElement(let step):
            try container.encode(StepType.forEachElement, forKey: .type)
            try container.encode(step, forKey: .forEachElement)
        case .forEachString(let step):
            try container.encode(StepType.forEachString, forKey: .type)
            try container.encode(step, forKey: .forEachString)
        case .warn(let step):
            try container.encode(StepType.warn, forKey: .type)
            try container.encode(step, forKey: .warn)
        case .fail(let step):
            try container.encode(StepType.fail, forKey: .type)
            try container.encode(step, forKey: .fail)
        }
    }
}

// MARK: - Step Payloads

public struct ActionStep: Codable, Sendable, Equatable {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?

    public init(
        command: HeistActionCommand,
        expectation: WaitStep? = nil,
        expectationWaiver: String? = nil
    ) throws {
        if let expectationWaiver {
            guard !expectationWaiver.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HeistPlanError.emptyExpectationWaiver
            }
            guard expectation == nil else {
                throw HeistPlanError.ambiguousExpectationContract
            }
        }
        self.command = command
        self.expectation = expectation
        self.expectationWaiver = expectationWaiver
    }

    @_disfavoredOverload
    public init(
        command: ClientMessage,
        expectation: WaitStep? = nil,
        expectationWaiver: String? = nil
    ) throws {
        try self.init(
            command: HeistActionCommand(clientMessage: command),
            expectation: expectation,
            expectationWaiver: expectationWaiver
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case command, expectation
        case expectationWaiver = "without_expectation"
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "action step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            command: try container.decode(HeistActionCommand.self, forKey: .command),
            expectation: try container.decodeIfPresent(WaitStep.self, forKey: .expectation),
            expectationWaiver: try container.decodeIfPresent(String.self, forKey: .expectationWaiver)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(command, forKey: .command)
        try container.encodeIfPresent(expectation, forKey: .expectation)
        try container.encodeIfPresent(expectationWaiver, forKey: .expectationWaiver)
    }
}

public struct WaitStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout
    }

    public let predicate: AccessibilityPredicateExpr
    /// Seconds. `0` means immediate predicate evaluation.
    public let timeout: Double

    public init(predicate: AccessibilityPredicateExpr, timeout: Double = 0) {
        self.predicate = predicate
        self.timeout = timeout
    }

    @_disfavoredOverload
    public init(predicate: AccessibilityPredicate, timeout: Double = 0) {
        self.init(predicate: .predicate(predicate), timeout: timeout)
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
            predicate: try container.decode(AccessibilityPredicateExpr.self, forKey: .predicate),
            timeout: decodedTimeout
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(predicate, forKey: .predicate)
        try container.encode(timeout, forKey: .timeout)
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
        guard !cases.contains(where: { $0.steps.containsRuntimeForEach }),
              elseSteps?.containsRuntimeForEach != true else {
            throw HeistPlanError.nestedForEachUnsupported
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
        guard !cases.contains(where: { $0.steps.containsRuntimeForEach }),
              elseSteps?.containsRuntimeForEach != true else {
            throw HeistPlanError.nestedForEachUnsupported
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

public struct PredicateCase: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, steps
    }

    public let predicate: AccessibilityPredicateExpr
    public let steps: [HeistStep]

    public init(predicate: AccessibilityPredicateExpr, steps: [HeistStep]) {
        self.predicate = predicate
        self.steps = steps
    }

    @_disfavoredOverload
    public init(predicate: AccessibilityPredicate, steps: [HeistStep]) {
        self.init(predicate: .predicate(predicate), steps: steps)
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "predicate case")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(AccessibilityPredicateExpr.self, forKey: .predicate),
            steps: try container.decode([HeistStep].self, forKey: .steps)
        )
    }
}

public struct ForEachElementStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case matching, limit, parameter, steps
    }

    public let matching: ElementPredicate
    public let limit: Int
    public let parameter: String
    public let steps: [HeistStep]

    public init(
        matching: ElementPredicate,
        limit: Int,
        parameter: String,
        steps: [HeistStep]
    ) throws {
        guard matching.hasPredicates else {
            throw HeistPlanError.emptyForEachPredicate
        }
        guard limit > 0 else {
            throw HeistPlanError.invalidForEachLimit(limit)
        }
        let trimmedParameter = try HeistParameterName.normalized(parameter)
        guard !steps.isEmpty else {
            throw HeistPlanError.emptyForEachSteps
        }
        guard !steps.containsRuntimeForEach else {
            throw HeistPlanError.nestedForEachUnsupported
        }
        self.matching = matching
        self.limit = limit
        self.parameter = trimmedParameter
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "for_each_element step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            matching: try container.decode(ElementPredicate.self, forKey: .matching),
            limit: try container.decode(Int.self, forKey: .limit),
            parameter: try container.decode(String.self, forKey: .parameter),
            steps: try container.decode([HeistStep].self, forKey: .steps)
        )
    }
}

public struct ForEachStringStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case values, parameter, steps
    }

    public let values: [String]
    public let parameter: String
    public let steps: [HeistStep]

    public init(
        values: [String],
        parameter: String,
        steps: [HeistStep]
    ) throws {
        guard !values.isEmpty else {
            throw HeistPlanError.emptyForEachValues
        }
        let trimmedParameter = try HeistParameterName.normalized(parameter)
        guard !steps.isEmpty else {
            throw HeistPlanError.emptyForEachSteps
        }
        guard !steps.containsRuntimeForEach else {
            throw HeistPlanError.nestedForEachUnsupported
        }
        self.values = values
        self.parameter = trimmedParameter
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "for_each_string step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            values: try container.decode([String].self, forKey: .values),
            parameter: try container.decode(String.self, forKey: .parameter),
            steps: try container.decode([HeistStep].self, forKey: .steps)
        )
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
    case ambiguousExpectationContract
    case emptyExpectationWaiver
    case emptyPredicateCases(String)
    case negativeTimeout(Double)
    case emptyForEachPredicate
    case invalidForEachLimit(Int)
    case emptyForEachParameter
    case invalidForEachParameter(String)
    case emptyForEachSteps
    case emptyForEachValues
    case nestedForEachUnsupported
}

public enum HeistParameterName {
    public static func normalized(_ parameter: String) throws -> String {
        let trimmed = parameter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HeistPlanError.emptyForEachParameter
        }
        guard isValid(trimmed) else {
            throw HeistPlanError.invalidForEachParameter(trimmed)
        }
        return trimmed
    }

    public static func isValid(_ parameter: String) -> Bool {
        guard let first = parameter.unicodeScalars.first,
              CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first) else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return parameter.unicodeScalars.allSatisfy { allowed.contains($0) } && !swiftKeywords.contains(parameter)
    }

    private static let swiftKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import",
        "init", "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol",
        "public", "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case",
        "catch", "continue", "default", "defer", "do", "else", "fallthrough", "for", "guard", "if",
        "in", "repeat", "return", "throw", "switch", "where", "while", "as", "Any", "catch", "false",
        "is", "nil", "super", "self", "Self", "throw", "throws", "true", "try",
    ]
}

public struct ResolvedWaitStep: Sendable, Equatable {
    public let predicate: AccessibilityPredicate
    public let timeout: Double

    public init(predicate: AccessibilityPredicate, timeout: Double = 0) {
        self.predicate = predicate
        self.timeout = timeout
    }
}

public extension WaitStep {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedWaitStep {
        ResolvedWaitStep(predicate: try predicate.resolve(in: environment), timeout: timeout)
    }
}

public extension PredicateCase {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedPredicateCase {
        ResolvedPredicateCase(
            predicate: try predicate.resolve(in: environment),
            steps: steps
        )
    }
}

public struct ResolvedPredicateCase: Sendable, Equatable {
    public let predicate: AccessibilityPredicate
    public let steps: [HeistStep]
}

private extension Array where Element == HeistStep {
    var containsRuntimeForEach: Bool {
        contains { step in
            switch step {
            case .forEachElement, .forEachString:
                return true
            case .conditional(let conditional):
                return conditional.cases.contains { $0.steps.containsRuntimeForEach }
                    || conditional.elseSteps?.containsRuntimeForEach == true
            case .waitForCases(let waitForCases):
                return waitForCases.cases.contains { $0.steps.containsRuntimeForEach }
                    || waitForCases.elseSteps?.containsRuntimeForEach == true
            case .action, .wait, .warn, .fail:
                return false
            }
        }
    }
}
