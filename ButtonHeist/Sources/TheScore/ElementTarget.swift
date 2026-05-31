import Foundation

// MARK: - Action Targets

/// Target for element actions.
/// Two resolution strategies: heistId (current-hierarchy token from
/// get_interface) or matcher (describe the element by accessibility
/// properties). HeistId is a standalone capture-local handle; ordinal only
/// applies to matcher targets.
/// Use heistId for immediate follow-up actions in the current capture; use
/// minimum matchers for durable replay. Matcher fields use case-insensitive
/// equality with typography folding — exact-or-miss.
/// On miss, the resolver returns structured suggestions; there is no
/// substring fallback.
public enum ElementTarget: Sendable, Equatable {
    /// Current-hierarchy handle assigned by get_interface — fast O(1) lookup.
    case heistId(HeistId)
    /// Predicate matcher: label, identifier, value, traits, excludeTraits.
    /// `ordinal` is a 0-based selection index into the list of matches
    /// after semantic narrowing. When nil, requires a unique match and reports
    /// ambiguity on 2+ hits. When set, selects the Nth narrowed match.
    /// This is a disambiguator for match results, NOT durable identity.
    case matcher(ElementMatcher, ordinal: Int? = nil)

}

public extension ElementTarget {
    static var heistIdFieldName: String {
        CodingKeys.heistId.stringValue
    }

    static var matcherFieldNames: [String] {
        CodingKeys.matcherKeys.map(\.stringValue)
    }

    static var selectorFieldNames: [String] {
        [heistIdFieldName] + matcherFieldNames
    }

    static var disambiguatorFieldNames: [String] {
        [CodingKeys.ordinal.stringValue]
    }

    static var inlineFieldNames: [String] {
        CodingKeys.allInlineKeys.map(\.stringValue)
    }
}

extension ElementTarget: CustomStringConvertible {
    public var description: String {
        switch self {
        case .heistId(let heistId):
            return ScoreDescription.call("target", [
                ScoreDescription.stringField("heistId", heistId),
            ].compactMap { $0 })
        case .matcher(let matcher, let ordinal):
            return ScoreDescription.call("target", [
                matcher.description,
                ScoreDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        }
    }
}

// MARK: - ElementTarget Codable (flat wire format)

extension ElementTarget: Codable {
    enum CodingKeys: String, CodingKey {
        case heistId
        case label, identifier, value, traits, excludeTraits
        case ordinal

        /// The matcher / heistId keys whose presence in a parent container
        /// indicates an `ElementTarget` is flattened at that level.
        static let matcherKeys: [CodingKeys] = [.label, .identifier, .value, .traits, .excludeTraits]
        static let allInlineKeys: [CodingKeys] = [.heistId] + matcherKeys + [.ordinal]
    }

    /// Decode an optional `ElementTarget` flattened into the same JSON object
    /// the decoder is currently reading. Returns `nil` when none of the
    /// matcher / heistId keys are present; throws if at least one key is
    /// present but the resulting target fails ElementTarget's own validation.
    public static func decodeInlineIfPresent(from decoder: Decoder) throws -> ElementTarget? {
        let probe = try decoder.container(keyedBy: CodingKeys.self)
        let hasTargetFields = CodingKeys.allInlineKeys.contains { probe.contains($0) }
        guard hasTargetFields else { return nil }
        return try decodeFlat(from: decoder, shouldRejectUnknownKeys: false)
    }

    /// Decode a required `ElementTarget` flattened into a command payload that
    /// may also contain command-specific fields.
    public static func decodeInline(from decoder: Decoder) throws -> ElementTarget {
        try decodeFlat(from: decoder, shouldRejectUnknownKeys: false)
    }

    public init(from decoder: Decoder) throws {
        self = try Self.decodeFlat(from: decoder, shouldRejectUnknownKeys: true)
    }

    static func decodeSubtreeElement(from decoder: Decoder, ordinal: Int?) throws -> ElementTarget {
        try decodeFlat(
            from: decoder,
            externalOrdinal: ordinal,
            allowsInlineOrdinal: false,
            shouldRejectUnknownKeys: true
        )
    }

    private static func decodeFlat(
        from decoder: Decoder,
        externalOrdinal: Int? = nil,
        allowsInlineOrdinal: Bool = true,
        shouldRejectUnknownKeys: Bool
    ) throws -> ElementTarget {
        if shouldRejectUnknownKeys {
            try rejectUnknownKeys(from: decoder, allowsInlineOrdinal: allowsInlineOrdinal)
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ordinal = allowsInlineOrdinal
            ? try container.decodeIfPresent(Int.self, forKey: .ordinal)
            : externalOrdinal
        if let ordinal, ordinal < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: ElementTargetGrammarError.negativeOrdinal(ordinal).diagnosticDescription
            )
        }
        if let heistId = try container.decodeIfPresent(HeistId.self, forKey: .heistId) {
            return try targetOrDecodingError(
                heistId: heistId,
                matcher: nil,
                matcherWasProvided: hasMatcherFields(in: container),
                ordinal: ordinal,
                codingPath: container.codingPath
            )
        }
        let matcher = ElementMatcher(
            label: try container.decodeIfPresent(String.self, forKey: .label),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            value: try container.decodeIfPresent(String.self, forKey: .value),
            traits: try container.decodeIfPresent([HeistTrait].self, forKey: .traits),
            excludeTraits: try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits)
        )
        return try targetOrDecodingError(
            heistId: nil,
            matcher: matcher,
            matcherWasProvided: hasMatcherFields(in: container),
            ordinal: ordinal,
            codingPath: container.codingPath
        )
    }

    private static func rejectUnknownKeys(from decoder: Decoder, allowsInlineOrdinal: Bool) throws {
        let allowedKeys = Set(CodingKeys.allInlineKeys
            .filter { allowsInlineOrdinal || $0 != .ordinal }
            .map(\.stringValue))
        try decoder.rejectUnknownKeys(allowed: allowedKeys, typeName: "element target")
    }

    private static func hasMatcherFields(in container: KeyedDecodingContainer<CodingKeys>) -> Bool {
        CodingKeys.matcherKeys.contains { container.contains($0) }
    }

    private static func targetOrDecodingError(
        heistId: HeistId?,
        matcher: ElementMatcher?,
        matcherWasProvided: Bool,
        ordinal: Int?,
        codingPath: [CodingKey]
    ) throws -> ElementTarget {
        do {
            return try ElementTargetGrammar.validatedTarget(
                heistId: heistId,
                matcher: matcher,
                matcherWasProvided: matcherWasProvided,
                ordinal: ordinal
            )
        } catch let error as ElementTargetGrammarError {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: error.diagnosticDescription
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heistId(let id):
            try container.encode(id, forKey: .heistId)
        case .matcher(let matcher, let ordinal):
            try container.encodeIfPresent(matcher.label, forKey: .label)
            try container.encodeIfPresent(matcher.identifier, forKey: .identifier)
            try container.encodeIfPresent(matcher.value, forKey: .value)
            try container.encodeIfPresent(matcher.traits, forKey: .traits)
            try container.encodeIfPresent(matcher.excludeTraits, forKey: .excludeTraits)
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        }
    }
}
