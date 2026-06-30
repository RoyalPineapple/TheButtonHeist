import Foundation

// MARK: - Heist Execution Environment

public struct HeistReferenceName: RawRepresentable, Codable, Hashable, Sendable, Equatable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(validating value: String, type: String = "heist") throws {
        guard let normalized = Self.normalized(value) else {
            throw HeistExpressionError.emptyReference(type)
        }
        self = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let normalized = Self.normalized(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "reference must not be empty"
            )
        }
        self = normalized
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func normalized(_ value: String) -> HeistReferenceName? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return HeistReferenceName(rawValue: trimmed)
    }

    public func normalized() -> HeistReferenceName? {
        Self.normalized(rawValue)
    }

    public func validated(type: String = "heist") throws -> HeistReferenceName {
        try Self(validating: rawValue, type: type)
    }
}

extension HeistReferenceName: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

extension HeistReferenceName {
    static func decode<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K,
        type: String? = nil
    ) throws -> HeistReferenceName {
        try decode(try container.decode(String.self, forKey: key), from: container, forKey: key, type: type)
    }

    static func decodeIfPresent<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K,
        type: String? = nil
    ) throws -> HeistReferenceName? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        return try decode(value, from: container, forKey: key, type: type)
    }

    private static func decode<K: CodingKey>(
        _ value: String,
        from container: KeyedDecodingContainer<K>,
        forKey key: K,
        type: String?
    ) throws -> HeistReferenceName {
        guard let normalized = normalized(value) else {
            let subject = type.map { "\($0) reference" } ?? key.stringValue
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "\(subject) must not be empty"
            )
        }
        return normalized
    }
}

public struct HeistExecutionEnvironment: Sendable, Equatable {
    public static let empty = HeistExecutionEnvironment()

    public let targets: [HeistReferenceName: ElementTarget]
    public let strings: [HeistReferenceName: String]

    public init(
        targets: [HeistReferenceName: ElementTarget] = [:],
        strings: [HeistReferenceName: String] = [:]
    ) {
        self.targets = targets
        self.strings = strings
    }

    public func binding(target: ElementTarget, to parameter: HeistReferenceName) -> HeistExecutionEnvironment {
        var targets = self.targets
        targets[parameter] = target
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }

    public func binding(string: String, to parameter: HeistReferenceName) -> HeistExecutionEnvironment {
        var strings = self.strings
        strings[parameter] = string
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }
}

struct HeistReferenceScope: Sendable, Equatable {
    static let empty = HeistReferenceScope()

    var targetRefs: Set<HeistReferenceName> = []
    var stringRefs: Set<HeistReferenceName> = []

    func bindingTarget(_ reference: HeistReferenceName) -> HeistReferenceScope {
        var copy = self
        copy.targetRefs.insert(reference)
        return copy
    }

    func bindingTarget(_ reference: String) -> HeistReferenceScope {
        bindingTarget(HeistReferenceName(rawValue: reference))
    }

    func bindingString(_ reference: HeistReferenceName) -> HeistReferenceScope {
        var copy = self
        copy.stringRefs.insert(reference)
        return copy
    }

    func bindingString(_ reference: String) -> HeistReferenceScope {
        bindingString(HeistReferenceName(rawValue: reference))
    }

    func binding(parameter: HeistParameter) -> HeistReferenceScope {
        guard let reference = parameter.name else { return self }
        switch parameter {
        case .none:
            return self
        case .string:
            return bindingString(reference)
        case .elementTarget:
            return bindingTarget(reference)
        }
    }
}

struct HeistReferenceBindingContext: Sendable, Equatable {
    static let empty = HeistReferenceBindingContext(
        scope: .empty,
        environment: .empty
    )

    let scope: HeistReferenceScope
    let environment: HeistExecutionEnvironment

    init(
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        self.scope = scope
        self.environment = environment
        precondition(
            invariantFailures.isEmpty,
            "Heist reference binding context diverged: \(invariantFailures.joined(separator: "; "))"
        )
    }

    var invariantFailures: [String] {
        var failures: [String] = []
        let environmentTargetRefs = Set(environment.targets.keys)
        if scope.targetRefs != environmentTargetRefs {
            failures.append(
                "target refs scope=\(scope.targetRefs.sortedDescriptions) environment=\(environmentTargetRefs.sortedDescriptions)"
            )
        }
        let environmentStringRefs = Set(environment.strings.keys)
        if scope.stringRefs != environmentStringRefs {
            failures.append(
                "string refs scope=\(scope.stringRefs.sortedDescriptions) environment=\(environmentStringRefs.sortedDescriptions)"
            )
        }
        return failures
    }

    func binding(target: ElementTarget, to parameter: HeistReferenceName) -> HeistReferenceBindingContext {
        HeistReferenceBindingContext(
            scope: scope.bindingTarget(parameter),
            environment: environment.binding(target: target, to: parameter)
        )
    }

    func binding(string: String, to parameter: HeistReferenceName) -> HeistReferenceBindingContext {
        HeistReferenceBindingContext(
            scope: scope.bindingString(parameter),
            environment: environment.binding(string: string, to: parameter)
        )
    }

    func binding(parameter: HeistParameter) -> HeistReferenceBindingContext {
        switch parameter {
        case .none:
            return self
        case .string(let name):
            return binding(string: "__heist_parameter__", to: name)
        case .elementTarget(let name):
            return binding(target: .predicate(.identifier("__heist_parameter__")), to: name)
        }
    }

    func binding(argument: HeistArgument, to parameter: HeistParameter) throws -> HeistReferenceBindingContext {
        HeistReferenceBindingContext(
            scope: scope.binding(parameter: parameter),
            environment: try environment.binding(argument: argument, to: parameter)
        )
    }

    static func runtimeSafetyPlaceholder(for parameter: HeistParameter) -> HeistReferenceBindingContext {
        empty.binding(parameter: parameter)
    }
}

private extension Set where Element == HeistReferenceName {
    var sortedDescriptions: String {
        "[" + map(\.rawValue).sorted().joined(separator: ", ") + "]"
    }
}

public enum HeistExpressionError: Error, Sendable, Equatable, CustomStringConvertible {
    case unresolvedTargetReference(String)
    case unresolvedStringReference(String)
    case emptyReference(String)
    case invalidStringMatch(mode: String)
    case unsupportedHeistActionCommand(String)
    case parameterArgumentMismatch(parameter: HeistParameterKind, argument: HeistParameterKind)

    public var description: String {
        switch self {
        case .unresolvedTargetReference(let reference):
            return "unresolved target reference \"\(reference)\""
        case .unresolvedStringReference(let reference):
            return "unresolved string reference \"\(reference)\""
        case .emptyReference(let type):
            return "\(type) reference must not be empty"
        case .invalidStringMatch(let mode):
            return "\(mode) string match value must not be empty"
        case .unsupportedHeistActionCommand(let command):
            return "unsupported heist action command \"\(command)\""
        case .parameterArgumentMismatch(let parameter, let argument):
            return "heist argument type \(argument.rawValue) does not match parameter type \(parameter.rawValue)"
        }
    }
}

public extension HeistExecutionEnvironment {
    func binding(argument: HeistArgument, to parameter: HeistParameter) throws -> HeistExecutionEnvironment {
        guard argument.kind == parameter.kind else {
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
        switch (parameter, argument) {
        case (.none, .none):
            return self
        case (.string(let name), .string(let value)):
            return binding(string: try value.resolve(in: self), to: name)
        case (.elementTarget(let name), .elementTarget(let target)):
            return binding(target: try target.resolve(in: self), to: name)
        default:
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
    }
}
