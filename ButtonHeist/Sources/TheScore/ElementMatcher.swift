import Foundation

// MARK: - Element Matching

/// Composable predicate for scanning accessibility elements.
///
/// Matching is exact-or-miss: string fields (`label`, `identifier`, `value`)
/// must equal the matcher value after case-insensitive typography folding.
/// Substring comparison is reserved for diagnostic suggestions, never
/// resolution. Trait fields use exact bitmask comparison.
public struct ElementMatcher: Sendable, Equatable {
    /// Case-insensitive equality match against element label.
    public let label: String?
    /// Case-insensitive equality match against accessibility identifier.
    public let identifier: String?
    /// Case-insensitive equality match against element value.
    public let value: String?
    /// All listed traits must be present on the element.
    public let traits: [HeistTrait]?
    /// None of the listed traits may be present on the element.
    public let excludeTraits: [HeistTrait]?

    public init(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait]? = nil,
        excludeTraits: [HeistTrait]? = nil
    ) {
        self.label = label
        self.identifier = identifier
        self.value = value
        self.traits = traits
        self.excludeTraits = excludeTraits
    }

    public var hasTraitPredicates: Bool {
        (traits?.isEmpty == false) || (excludeTraits?.isEmpty == false)
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

extension ElementMatcher: Codable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case label, identifier, value, traits, excludeTraits
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element matcher")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try container.decodeIfPresent(String.self, forKey: .label),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            value: try container.decodeIfPresent(String.self, forKey: .value),
            traits: try container.decodeIfPresent([HeistTrait].self, forKey: .traits),
            excludeTraits: try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(traits, forKey: .traits)
        try container.encodeIfPresent(excludeTraits, forKey: .excludeTraits)
    }
}

extension ElementMatcher: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("matcher", [
            ScoreDescription.stringField("label", label),
            ScoreDescription.stringField("identifier", identifier),
            ScoreDescription.stringField("value", value),
            ScoreDescription.listField("traits", traits),
            ScoreDescription.listField("excludeTraits", excludeTraits),
        ].compactMap { $0 })
    }
}

extension HeistElement {
    /// Known trait values. Used to reject unknown traits in matcher queries.
    private static let knownTraits = Set(HeistTrait.allCases)

    /// Match this wire element against an `ElementMatcher`.
    ///
    /// Unknown traits in `traits` or `excludeTraits` cause a miss.
    public func matches(_ matcher: ElementMatcher) -> Bool {
        guard matcher.hasPredicates else { return false }
        if let matchLabel = matcher.label {
            if matchLabel.isEmpty { return false }
            guard let label, ElementMatcher.stringEquals(label, matchLabel) else { return false }
        }
        if let matchId = matcher.identifier {
            if matchId.isEmpty { return false }
            guard let identifier, ElementMatcher.stringEquals(identifier, matchId) else { return false }
        }
        if let matchVal = matcher.value {
            if matchVal.isEmpty { return false }
            guard let value, ElementMatcher.stringEquals(value, matchVal) else { return false }
        }
        let traitSet = matcher.hasTraitPredicates ? Set(traits) : []
        if let required = matcher.traits, !required.isEmpty {
            for trait in required where !Self.knownTraits.contains(trait) { return false }
            for trait in required where !traitSet.contains(trait) { return false }
        }
        if let excluded = matcher.excludeTraits, !excluded.isEmpty {
            for trait in excluded where !Self.knownTraits.contains(trait) { return false }
            for trait in excluded where traitSet.contains(trait) { return false }
        }
        return true
    }
}
