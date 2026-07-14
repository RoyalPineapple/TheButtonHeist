import Foundation

// MARK: - Heist Execution Environment

public struct HeistReferenceName: Codable, Hashable, Sendable, Equatable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(stringLiteral value: String) {
        guard let normalized = Self.normalizedValue(value) else {
            preconditionFailure("heist reference must not be empty")
        }
        rawValue = normalized
    }

    public init(validating value: String, type: String = "heist") throws {
        guard let normalized = Self.normalizedValue(value) else {
            throw HeistExpressionError.emptyReference(type)
        }
        rawValue = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let normalized = Self.normalizedValue(value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "reference must not be empty"
            )
        }
        rawValue = normalized
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    package static func normalized(_ value: String) -> HeistReferenceName? {
        normalizedValue(value).map { HeistReferenceName(validated: $0) }
    }

    private static func normalizedValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private init(validated value: String) {
        rawValue = value
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

package struct HeistExecutionEnvironment: Sendable, Equatable {
    package static let empty = HeistExecutionEnvironment()

    package let targets: [HeistReferenceName: ResolvedAccessibilityTarget]
    package let strings: [HeistReferenceName: String]

    package init(
        targets: [HeistReferenceName: ResolvedAccessibilityTarget] = [:],
        strings: [HeistReferenceName: String] = [:]
    ) {
        self.targets = targets
        self.strings = strings
    }

    package func binding(
        target: ResolvedAccessibilityTarget,
        to parameter: HeistReferenceName
    ) -> HeistExecutionEnvironment {
        var targets = self.targets
        targets[parameter] = target
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }

    package func binding(string: String, to parameter: HeistReferenceName) -> HeistExecutionEnvironment {
        var strings = self.strings
        strings[parameter] = string
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }
}

struct HeistReferenceScope: Sendable, Equatable {
    static let empty = HeistReferenceScope()

    var targetRefs: Set<HeistReferenceName> = []
    var stringRefs: Set<HeistReferenceName> = []
}

struct HeistReferenceBinding: Sendable, Equatable {
    enum Value: Sendable, Equatable {
        case string(String)
        case accessibilityTarget(ResolvedAccessibilityTarget)
    }

    static let runtimeSafetyStringPlaceholder = "__heist_parameter__"
    static let runtimeSafetyAccessibilityTargetPlaceholder = ResolvedAccessibilityTarget.predicate(
        .identifier("__heist_parameter__")
    )

    let reference: HeistReferenceName
    let value: Value

    static func runtimeSafetyPlaceholder(for parameter: HeistParameter) -> HeistReferenceBinding? {
        switch parameter {
        case .none:
            return nil
        case .string(let name):
            return HeistReferenceBinding(reference: name, value: .string(runtimeSafetyStringPlaceholder))
        case .accessibilityTarget(let name):
            return HeistReferenceBinding(
                reference: name,
                value: .accessibilityTarget(runtimeSafetyAccessibilityTargetPlaceholder)
            )
        }
    }
}

struct HeistReferenceBindingContext: Sendable, Equatable {
    static let empty = HeistReferenceBindingContext()

    let bindings: [HeistReferenceBinding]

    init(bindings: [HeistReferenceBinding] = []) {
        self.bindings = bindings
    }

    var scope: HeistReferenceScope {
        bindings.reduce(into: .empty) { scope, binding in
            switch binding.value {
            case .string:
                scope.stringRefs.insert(binding.reference)
            case .accessibilityTarget:
                scope.targetRefs.insert(binding.reference)
            }
        }
    }

    var environment: HeistExecutionEnvironment {
        var targets: [HeistReferenceName: ResolvedAccessibilityTarget] = [:]
        var strings: [HeistReferenceName: String] = [:]
        for binding in bindings {
            switch binding.value {
            case .string(let value):
                strings[binding.reference] = value
            case .accessibilityTarget(let target):
                targets[binding.reference] = target
            }
        }
        return HeistExecutionEnvironment(targets: targets, strings: strings)
    }

    var invariantFailures: [String] {
        var failures: [String] = []
        let projectedScope = scope
        let projectedEnvironment = environment
        let environmentTargetRefs = Set(projectedEnvironment.targets.keys)
        if projectedScope.targetRefs != environmentTargetRefs {
            failures.append(
                "target refs scope=\(projectedScope.targetRefs.sortedDescriptions) environment=\(environmentTargetRefs.sortedDescriptions)"
            )
        }
        let environmentStringRefs = Set(projectedEnvironment.strings.keys)
        if projectedScope.stringRefs != environmentStringRefs {
            failures.append(
                "string refs scope=\(projectedScope.stringRefs.sortedDescriptions) environment=\(environmentStringRefs.sortedDescriptions)"
            )
        }
        return failures
    }

    func binding(
        target: ResolvedAccessibilityTarget,
        to parameter: HeistReferenceName
    ) -> HeistReferenceBindingContext {
        binding(HeistReferenceBinding(reference: parameter, value: .accessibilityTarget(target)))
    }

    func binding(string: String, to parameter: HeistReferenceName) -> HeistReferenceBindingContext {
        binding(HeistReferenceBinding(reference: parameter, value: .string(string)))
    }

    func binding(parameter: HeistParameter) -> HeistReferenceBindingContext {
        guard let binding = HeistReferenceBinding.runtimeSafetyPlaceholder(for: parameter) else { return self }
        return self.binding(binding)
    }

    func binding(argument: HeistArgument, to parameter: HeistParameter) throws -> HeistReferenceBindingContext {
        guard argument.kind == parameter.kind else {
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
        switch (parameter, argument.core) {
        case (.none, .none):
            return self
        case (.string(let name), .string(let value)):
            return binding(string: try value.resolve(in: environment), to: name)
        case (.accessibilityTarget(let name), .accessibilityTarget(let target)):
            return binding(target: try target.resolve(in: environment), to: name)
        default:
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
    }

    static func runtimeSafetyPlaceholder(for parameter: HeistParameter) -> HeistReferenceBindingContext {
        empty.binding(parameter: parameter)
    }

    private func binding(_ binding: HeistReferenceBinding) -> HeistReferenceBindingContext {
        HeistReferenceBindingContext(bindings: bindings + [binding])
    }
}

extension HeistPlan {
    var parameterReferenceBindings: HeistReferenceBindingContext {
        HeistReferenceBindingContext.runtimeSafetyPlaceholder(for: parameter)
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

package extension HeistExecutionEnvironment {
    func binding(argument: HeistArgument, to parameter: HeistParameter) throws -> HeistExecutionEnvironment {
        guard argument.kind == parameter.kind else {
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
        switch (parameter, argument.core) {
        case (.none, .none):
            return self
        case (.string(let name), .string(let value)):
            return binding(string: try value.resolve(in: self), to: name)
        case (.accessibilityTarget(let name), .accessibilityTarget(let target)):
            return binding(target: try target.resolve(in: self), to: name)
        default:
            throw HeistExpressionError.parameterArgumentMismatch(parameter: parameter.kind, argument: argument.kind)
        }
    }
}
