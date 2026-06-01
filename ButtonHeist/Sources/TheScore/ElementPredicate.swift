import Foundation

// MARK: - Element Predicate

/// The canonical predicate for matching a single accessibility element.
///
/// Matching is exact-or-miss: string fields (`label`, `identifier`, `value`)
/// must equal the predicate value after case-insensitive typography folding.
/// Substring comparison is reserved for diagnostic suggestions, never
/// resolution. Trait fields use exact bitmask comparison. Specificity is
/// expressed entirely by which fields are set — there is no separate scope or
/// query system.
public struct ElementPredicate: Sendable, Equatable, Hashable {
    /// Case-insensitive equality match against element label.
    public var label: String?
    /// Case-insensitive equality match against accessibility identifier.
    public var identifier: String?
    /// Case-insensitive equality match against element value.
    public var value: String?
    /// All listed traits must be present on the element.
    public var traits: [HeistTrait]
    /// None of the listed traits may be present on the element.
    public var excludeTraits: [HeistTrait]

    public init(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
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
        label?.isEmpty == false || identifier?.isEmpty == false ||
            value?.isEmpty == false || hasTraitPredicates
    }

    /// Returns `self` when at least one predicate field is set, else `nil`.
    public var nonEmpty: Self? { hasPredicates ? self : nil }
}

// MARK: - Convenience Constructors

public extension ElementPredicate {
    /// Match by label alone.
    static func label(_ label: String) -> ElementPredicate {
        ElementPredicate(label: label)
    }

    /// Match by accessibility identifier alone.
    static func identifier(_ identifier: String) -> ElementPredicate {
        ElementPredicate(identifier: identifier)
    }

    /// Match by value alone.
    static func value(_ value: String) -> ElementPredicate {
        ElementPredicate(value: value)
    }

    /// Match by any combination of fields — the canonical multi-field form.
    static func element(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
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

// MARK: - String Match Mode

public extension ElementPredicate {
    /// String-comparison strategy for predicate string fields.
    /// Trait predicates ignore this — they always compare exactly.
    enum StringMatchMode: Sendable {
        /// Case-insensitive equality with typography folding. The single
        /// resolution semantics.
        case exact
        /// Case-insensitive substring with typography folding. Suggestion-only —
        /// used by diagnostics to surface near misses, never by resolution.
        case substring
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
    func matches(_ subject: some ElementPredicateSubject, mode: StringMatchMode = .exact) -> Bool {
        guard hasPredicates else { return false }
        if let label {
            if label.isEmpty { return false }
            guard let candidate = subject.predicateLabel, Self.stringMatches(candidate, label, mode: mode) else { return false }
        }
        if let identifier {
            if identifier.isEmpty { return false }
            guard let candidate = subject.predicateIdentifier, Self.stringMatches(candidate, identifier, mode: mode) else { return false }
        }
        if let value {
            if value.isEmpty { return false }
            guard let candidate = subject.predicateValue, Self.stringMatches(candidate, value, mode: mode) else { return false }
        }
        if !traits.isEmpty, !subject.satisfiesRequiredTraits(traits) { return false }
        if !excludeTraits.isEmpty, subject.violatesExcludedTraits(excludeTraits) { return false }
        return true
    }

    /// Whether any element in the collection satisfies this predicate.
    func anyMatch(in elements: [HeistElement]) -> Bool {
        elements.contains { matches($0) }
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
            label: try container.decodeIfPresent(String.self, forKey: .label),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            value: try container.decodeIfPresent(String.self, forKey: .value),
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
            ScoreDescription.stringField("label", label),
            ScoreDescription.stringField("identifier", identifier),
            ScoreDescription.stringField("value", value),
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

    /// Case-insensitive substring with typography folding. Suggestion-only:
    /// used by diagnostics to surface near misses, never by resolution.
    static func stringContains(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveContains(normalizeTypography(pattern))
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

    internal static func stringMatches(_ candidate: String, _ pattern: String, mode: StringMatchMode) -> Bool {
        switch mode {
        case .exact: return stringEquals(candidate, pattern)
        case .substring: return stringContains(candidate, pattern)
        }
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

// MARK: - HeistElement Conformance

extension HeistElement: ElementPredicateSubject {
    /// Known trait values. Used to reject unknown traits in predicate queries.
    private static let knownTraits = Set(HeistTrait.allCases)

    public var predicateLabel: String? { label }
    public var predicateIdentifier: String? { identifier }
    public var predicateValue: String? { value }

    public func satisfiesRequiredTraits(_ required: [HeistTrait]) -> Bool {
        for trait in required where !Self.knownTraits.contains(trait) { return false }
        let traitSet = Set(traits)
        return required.allSatisfy { traitSet.contains($0) }
    }

    public func violatesExcludedTraits(_ excluded: [HeistTrait]) -> Bool {
        for trait in excluded where !Self.knownTraits.contains(trait) { return true }
        let traitSet = Set(traits)
        return excluded.contains { traitSet.contains($0) }
    }

    /// Match this wire element against an `ElementPredicate`.
    public func matches(_ predicate: ElementPredicate) -> Bool {
        predicate.matches(self, mode: .exact)
    }
}
