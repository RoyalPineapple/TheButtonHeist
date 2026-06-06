import Foundation

// MARK: - Heist Plan

/// Canonical ordered automation contract.
///
/// Swift DSL source, dynamic agent JSON, live composition, and run-heist all converge
/// on this value. DSL syntax is source authoring; `HeistPlan` is the product
/// contract executed by the runtime. The plan stores semantic structure; it
/// does not observe UI state, settle, report, compose live interactions, or dispatch actions.
public struct HeistPlan: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public let version: Int
    public let name: String?
    public let parameter: HeistParameter
    public let definitions: [HeistPlan]
    public let body: [HeistStep]

    public init(
        version: Int = HeistPlan.currentVersion,
        name: String? = nil,
        parameter: HeistParameter = .none,
        definitions: [HeistPlan] = [],
        body: [HeistStep]
    ) throws {
        self = try UnvalidatedHeistPlan(
            version: version,
            name: name,
            parameter: parameter,
            definitions: definitions.map(UnvalidatedHeistPlan.init),
            body: body
        ).validatedForRuntime()
    }

    init(
        runtimeValidatedVersion version: Int,
        name: String? = nil,
        parameter: HeistParameter = .none,
        definitions: [HeistPlan] = [],
        body: [HeistStep]
    ) {
        self.version = version
        self.name = name
        self.parameter = parameter
        self.definitions = definitions
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        self = try UnvalidatedHeistPlan(from: decoder).validatedForRuntime()
    }

    public func encode(to encoder: Encoder) throws {
        try UnvalidatedHeistPlan(self).encode(to: encoder)
    }
}

public enum HeistParameter: Codable, Sendable, Equatable {
    case none
    case strings(name: HeistReferenceName)
    case elementTarget(name: HeistReferenceName)

    public var name: HeistReferenceName? {
        switch self {
        case .none:
            return nil
        case .strings(let name), .elementTarget(let name):
            return name
        }
    }

    public var kind: HeistParameterKind {
        switch self {
        case .none: return .none
        case .strings: return .strings
        case .elementTarget: return .elementTarget
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, name
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist parameter")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(HeistParameterKind.self, forKey: .type)
        switch type {
        case .none:
            if container.contains(.name) {
                throw DecodingError.dataCorruptedError(
                    forKey: .name,
                    in: container,
                    debugDescription: "none heist parameter must not include a name"
                )
            }
            self = .none
        case .strings:
            self = .strings(name: try container.decode(String.self, forKey: .name))
        case .elementTarget:
            self = .elementTarget(name: try container.decode(String.self, forKey: .name))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        if let name {
            try container.encode(name, forKey: .name)
        }
    }
}

public enum HeistParameterKind: String, Codable, Sendable, Equatable {
    case none
    case strings
    case elementTarget = "element_target"
}

public enum HeistArgument: Codable, Sendable, Equatable {
    case none
    case strings([StringExpr])
    case elementTarget(ElementTargetExpr)

    public var kind: HeistParameterKind {
        switch self {
        case .none: return .none
        case .strings: return .strings
        case .elementTarget: return .elementTarget
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, value
        case valueRef = "value_ref"
        case target
        case values
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist argument")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(HeistParameterKind.self, forKey: .type)
        switch type {
        case .none:
            let hasValue = container.contains(.value)
                || container.contains(.valueRef)
                || container.contains(.target)
                || container.contains(.values)
            if hasValue {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "none heist argument must not include a value"
                ))
            }
            self = .none
        case .strings:
            let hasValues = container.contains(.values)
            let hasValue = container.contains(.value)
            let hasRef = container.contains(.valueRef)
            guard hasValues != (hasValue || hasRef) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "strings heist argument requires values or exactly one of value/value_ref"
                ))
            }
            if hasValues {
                self = .strings(try container.decode([StringExpr].self, forKey: .values))
            } else {
                guard hasValue != hasRef else {
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: container.codingPath,
                        debugDescription: "strings heist argument requires values or exactly one of value/value_ref"
                    ))
                }
                self = hasValue
                    ? .strings([.literal(try container.decode(String.self, forKey: .value))])
                    : .strings([.ref(try container.decode(String.self, forKey: .valueRef))])
            }
        case .elementTarget:
            // Singular: a predicate for exactly one element, carried under `target`
            // as an element-target expression (concrete target, predicate, or ref).
            guard container.contains(.target) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "element_target heist argument requires a target"
                ))
            }
            self = .elementTarget(try container.decode(ElementTargetExpr.self, forKey: .target))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .none:
            break
        case .strings(let values):
            try container.encode(values, forKey: .values)
        case .elementTarget(let target):
            try container.encode(target, forKey: .target)
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
    indirect case heist(HeistPlan)
    case invoke(HeistInvocationStep)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, action, wait, conditional, waitForCases = "wait_for_cases"
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case warn, fail, heist, invoke
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
        case heist
        case invoke
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
        case .heist:
            try decoder.rejectUnknownKeys(allowed: ["type", "heist"], typeName: "heist group step")
            self = .heist(try container.decode(HeistPlan.self, forKey: .heist))
        case .invoke:
            try decoder.rejectUnknownKeys(allowed: ["type", "invoke"], typeName: "invoke heist step")
            self = .invoke(try container.decode(HeistInvocationStep.self, forKey: .invoke))
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
        case .heist(let plan):
            try container.encode(StepType.heist, forKey: .type)
            try container.encode(plan, forKey: .heist)
        case .invoke(let step):
            try container.encode(StepType.invoke, forKey: .type)
            try container.encode(step, forKey: .invoke)
        }
    }
}

// MARK: - Step Payloads

public struct ActionStep: Codable, Sendable, Equatable {
    public let command: HeistActionCommand
    public let expectation: WaitStep?
    public let expectationWaiver: String?
    let expectationValidationFailure: String?

    public init(
        command: HeistActionCommand,
        expectation: WaitStep? = nil,
        expectationWaiver: String? = nil,
        expectationValidationFailure: String? = nil
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
        self.expectationValidationFailure = expectationValidationFailure
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

    public static func == (lhs: ActionStep, rhs: ActionStep) -> Bool {
        lhs.command == rhs.command
            && lhs.expectation == rhs.expectation
            && lhs.expectationWaiver == rhs.expectationWaiver
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
        case elseBody = "else_body"
    }

    public let cases: [PredicateCase]
    public let elseBody: [HeistStep]?

    public init(cases: [PredicateCase], elseBody: [HeistStep]? = nil) throws {
        guard !cases.isEmpty else {
            throw HeistPlanError.emptyPredicateCases("conditional")
        }
        self.cases = cases
        self.elseBody = elseBody
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "conditional step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            cases: try container.decode([PredicateCase].self, forKey: .cases),
            elseBody: try container.decodeIfPresent([HeistStep].self, forKey: .elseBody)
        )
    }
}

public struct WaitForCasesStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case timeout, cases
        case elseBody = "else_body"
    }

    public let timeout: Double
    public let cases: [PredicateCase]
    public let elseBody: [HeistStep]?

    public init(
        timeout: Double,
        cases: [PredicateCase],
        elseBody: [HeistStep]? = nil
    ) throws {
        guard timeout >= 0 else {
            throw HeistPlanError.negativeTimeout(timeout)
        }
        guard !cases.isEmpty else {
            throw HeistPlanError.emptyPredicateCases("wait_for_cases")
        }
        self.timeout = timeout
        self.cases = cases
        self.elseBody = elseBody
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
            elseBody: try container.decodeIfPresent([HeistStep].self, forKey: .elseBody)
        )
    }
}

public struct PredicateCase: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, body
    }

    public let predicate: AccessibilityPredicateExpr
    public let body: [HeistStep]

    public init(predicate: AccessibilityPredicateExpr, body: [HeistStep]) {
        self.predicate = predicate
        self.body = body
    }

    @_disfavoredOverload
    public init(predicate: AccessibilityPredicate, body: [HeistStep]) {
        self.init(predicate: .predicate(predicate), body: body)
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "predicate case")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(AccessibilityPredicateExpr.self, forKey: .predicate),
            body: try container.decode([HeistStep].self, forKey: .body)
        )
    }
}

public struct ForEachElementStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case matching, limit, parameter, body
    }

    public let matching: ElementPredicate
    public let limit: Int
    public let parameter: String
    public let body: [HeistStep]

    public init(
        matching: ElementPredicate,
        limit: Int,
        parameter: String,
        body: [HeistStep]
    ) throws {
        guard matching.hasPredicates else {
            throw HeistPlanError.emptyForEachPredicate
        }
        guard limit > 0 else {
            throw HeistPlanError.invalidForEachLimit(limit)
        }
        guard !body.isEmpty else {
            throw HeistPlanError.emptyForEachSteps
        }
        self.matching = matching
        self.limit = limit
        self.parameter = parameter
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "for_each_element step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            matching: try container.decode(ElementPredicate.self, forKey: .matching),
            limit: try container.decode(Int.self, forKey: .limit),
            parameter: try container.decode(String.self, forKey: .parameter),
            body: try container.decode([HeistStep].self, forKey: .body)
        )
    }
}

public struct ForEachStringStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case values, parameter, body
    }

    public let values: [String]
    public let parameter: String
    public let body: [HeistStep]

    public init(
        values: [String],
        parameter: String,
        body: [HeistStep]
    ) throws {
        guard !values.isEmpty else {
            throw HeistPlanError.emptyForEachValues
        }
        guard !body.isEmpty else {
            throw HeistPlanError.emptyForEachSteps
        }
        self.values = values
        self.parameter = parameter
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "for_each_string step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            values: try container.decode([String].self, forKey: .values),
            parameter: try container.decode(String.self, forKey: .parameter),
            body: try container.decode([HeistStep].self, forKey: .body)
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

public struct HeistInvocationStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path, argument
    }

    public let path: [String]
    public let argument: HeistArgument

    public init(
        path: [String],
        argument: HeistArgument = .none
    ) {
        self.path = path
        self.argument = argument
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist invocation step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode([String].self, forKey: .path),
            argument: try container.decodeIfPresent(HeistArgument.self, forKey: .argument) ?? .none
        )
    }

    /// Dotted capability name, e.g. `LibraryScreen.addToCart`.
    public var capabilityName: String {
        path.joined(separator: ".")
    }

    /// Report/display summary of this run as `RunHeist("Name", argument)`.
    /// The frame is the product — reports surface this rather than a bare
    /// `invoke`, so a reader can see which capability ran and with what.
    public var runHeistSummary: String {
        let name = "\"\(capabilityName)\""
        switch argument {
        case .none:
            return "RunHeist(\(name))"
        case .strings(let values):
            let rendered = values.map(Self.stringArgumentSummary).joined(separator: ", ")
            return "RunHeist(\(name), \(rendered))"
        case .elementTarget(let target):
            return "RunHeist(\(name), \(Self.targetArgumentSummary(target)))"
        }
    }

    private static func stringArgumentSummary(_ expr: StringExpr) -> String {
        switch expr {
        case .literal(let value):
            return "\"\(value)\""
        case .ref(let reference):
            return reference
        }
    }

    private static func targetArgumentSummary(_ expr: ElementTargetExpr) -> String {
        switch expr {
        case .ref(let reference):
            return reference
        default:
            return expr.description
        }
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

@_spi(ButtonHeistInternals) public extension HeistPlan {
    func heistDefinition(at path: [String]) -> HeistPlan? {
        HeistDefinitionScope(definitions: definitions).resolve(path: path)?.definition
    }
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
            body: body
        )
    }
}

public struct ResolvedPredicateCase: Sendable, Equatable {
    public let predicate: AccessibilityPredicate
    public let body: [HeistStep]
}
