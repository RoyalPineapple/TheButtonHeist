import Foundation

/// A string literal or typed reference awaiting plan resolution.
package enum AuthoredString: Codable, Sendable, Equatable, Hashable {
    case literal(String)
    case ref(HeistReferenceName)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case ref
    }

    package init(from decoder: Decoder) throws {
        if let literal = try? decoder.singleValueContainer().decode(String.self) {
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

    package func resolve(in environment: HeistExecutionEnvironment) throws -> String {
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

    package var literalIsEmpty: Bool? {
        guard case .literal(let value) = self else { return nil }
        return value.isEmpty
    }
}

extension AuthoredString: CustomStringConvertible {
    package var description: String {
        switch self {
        case .literal(let literal):
            return CanonicalValueDescription.quoted(literal)
        case .ref(let reference):
            return CanonicalValueDescription.call("stringRef", [CanonicalValueDescription.quoted(reference.rawValue)])
        }
    }
}

package struct InvalidResolvedPredicateError: Error, Sendable, Equatable, CustomStringConvertible {
    package let reason: String

    package var description: String {
        "resolved predicate is invalid: \(reason)"
    }
}

/// A string match that accepts literals or typed references.
public struct StringMatch: Codable, Sendable, Equatable, Hashable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        case exact
        case contains
        case prefix
        case suffix
        case isEmpty
    }

    package let mode: Mode
    package let value: AuthoredString?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode, value
    }

    package init(mode: Mode, value: AuthoredString?) {
        self.mode = mode
        self.value = value
    }

    public init(_ value: String) {
        self.init(mode: .exact, value: .literal(value))
    }

    public static func exact(_ value: String) -> Self {
        Self(mode: .exact, value: .literal(value))
    }

    @_disfavoredOverload
    public static func exact(_ reference: HeistReferenceName) -> Self {
        Self(mode: .exact, value: .ref(reference))
    }

    public static func contains(_ value: String) -> Self {
        Self(mode: .contains, value: .literal(value))
    }

    @_disfavoredOverload
    public static func contains(_ reference: HeistReferenceName) -> Self {
        Self(mode: .contains, value: .ref(reference))
    }

    public static func prefix(_ value: String) -> Self {
        Self(mode: .prefix, value: .literal(value))
    }

    @_disfavoredOverload
    public static func prefix(_ reference: HeistReferenceName) -> Self {
        Self(mode: .prefix, value: .ref(reference))
    }

    public static func suffix(_ value: String) -> Self {
        Self(mode: .suffix, value: .literal(value))
    }

    @_disfavoredOverload
    public static func suffix(_ reference: HeistReferenceName) -> Self {
        Self(mode: .suffix, value: .ref(reference))
    }

    public static var isEmpty: Self {
        Self(mode: .isEmpty, value: nil)
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "string match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(Mode.self, forKey: .mode)
        if mode == .isEmpty {
            if container.contains(.value) {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "isEmpty string match must not include value"
                )
            }
            value = nil
            return
        }
        value = try container.decode(AuthoredString.self, forKey: .value)
        if hasInvalidEmptyBroadLiteral {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "\(mode.rawValue) string match value must not be empty"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(value, forKey: .value)
    }

    package var hasInvalidEmptyBroadLiteral: Bool {
        mode != .exact && mode != .isEmpty && value?.literalIsEmpty == true
    }

    package var hasPredicateLiteral: Bool {
        value?.literalIsEmpty != true
    }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedStringMatch {
        let resolvedValue = try value?.resolve(in: environment)
        if mode != .exact, mode != .isEmpty, resolvedValue?.isEmpty == true {
            throw HeistExpressionError.invalidStringMatch(mode: mode.rawValue)
        }
        return ResolvedStringMatch(mode: mode, value: resolvedValue)
    }
}

extension StringMatch: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension StringMatch: CustomStringConvertible {
    public var description: String {
        switch mode {
        case .exact:
            return value?.description ?? "isEmpty"
        case .contains:
            return "contains(\(value?.description ?? ""))"
        case .prefix:
            return "prefix(\(value?.description ?? ""))"
        case .suffix:
            return "suffix(\(value?.description ?? ""))"
        case .isEmpty:
            return "isEmpty"
        }
    }
}

package struct ResolvedStringMatch: Codable, Sendable, Equatable, Hashable {
    package let mode: StringMatch.Mode
    package let value: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode, value
    }

    package init(mode: StringMatch.Mode, value: String?) {
        self.mode = mode
        self.value = value
    }

    package static func exact(_ value: String) -> Self {
        Self(mode: .exact, value: value)
    }

    package init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "string match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(StringMatch.Mode.self, forKey: .mode)
        if mode == .isEmpty {
            if container.contains(.value) {
                throw DecodingError.dataCorruptedError(
                    forKey: .value,
                    in: container,
                    debugDescription: "isEmpty string match must not include value"
                )
            }
            value = nil
            return
        }
        value = try container.decode(String.self, forKey: .value)
        if mode != .exact, value?.isEmpty == true {
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
        try container.encodeIfPresent(value, forKey: .value)
    }

    package var hasPredicateLiteral: Bool {
        value?.isEmpty != true
    }

    package var invalidEmptyBroadMode: StringMatch.Mode? {
        mode != .exact && mode != .isEmpty && value?.isEmpty == true ? mode : nil
    }

    package func matches(optional candidate: String?) -> Bool {
        if mode == .isEmpty {
            return (candidate ?? "").isEmpty
        }
        guard let candidate else { return false }
        return matches(candidate)
    }

    package func matches(_ candidate: String) -> Bool {
        switch mode {
        case .exact:
            return value.map { !$0.isEmpty && ElementPredicate.stringEquals(candidate, $0) } ?? false
        case .contains:
            return value.map { !$0.isEmpty && ElementPredicate.stringContains(candidate, $0) } ?? false
        case .prefix:
            return value.map { !$0.isEmpty && ElementPredicate.stringHasPrefix(candidate, $0) } ?? false
        case .suffix:
            return value.map { !$0.isEmpty && ElementPredicate.stringHasSuffix(candidate, $0) } ?? false
        case .isEmpty:
            return candidate.isEmpty
        }
    }
}

extension ResolvedStringMatch: CustomStringConvertible {
    package var description: String {
        switch mode {
        case .exact:
            return value.map(CanonicalValueDescription.quoted) ?? "isEmpty"
        case .contains:
            return "contains(\(value.map(CanonicalValueDescription.quoted) ?? ""))"
        case .prefix:
            return "prefix(\(value.map(CanonicalValueDescription.quoted) ?? ""))"
        case .suffix:
            return "suffix(\(value.map(CanonicalValueDescription.quoted) ?? ""))"
        case .isEmpty:
            return "isEmpty"
        }
    }
}
