import Foundation

// MARK: - Expression Phases

/// The only unresolved leaf representation in ThePlans.
package enum Expr<Value> {
    case literal(Value)
    case ref(HeistReferenceName)

    package func map<NewValue>(_ transform: (Value) throws -> NewValue) rethrows -> Expr<NewValue> {
        switch self {
        case .literal(let value):
            return try .literal(transform(value))
        case .ref(let reference):
            return .ref(reference)
        }
    }
}

extension Expr: Sendable where Value: Sendable {}
extension Expr: Equatable where Value: Equatable {}
extension Expr: Hashable where Value: Hashable {}

package struct InvalidResolvedPredicateError: Error, Sendable, Equatable, CustomStringConvertible {
    package let reason: String

    package var description: String {
        "resolved predicate is invalid: \(reason)"
    }
}

extension Expr: Codable where Value: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ref
    }

    package init(from decoder: Decoder) throws {
        if let literal = try? decoder.singleValueContainer().decode(Value.self) {
            self = .literal(literal)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "expression")
        self = .ref(try HeistReferenceName.decode(from: container, forKey: .ref, type: "string"))
    }

    package func encode(to encoder: Encoder) throws {
        switch self {
        case .literal(let literal):
            var container = encoder.singleValueContainer()
            try container.encode(literal)
        case .ref(let reference):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(reference, forKey: .ref)
        }
    }
}

package extension Expr where Value == String {
    func resolve(in environment: HeistExecutionEnvironment) throws -> String {
        switch self {
        case .literal(let literal):
            return literal
        case .ref(let reference):
            guard let string = environment.strings[reference] else {
                throw HeistExpressionError.unresolvedStringReference(reference.rawValue)
            }
            return string
        }
    }
}

extension Expr: CustomStringConvertible where Value == String {
    package var description: String {
        switch self {
        case .literal(let literal):
            return ScoreDescription.quoted(literal)
        case .ref(let reference):
            return ScoreDescription.call("stringRef", [ScoreDescription.quoted(reference.rawValue)])
        }
    }
}

// MARK: - String Match Core

package protocol StringMatchLeaf {
    var stringMatchLiteralIsEmpty: Bool? { get }
}

extension String: StringMatchLeaf {
    package var stringMatchLiteralIsEmpty: Bool? { isEmpty }
}

extension Expr: StringMatchLeaf where Value == String {
    package var stringMatchLiteralIsEmpty: Bool? {
        switch self {
        case .literal(let value):
            return value.isEmpty
        case .ref:
            return nil
        }
    }
}

package enum StringMatchCore<Value> {
    case exact(Value)
    case contains(Value)
    case prefix(Value)
    case suffix(Value)
    case isEmpty

    package var mode: StringMatch.Mode {
        switch self {
        case .exact:
            return .exact
        case .contains:
            return .contains
        case .prefix:
            return .prefix
        case .suffix:
            return .suffix
        case .isEmpty:
            return .isEmpty
        }
    }

    package var payload: Value? {
        switch self {
        case .exact(let value), .contains(let value), .prefix(let value), .suffix(let value):
            return value
        case .isEmpty:
            return nil
        }
    }

    package func map<NewValue>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> StringMatchCore<NewValue> {
        switch self {
        case .exact(let value):
            return try .exact(transform(value))
        case .contains(let value):
            return try .contains(transform(value))
        case .prefix(let value):
            return try .prefix(transform(value))
        case .suffix(let value):
            return try .suffix(transform(value))
        case .isEmpty:
            return .isEmpty
        }
    }
}

extension StringMatchCore: Sendable where Value: Sendable {}
extension StringMatchCore: Equatable where Value: Equatable {}
extension StringMatchCore: Hashable where Value: Hashable {}

package extension StringMatchCore where Value: StringMatchLeaf {
    var invalidEmptyBroadMode: StringMatch.Mode? {
        hasInvalidEmptyBroadLiteral ? mode : nil
    }

    var hasInvalidEmptyBroadLiteral: Bool {
        switch self {
        case .contains(let value), .prefix(let value), .suffix(let value):
            return value.stringMatchLiteralIsEmpty == true
        case .exact, .isEmpty:
            return false
        }
    }

    var hasPredicateLiteral: Bool {
        payload?.stringMatchLiteralIsEmpty != true
    }
}

extension StringMatchCore: Codable where Value: Codable & StringMatchLeaf {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode, value
    }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "string match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(StringMatch.Mode.self, forKey: .mode)
        if mode == .isEmpty {
            if container.contains(.value) {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "isEmpty string match must not include value"
                )
            }
            self = .isEmpty
            return
        }
        let value = try container.decode(Value.self, forKey: .value)
        self = Self(mode: mode, value: value)
        if hasInvalidEmptyBroadLiteral {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "\(mode.rawValue) string match value must not be empty"
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        if let payload {
            try container.encode(payload, forKey: .value)
        }
    }

    private init(mode: StringMatch.Mode, value: Value) {
        switch mode {
        case .exact:
            self = .exact(value)
        case .contains:
            self = .contains(value)
        case .prefix:
            self = .prefix(value)
        case .suffix:
            self = .suffix(value)
        case .isEmpty:
            self = .isEmpty
        }
    }
}

extension StringMatchCore: CustomStringConvertible {
    package var description: String {
        switch self {
        case .exact(let value):
            return String(describing: value)
        case .contains(let value):
            return "contains(\(value))"
        case .prefix(let value):
            return "prefix(\(value))"
        case .suffix(let value):
            return "suffix(\(value))"
        case .isEmpty:
            return "isEmpty"
        }
    }
}

// MARK: - Authored String Match

/// A string match that accepts literals or typed references.
public struct StringMatch: Codable, Sendable, Equatable, Hashable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case exact
        case contains
        case prefix
        case suffix
        case isEmpty
    }

    package let core: StringMatchCore<Expr<String>>

    package init(core: StringMatchCore<Expr<String>>) {
        self.core = core
    }

    public init(_ value: String) {
        core = .exact(.literal(value))
    }

    public static func exact(_ value: String) -> Self {
        Self(core: .exact(.literal(value)))
    }

    @_disfavoredOverload
    public static func exact(_ reference: HeistReferenceName) -> Self {
        Self(core: .exact(.ref(reference)))
    }

    public static func contains(_ value: String) -> Self {
        Self(core: .contains(.literal(value)))
    }

    @_disfavoredOverload
    public static func contains(_ reference: HeistReferenceName) -> Self {
        Self(core: .contains(.ref(reference)))
    }

    public static func prefix(_ value: String) -> Self {
        Self(core: .prefix(.literal(value)))
    }

    @_disfavoredOverload
    public static func prefix(_ reference: HeistReferenceName) -> Self {
        Self(core: .prefix(.ref(reference)))
    }

    public static func suffix(_ value: String) -> Self {
        Self(core: .suffix(.literal(value)))
    }

    @_disfavoredOverload
    public static func suffix(_ reference: HeistReferenceName) -> Self {
        Self(core: .suffix(.ref(reference)))
    }

    public static var isEmpty: Self {
        Self(core: .isEmpty)
    }

    public var mode: Mode { core.mode }

    public init(from decoder: Decoder) throws {
        core = try StringMatchCore(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try core.encode(to: encoder)
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedStringMatch {
        let resolved = try core.map { try $0.resolve(in: environment) }
        if resolved.hasInvalidEmptyBroadLiteral {
            throw HeistExpressionError.invalidStringMatch(mode: resolved.mode.rawValue)
        }
        return ResolvedStringMatch(core: resolved)
    }
}

extension StringMatch: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension StringMatch: CustomStringConvertible {
    public var description: String { core.description }
}

package struct ResolvedStringMatch: Sendable, Equatable, Hashable {
    package let core: StringMatchCore<String>

    package init(core: StringMatchCore<String>) {
        self.core = core
    }

    package func matches(optional candidate: String?) -> Bool {
        if case .isEmpty = core {
            return (candidate ?? "").isEmpty
        }
        guard let candidate else { return false }
        return matches(candidate)
    }

    package func matches(_ candidate: String) -> Bool {
        switch core {
        case .exact(let pattern):
            return !pattern.isEmpty && ElementPredicate.stringEquals(candidate, pattern)
        case .contains(let pattern):
            return !pattern.isEmpty && ElementPredicate.stringContains(candidate, pattern)
        case .prefix(let pattern):
            return !pattern.isEmpty && ElementPredicate.stringHasPrefix(candidate, pattern)
        case .suffix(let pattern):
            return !pattern.isEmpty && ElementPredicate.stringHasSuffix(candidate, pattern)
        case .isEmpty:
            return candidate.isEmpty
        }
    }
}
