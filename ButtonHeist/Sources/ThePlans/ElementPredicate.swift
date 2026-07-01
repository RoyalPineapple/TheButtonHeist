import Foundation

// MARK: - String Matching

public protocol StringMatchPayload: Sendable, Equatable, Hashable {
    /// Literal emptiness when it is knowable without resolving runtime refs.
    var stringMatchLiteralIsEmpty: Bool? { get }
}

extension String: StringMatchPayload {
    public var stringMatchLiteralIsEmpty: Bool? { isEmpty }
}

/// Shared representation for predicate string comparison.
///
/// Literal Swift values create exact matches. Public JSON boundaries spell the
/// selected mode explicitly through their request schema.
public enum StringMatch<Value: StringMatchPayload>: Sendable, Equatable, Hashable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Exact string match. This is the default for string literals.
        case exact
        /// Explicit substring match. Authors opt into this broad match mode.
        case contains
        /// Explicit prefix match.
        case prefix
        /// Explicit suffix match.
        case suffix
    }

    case exact(Value)
    case contains(Value)
    case prefix(Value)
    case suffix(Value)

    public init(_ value: Value) {
        self = .exact(value)
    }

    public init(mode: Mode, value: Value) {
        switch mode {
        case .exact:
            self = .exact(value)
        case .contains:
            self = .contains(value)
        case .prefix:
            self = .prefix(value)
        case .suffix:
            self = .suffix(value)
        }
    }

    public var mode: Mode {
        switch self {
        case .exact:
            return .exact
        case .contains:
            return .contains
        case .prefix:
            return .prefix
        case .suffix:
            return .suffix
        }
    }

    public var value: Value {
        switch self {
        case .exact(let value), .contains(let value), .prefix(let value), .suffix(let value):
            return value
        }
    }

    public var isExact: Bool {
        mode == .exact
    }

    public var hasInvalidEmptyBroadLiteral: Bool {
        mode != .exact && value.stringMatchLiteralIsEmpty == true
    }

    public var hasPredicateLiteral: Bool {
        value.stringMatchLiteralIsEmpty != true
    }

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> StringMatch<NewValue> {
        try StringMatch<NewValue>(
            mode: StringMatch<NewValue>.Mode(rawValue: self.mode.rawValue) ?? .exact,
            value: transform(value)
        )
    }
}

extension StringMatch: ExpressibleByUnicodeScalarLiteral
where Value: ExpressibleByStringLiteral, Value.StringLiteralType == String {
    public init(unicodeScalarLiteral value: String) {
        self = .exact(Value(stringLiteral: value))
    }
}

extension StringMatch: ExpressibleByExtendedGraphemeClusterLiteral
where Value: ExpressibleByStringLiteral, Value.StringLiteralType == String {
    public init(extendedGraphemeClusterLiteral value: String) {
        self = .exact(Value(stringLiteral: value))
    }
}

extension StringMatch: ExpressibleByStringLiteral where Value: ExpressibleByStringLiteral, Value.StringLiteralType == String {
    public init(stringLiteral value: String) {
        self = .exact(Value(stringLiteral: value))
    }
}

extension StringMatch: Codable where Value: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case mode, value
    }

    private enum ExactReferenceCodingKeys: String, CodingKey {
        case ref
    }

    public init(from decoder: Decoder) throws {
        if Value.self == StringExpr.self,
           let referenceContainer = try? decoder.container(keyedBy: ExactReferenceCodingKeys.self),
           referenceContainer.contains(.ref) {
            self = .exact(try Value(from: decoder))
            return
        }

        if let exactValue = try? decoder.singleValueContainer().decode(Value.self) {
            self = .exact(exactValue)
            return
        }

        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "string match")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(Mode.self, forKey: .mode)
        let value = try container.decode(Value.self, forKey: .value)
        self = StringMatch(mode: mode, value: value)
        if hasInvalidEmptyBroadLiteral {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "\(mode.rawValue) string match value must not be empty"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        if case .exact(let value) = self {
            var container = encoder.singleValueContainer()
            try container.encode(value)
            return
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(value, forKey: .value)
    }
}

extension StringMatch: CustomStringConvertible {
    public var description: String {
        switch self {
        case .exact(let value):
            return String(describing: value)
        case .contains(let value):
            return "contains(\(value))"
        case .prefix(let value):
            return "prefix(\(value))"
        case .suffix(let value):
            return "suffix(\(value))"
        }
    }
}

public extension StringMatch where Value == String {
    func matches(_ candidate: String) -> Bool {
        guard !value.isEmpty else { return false }
        switch self {
        case .exact(let pattern):
            return ElementPredicate.stringEquals(candidate, pattern)
        case .contains(let pattern):
            return ElementPredicate.stringContains(candidate, pattern)
        case .prefix(let pattern):
            return ElementPredicate.stringHasPrefix(candidate, pattern)
        case .suffix(let pattern):
            return ElementPredicate.stringHasSuffix(candidate, pattern)
        }
    }

}

public extension StringMatch where Value: Codable {
    static func decodeOneOrMany<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> [Self] {
        guard container.contains(key) else { return [] }
        let decoder = try container.superDecoder(forKey: key)
        if (try? decoder.unkeyedContainer()) != nil {
            return try [Self](from: decoder)
        }
        return [try Self(from: decoder)]
    }

    static func encodeOneOrMany<Key: CodingKey>(
        _ matches: [Self],
        to container: inout KeyedEncodingContainer<Key>,
        forKey key: Key
    ) throws {
        switch matches.count {
        case 0:
            break
        case 1:
            try container.encode(matches[0], forKey: key)
        default:
            try container.encode(matches, forKey: key)
        }
    }
}

public enum ElementPredicateCheck<Value: StringMatchPayload>: Sendable, Equatable, Hashable {
    case label(StringMatch<Value>)
    case identifier(StringMatch<Value>)
    case value(StringMatch<Value>)
    case traits(Set<HeistTrait>)
    case excludeTraits(Set<HeistTrait>)

    public var hasPredicateLiteral: Bool {
        switch self {
        case .label(let match), .identifier(let match), .value(let match):
            return match.hasPredicateLiteral
        case .traits(let traits), .excludeTraits(let traits):
            return !traits.isEmpty
        }
    }

    public func map<NewValue: StringMatchPayload>(
        _ transform: (Value) throws -> NewValue
    ) rethrows -> ElementPredicateCheck<NewValue> {
        switch self {
        case .label(let match):
            return try .label(match.map(transform))
        case .identifier(let match):
            return try .identifier(match.map(transform))
        case .value(let match):
            return try .value(match.map(transform))
        case .traits(let traits):
            return .traits(traits)
        case .excludeTraits(let traits):
            return .excludeTraits(traits)
        }
    }
}

// MARK: - Element Predicate

/// The canonical predicate for matching a single accessibility element.
///
/// Predicates are ordered check chains. Matching is equivalent to `&&` over the
/// checks; diagnostics can use the same order to explain where a candidate first
/// failed.
public struct ElementPredicate: Sendable, Equatable, Hashable {
    /// Ordered checks against one accessibility element. All checks must pass.
    public let checks: [ElementPredicateCheck<String>]

    public init(_ checks: [ElementPredicateCheck<String>] = []) {
        self.checks = checks
    }

    public init(
        label: StringMatch<String>? = nil,
        identifier: StringMatch<String>? = nil,
        value: StringMatch<String>? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) {
        self.init(Self.checks(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            excludeTraits: excludeTraits
        ))
    }

    public init(
        _ checks: [ElementPredicateCheck<String>],
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) {
        self.init(checks + Self.traitChecks(traits: traits, excludeTraits: excludeTraits))
    }

    /// Whether any predicate is set. Empty string and empty trait collection
    /// checks are treated as unset: they match nothing rather than everything.
    public var hasPredicates: Bool {
        checks.contains { $0.hasPredicateLiteral }
    }

    /// Returns `self` when at least one predicate field is set, else `nil`.
    public var nonEmpty: Self? { hasPredicates ? self : nil }

    private static func checks(
        label: StringMatch<String>?,
        identifier: StringMatch<String>?,
        value: StringMatch<String>?,
        traits: [HeistTrait],
        excludeTraits: [HeistTrait]
    ) -> [ElementPredicateCheck<String>] {
        var checks: [ElementPredicateCheck<String>] = []
        if let label { checks.append(.label(label)) }
        if let identifier { checks.append(.identifier(identifier)) }
        if let value { checks.append(.value(value)) }
        checks += traitChecks(traits: traits, excludeTraits: excludeTraits)
        return checks
    }

    private static func traitChecks(
        traits: [HeistTrait],
        excludeTraits: [HeistTrait]
    ) -> [ElementPredicateCheck<String>] {
        var checks: [ElementPredicateCheck<String>] = []
        let traits = traits.heistTraitSet
        let excludeTraits = excludeTraits.heistTraitSet
        if !traits.isEmpty { checks.append(.traits(traits)) }
        if !excludeTraits.isEmpty { checks.append(.excludeTraits(excludeTraits)) }
        return checks
    }
}

// MARK: - Convenience Constructors

public extension ElementPredicate {
    /// Match by exact label.
    static func label(_ label: String) -> ElementPredicate {
        ElementPredicate(label: StringMatch(label))
    }

    /// Match by label alone.
    static func label(_ label: StringMatch<String>) -> ElementPredicate {
        ElementPredicate(label: label)
    }

    /// Match by exact accessibility identifier.
    static func identifier(_ identifier: String) -> ElementPredicate {
        ElementPredicate(identifier: StringMatch(identifier))
    }

    /// Match by accessibility identifier alone.
    static func identifier(_ identifier: StringMatch<String>) -> ElementPredicate {
        ElementPredicate(identifier: identifier)
    }

    /// Match by exact value.
    static func value(_ value: String) -> ElementPredicate {
        ElementPredicate(value: StringMatch(value))
    }

    /// Match by value alone.
    static func value(_ value: StringMatch<String>) -> ElementPredicate {
        ElementPredicate(value: value)
    }

    /// Match elements that include every listed trait.
    static func traits(_ traits: [HeistTrait]) -> ElementPredicate {
        ElementPredicate(traits: traits)
    }

    /// Match elements that include none of the listed traits.
    static func excludeTraits(_ traits: [HeistTrait]) -> ElementPredicate {
        ElementPredicate(excludeTraits: traits)
    }

    /// Match by an ordered list of property checks. Repeating a property means
    /// every check against that property must pass.
    static func element(
        _ checks: ElementPredicateCheck<String>...,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> ElementPredicate {
        ElementPredicate(checks, traits: traits, excludeTraits: excludeTraits)
    }
}

// MARK: - Evaluation

/// A value that an `ElementPredicate` can be evaluated against. The string
/// fields are read directly; trait inclusion/exclusion is delegated so each
/// subject keeps its own trait representation (client `Set<HeistTrait>` vs
/// server UIKit bitmask) while the predicate walk lives in one place.
package protocol ElementPredicateSubject {
    var predicateLabel: String? { get }
    var predicateIdentifier: String? { get }
    var predicateValue: String? { get }
    /// True when every required trait is present (and known) on the subject.
    func satisfiesRequiredTraits(_ required: Set<HeistTrait>) -> Bool
    /// True when any excluded trait is present (or unknown) on the subject —
    /// i.e. the subject should be rejected.
    func violatesExcludedTraits(_ excluded: Set<HeistTrait>) -> Bool
}

package extension ElementPredicate {
    /// The single source of truth for predicate evaluation.
    func matches(_ subject: some ElementPredicateSubject) -> Bool {
        guard hasPredicates else { return false }
        return checks.allSatisfy { $0.matches(subject) }
    }

}

// MARK: - Codable

extension ElementPredicate: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decodeIfPresent([ElementPredicateCheck<String>].self, forKey: .checks) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !checks.isEmpty { try container.encode(checks, forKey: .checks) }
    }

}

extension ElementPredicate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("predicate", checks.compactMap(ScoreDescription.predicateCheckField))
    }
}

extension ElementPredicateCheck: Codable where Value: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, match, values
    }

    package enum Kind: String, Codable, CaseIterable {
        case label, identifier, value, traits, excludeTraits
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate check")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .label:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .label)
            self = .label(try container.decode(StringMatch<Value>.self, forKey: .match))
        case .identifier:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .identifier)
            self = .identifier(try container.decode(StringMatch<Value>.self, forKey: .match))
        case .value:
            try Self.rejectIrrelevantField(.values, in: container, forKind: .value)
            self = .value(try container.decode(StringMatch<Value>.self, forKey: .match))
        case .traits:
            try Self.rejectIrrelevantField(.match, in: container, forKind: .traits)
            self = .traits(try container.decode([HeistTrait].self, forKey: .values).heistTraitSet)
        case .excludeTraits:
            try Self.rejectIrrelevantField(.match, in: container, forKind: .excludeTraits)
            self = .excludeTraits(try container.decode([HeistTrait].self, forKey: .values).heistTraitSet)
        }
    }

    private static func rejectIrrelevantField(
        _ key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>,
        forKind kind: Kind
    ) throws {
        guard container.contains(key) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(key.stringValue) is not valid for \(kind.rawValue) element predicate checks"
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .label(let match):
            try container.encode(Kind.label, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .identifier(let match):
            try container.encode(Kind.identifier, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .value(let match):
            try container.encode(Kind.value, forKey: .kind)
            try container.encode(match, forKey: .match)
        case .traits(let traits):
            try container.encode(Kind.traits, forKey: .kind)
            try container.encode(traits.canonicalHeistTraitArray, forKey: .values)
        case .excludeTraits(let traits):
            try container.encode(Kind.excludeTraits, forKey: .kind)
            try container.encode(traits.canonicalHeistTraitArray, forKey: .values)
        }
    }
}

package extension ElementPredicateCheck where Value == String {
    func matches(_ subject: some ElementPredicateSubject) -> Bool {
        switch self {
        case .label(let match):
            guard let candidate = subject.predicateLabel else { return false }
            return match.matches(candidate)
        case .identifier(let match):
            guard let candidate = subject.predicateIdentifier else { return false }
            return match.matches(candidate)
        case .value(let match):
            guard let candidate = subject.predicateValue else { return false }
            return match.matches(candidate)
        case .traits(let traits):
            return traits.isEmpty || subject.satisfiesRequiredTraits(traits)
        case .excludeTraits(let traits):
            return traits.isEmpty || !subject.violatesExcludedTraits(traits)
        }
    }
}

// MARK: - String Comparison (canonical, shared by client and server)

public extension ElementPredicate {
    /// Case-insensitive equality with typography folding. The canonical
    /// exact-or-miss comparison shared by client-side and server-side matching.
    static func stringEquals(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveCompare(normalizeTypography(pattern)) == .orderedSame
    }

    /// Case-insensitive substring with typography folding. Used by explicit
    /// `.contains` predicates and by diagnostic near-miss search.
    static func stringContains(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveContains(normalizeTypography(pattern))
    }

    static func stringHasPrefix(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .range(of: normalizeTypography(pattern), options: [.anchored, .caseInsensitive]) != nil
    }

    static func stringHasSuffix(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .range(of: normalizeTypography(pattern), options: [.anchored, .backwards, .caseInsensitive]) != nil
    }

    /// Fold typographic punctuation that has an ASCII equivalent.
    static func normalizeTypography(_ string: String) -> String {
        guard string.unicodeScalars.contains(where: { typographicAsciiFold[$0] != nil }) else {
            return string
        }
        var result = ""
        result.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            if let replacement = typographicAsciiFold[scalar] {
                result.append(replacement)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
    private static let typographicAsciiFold: [Unicode.Scalar: String] = [
        // Single quotes / apostrophes
        "\u{2018}": "'",
        "\u{2019}": "'",
        "\u{201A}": "'",
        "\u{201B}": "'",
        "\u{2032}": "'",
        // Double quotes
        "\u{201C}": "\"",
        "\u{201D}": "\"",
        "\u{201E}": "\"",
        "\u{201F}": "\"",
        "\u{2033}": "\"",
        // Dashes / hyphens
        "\u{2010}": "-",
        "\u{2011}": "-",
        "\u{2012}": "-",
        "\u{2013}": "-",
        "\u{2014}": "-",
        "\u{2015}": "-",
        "\u{2212}": "-",
        // Ellipsis
        "\u{2026}": "...",
        // Non-breaking / typographic spaces
        "\u{00A0}": " ",
        "\u{2007}": " ",
        "\u{202F}": " ",
    ]
}
