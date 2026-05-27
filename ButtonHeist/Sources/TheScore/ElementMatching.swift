import Foundation

// MARK: - Container Matching

/// Stable names for parser accessibility container categories.
public enum ContainerTypeName: String, Codable, CaseIterable, Sendable {
    case semanticGroup
    case list
    case landmark
    case dataTable
    case tabBar
    case scrollable
}

/// Exact selector for container nodes in an interface tree.
///
/// This is intentionally separate from `ElementMatcher`: elements and
/// containers have different identity fields and are matched in different tree
/// positions.
public struct ContainerMatcher: Codable, Sendable, Equatable {
    public let stableId: HeistContainer?
    public let type: ContainerTypeName?
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let isModalBoundary: Bool?

    public init(
        stableId: HeistContainer? = nil,
        type: ContainerTypeName? = nil,
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        isModalBoundary: Bool? = nil
    ) {
        self.stableId = stableId
        self.type = type
        self.label = label
        self.value = value
        self.identifier = identifier
        self.isModalBoundary = isModalBoundary
    }

    public var hasPredicates: Bool {
        stableId?.isEmpty == false || type != nil || label?.isEmpty == false ||
            value?.isEmpty == false || identifier?.isEmpty == false || isModalBoundary != nil
    }
}

extension ContainerMatcher: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("containerMatcher", [
            ScoreDescription.stringField("stableId", stableId),
            ScoreDescription.valueField("type", type),
            ScoreDescription.stringField("label", label),
            ScoreDescription.stringField("value", value),
            ScoreDescription.stringField("identifier", identifier),
            ScoreDescription.valueField("modal", isModalBoundary),
        ].compactMap { $0 })
    }
}

// MARK: - Element Matcher

/// Composable predicate for scanning the accessibility tree.
/// All non-nil fields must match (AND semantics).
///
/// Matching is **exact or miss**: `heistId` must equal the current leaf handle;
/// string fields (`label`, `identifier`, `value`) must equal the matcher value,
/// compared case-insensitively after typography folding (smart quotes/dashes/
/// ellipsis fold to ASCII; emoji, accents, and CJK pass through). Trait fields
/// use exact bitmask comparison.
///
/// There is no substring fallback. On miss, the resolver returns `.notFound`
/// with structured suggestions ("did you mean 'Save Draft' or 'Save All'?")
/// produced by the diagnostic / near-miss path. Agents who relied on substring
/// fallback must use the full label.
///
/// Trait values use the HeistTrait enum (e.g. .button, .header, .selected).
/// The hierarchy-level matcher bridges these to UIAccessibilityTraits bitmasks
/// via AccessibilitySnapshotParser's knownTraits.
public struct ElementMatcher: Codable, Sendable, Equatable {
    /// Exact match against the Button Heist leaf element handle
    public let heistId: HeistId?
    /// Case-insensitive equality match against element label (typography-folded)
    public let label: String?
    /// Case-insensitive equality match against accessibility identifier (typography-folded)
    public let identifier: String?
    /// Case-insensitive equality match against element value (typography-folded)
    public let value: String?
    /// All listed traits must be present on the element (AND)
    public let traits: [HeistTrait]?
    /// None of the listed traits may be present on the element
    public let excludeTraits: [HeistTrait]?

    public init(
        heistId: HeistId? = nil,
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait]? = nil,
        excludeTraits: [HeistTrait]? = nil
    ) {
        self.heistId = heistId
        self.label = label
        self.identifier = identifier
        self.value = value
        self.traits = traits
        self.excludeTraits = excludeTraits
    }

    public var hasTraitPredicates: Bool {
        (traits?.isEmpty == false) || (excludeTraits?.isEmpty == false)
    }

    /// Whether any property predicate is set (heistId, label, identifier, value, traits, or excludeTraits).
    /// Empty strings are treated as unset — they match nothing rather than everything.
    public var hasPredicates: Bool {
        heistId?.isEmpty == false || label?.isEmpty == false || identifier?.isEmpty == false ||
            value?.isEmpty == false || hasTraitPredicates
    }

    /// Returns `self` when at least one predicate field is set, else `nil`.
    /// Useful for chaining: an empty matcher shouldn't be sent over the wire,
    /// so callers can drop it with `matcher.nonEmpty`.
    public var nonEmpty: Self? { hasPredicates ? self : nil }
}

extension ElementMatcher: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("matcher", [
            ScoreDescription.stringField("heistId", heistId),
            ScoreDescription.stringField("label", label),
            ScoreDescription.stringField("identifier", identifier),
            ScoreDescription.stringField("value", value),
            ScoreDescription.listField("traits", traits),
            ScoreDescription.listField("excludeTraits", excludeTraits),
        ].compactMap { $0 })
    }
}

/// Selector for projecting an `Interface` to one matched node.
///
/// `.element` searches leaf `HeistElement` nodes with `ElementMatcher`.
/// `.container` searches parser container nodes with `ContainerMatcher`.
/// `ordinal` is applied only after semantic narrowing; element matches are
/// ordered by parse-local traversal index with tree path as a tie-breaker.
public enum SubtreeSelector: Codable, Sendable, Equatable {
    case element(ElementMatcher, ordinal: Int? = nil)
    case container(ContainerMatcher, ordinal: Int? = nil)

    private enum CodingKeys: String, CodingKey {
        case element
        case container
        case ordinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hasElement = container.contains(.element)
        let hasContainer = container.contains(.container)
        guard hasElement != hasContainer else {
            throw DecodingError.dataCorruptedError(
                forKey: .element,
                in: container,
                debugDescription: "SubtreeSelector requires exactly one of element or container"
            )
        }
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if hasElement {
            self = .element(try container.decode(ElementMatcher.self, forKey: .element), ordinal: ordinal)
        } else {
            self = .container(try container.decode(ContainerMatcher.self, forKey: .container), ordinal: ordinal)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let matcher, let ordinal):
            try container.encode(matcher, forKey: .element)
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        case .container(let matcher, let ordinal):
            try container.encode(matcher, forKey: .container)
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        }
    }

    public var ordinal: Int? {
        switch self {
        case .element(_, let ordinal), .container(_, let ordinal):
            return ordinal
        }
    }

    public var hasPredicates: Bool {
        switch self {
        case .element(let matcher, _):
            return matcher.hasPredicates
        case .container(let matcher, _):
            return matcher.hasPredicates
        }
    }
}

extension SubtreeSelector: CustomStringConvertible {
    public var description: String {
        switch self {
        case .element(let matcher, let ordinal):
            return ScoreDescription.call("subtree.element", [
                matcher.description,
                ScoreDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        case .container(let matcher, let ordinal):
            return ScoreDescription.call("subtree.container", [
                matcher.description,
                ScoreDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        }
    }
}

// MARK: - Convenience Extensions

extension HeistElement {
    /// Known trait values. Used to reject unknown traits in matcher queries (fail-safe).
    private static let knownTraits = Set(HeistTrait.allCases)

    /// Match this wire element against an ElementMatcher predicate.
    ///
    /// Exact-or-miss semantics: string fields (`label`, `identifier`, `value`)
    /// must equal the matcher value, compared case-insensitively after typography
    /// folding (smart quotes/dashes/ellipsis fold to ASCII; emoji, accents, and
    /// CJK pass through). Trait fields use exact bitmask comparison. This is
    /// identical to the server-side `AccessibilityElement.matches` so the same
    /// `ElementMatcher` evaluated client-side and server-side produces the same
    /// answer.
    ///
    /// Used for client-side filtering of serialized interface data (`get_interface`)
    /// and for action-expectation matchers (`elementAppeared`, `elementDisappeared`).
    /// Unknown traits in `traits` or `excludeTraits` cause a miss (fail-safe).
    public func matches(_ matcher: ElementMatcher) -> Bool {
        guard matcher.hasPredicates else { return false }
        if let matchHeistId = matcher.heistId {
            if matchHeistId.isEmpty { return false }
            guard heistId == matchHeistId else { return false }
        }
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

// MARK: - String Comparison Helpers

extension ElementMatcher {
    /// Case-insensitive equality with typography folding. The canonical comparison
    /// used by both client-side `HeistElement.matches` and server-side
    /// `AccessibilityElement.matches`. Folding turns smart quotes / dashes /
    /// ellipsis / non-breaking spaces into their ASCII equivalents so labels
    /// authored with typographic punctuation match patterns typed with ASCII
    /// (and vice versa). Real Unicode without an ASCII equivalent — emoji,
    /// accents, CJK — is left untouched.
    public static func stringEquals(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveCompare(normalizeTypography(pattern)) == .orderedSame
    }

    /// Case-insensitive substring with typography folding. Suggestion-only —
    /// used by the diagnostic / near-miss path to surface "did you mean X?"
    /// hints when an exact match fails. Never used by resolution.
    public static func stringContains(_ candidate: String, _ pattern: String) -> Bool {
        normalizeTypography(candidate)
            .localizedCaseInsensitiveContains(normalizeTypography(pattern))
    }

    /// Fold typographic punctuation that has an ASCII equivalent.
    /// Shared between client-side and server-side matchers so the same input
    /// produces the same comparison on both sides.
    public static func normalizeTypography(_ string: String) -> String {
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
        "\u{2018}": "'",  // ' LEFT SINGLE QUOTATION MARK
        "\u{2019}": "'",  // ' RIGHT SINGLE QUOTATION MARK / typographic apostrophe
        "\u{201A}": "'",  // ‚ SINGLE LOW-9 QUOTATION MARK
        "\u{201B}": "'",  // ‛ SINGLE HIGH-REVERSED-9 QUOTATION MARK
        "\u{2032}": "'",  // ′ PRIME
        // Double quotes
        "\u{201C}": "\"", // " LEFT DOUBLE QUOTATION MARK
        "\u{201D}": "\"", // " RIGHT DOUBLE QUOTATION MARK
        "\u{201E}": "\"", // „ DOUBLE LOW-9 QUOTATION MARK
        "\u{201F}": "\"", // ‟ DOUBLE HIGH-REVERSED-9 QUOTATION MARK
        "\u{2033}": "\"", // ″ DOUBLE PRIME
        // Dashes / hyphens
        "\u{2010}": "-",  // ‐ HYPHEN
        "\u{2011}": "-",  // ‑ NON-BREAKING HYPHEN
        "\u{2012}": "-",  // ‒ FIGURE DASH
        "\u{2013}": "-",  // – EN DASH
        "\u{2014}": "-",  // — EM DASH
        "\u{2015}": "-",  // ― HORIZONTAL BAR
        "\u{2212}": "-",  // − MINUS SIGN
        // Ellipsis
        "\u{2026}": "...", // … HORIZONTAL ELLIPSIS
        // Non-breaking / typographic spaces
        "\u{00A0}": " ",  // NO-BREAK SPACE
        "\u{2007}": " ",  // FIGURE SPACE
        "\u{202F}": " ",  // NARROW NO-BREAK SPACE
    ]
}
