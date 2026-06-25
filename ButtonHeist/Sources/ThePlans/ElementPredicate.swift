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
/// Exact matching is the default and retains the legacy flat JSON form:
/// `"label": "Pay"` decodes as `.exact("Pay")`. Broader modes use object
/// form: `"label": {"mode":"contains","value":"Send"}`.
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

    public init(from decoder: Decoder) throws {
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

// MARK: - Element Predicate

/// The canonical predicate for matching a single accessibility element.
///
/// String fields (`label`, `identifier`, `value`) use `StringMatch`; exact
/// matching is the default for legacy `.label("Pay")`-style construction.
/// Trait fields use exact bitmask comparison. Specificity is expressed entirely
/// by which fields are set — there is no separate scope or query system.
public struct ElementPredicate: Sendable, Equatable, Hashable {
    /// Match against element label.
    public var label: StringMatch<String>?
    /// Match against accessibility identifier.
    public var identifier: StringMatch<String>?
    /// Match against element value.
    public var value: StringMatch<String>?
    /// All listed traits must be present on the element.
    public var traits: [HeistTrait]
    /// None of the listed traits may be present on the element.
    public var excludeTraits: [HeistTrait]

    public init(
        label: StringMatch<String>? = nil,
        identifier: StringMatch<String>? = nil,
        value: StringMatch<String>? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) {
        self.label = label
        self.identifier = identifier
        self.value = value
        self.traits = traits
        self.excludeTraits = excludeTraits
    }

    public var hasTraitPredicates: Bool {
        !traits.isEmpty || !excludeTraits.isEmpty
    }

    /// Whether any property predicate is set. Empty strings are treated as
    /// unset: they match nothing rather than everything.
    public var hasPredicates: Bool {
        label?.hasPredicateLiteral == true || identifier?.hasPredicateLiteral == true ||
            value?.hasPredicateLiteral == true || hasTraitPredicates
    }

    /// Returns `self` when at least one predicate field is set, else `nil`.
    public var nonEmpty: Self? { hasPredicates ? self : nil }
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

    /// Match by any combination of fields — the canonical multi-field form.
    static func element(
        label: StringMatch<String>? = nil,
        identifier: StringMatch<String>? = nil,
        value: StringMatch<String>? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) -> ElementPredicate {
        ElementPredicate(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            excludeTraits: excludeTraits
        )
    }
}

// MARK: - Evaluation

/// A value that an `ElementPredicate` can be evaluated against. The string
/// fields are read directly; trait inclusion/exclusion is delegated so each
/// subject keeps its own trait representation (client `Set<HeistTrait>` vs
/// server UIKit bitmask) while the predicate walk lives in one place.
public protocol ElementPredicateSubject {
    var predicateLabel: String? { get }
    var predicateIdentifier: String? { get }
    var predicateValue: String? { get }
    /// True when every required trait is present (and known) on the subject.
    func satisfiesRequiredTraits(_ required: [HeistTrait]) -> Bool
    /// True when any excluded trait is present (or unknown) on the subject —
    /// i.e. the subject should be rejected.
    func violatesExcludedTraits(_ excluded: [HeistTrait]) -> Bool
}

public extension ElementPredicate {
    /// The single source of truth for predicate evaluation.
    func matches(_ subject: some ElementPredicateSubject) -> Bool {
        guard hasPredicates else { return false }
        if let label {
            guard let candidate = subject.predicateLabel, label.matches(candidate) else { return false }
        }
        if let identifier {
            guard let candidate = subject.predicateIdentifier, identifier.matches(candidate) else { return false }
        }
        if let value {
            guard let candidate = subject.predicateValue, value.matches(candidate) else { return false }
        }
        if !traits.isEmpty, !subject.satisfiesRequiredTraits(traits) { return false }
        if !excludeTraits.isEmpty, subject.violatesExcludedTraits(excludeTraits) { return false }
        return true
    }

}

// MARK: - Codable (flat wire format)

extension ElementPredicate: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label, identifier, value, traits, excludeTraits
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decodeIfPresent(StringMatch<String>.self, forKey: .label),
            identifier: try container.decodeIfPresent(StringMatch<String>.self, forKey: .identifier),
            value: try container.decodeIfPresent(StringMatch<String>.self, forKey: .value),
            traits: try container.decodeIfPresent([HeistTrait].self, forKey: .traits) ?? [],
            excludeTraits: try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits) ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encodeIfPresent(value, forKey: .value)
        if !traits.isEmpty { try container.encode(traits, forKey: .traits) }
        if !excludeTraits.isEmpty { try container.encode(excludeTraits, forKey: .excludeTraits) }
    }
}

extension ElementPredicate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("predicate", [
            ScoreDescription.stringMatchField("label", label),
            ScoreDescription.stringMatchField("identifier", identifier),
            ScoreDescription.stringMatchField("value", value),
            ScoreDescription.listField("traits", traits.isEmpty ? nil : traits),
            ScoreDescription.listField("excludeTraits", excludeTraits.isEmpty ? nil : excludeTraits),
        ].compactMap { $0 })
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
