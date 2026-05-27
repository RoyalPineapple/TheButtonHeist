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

    /// Returns nil if both matcher and ordinal are empty.
    public init?(heistId: HeistId? = nil, matcher: ElementMatcher, ordinal: Int? = nil) {
        if let heistId {
            guard ordinal == nil, matcher.nonEmpty == nil else { return nil }
            self = .heistId(heistId)
        } else if let match = matcher.nonEmpty {
            self = .matcher(match, ordinal: ordinal)
        } else if ordinal != nil {
            self = .matcher(matcher, ordinal: ordinal)
        } else {
            return nil
        }
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
    fileprivate enum CodingKeys: String, CodingKey {
        case heistId
        case label, identifier, value, traits, excludeTraits
        case ordinal

        /// The matcher / heistId keys whose presence in a parent container
        /// indicates an `ElementTarget` is flattened at that level.
        static let allInlineKeys: [CodingKeys] = [
            .heistId, .label, .identifier, .value, .traits, .excludeTraits, .ordinal,
        ]
    }

    /// Decode an optional `ElementTarget` flattened into the same JSON object
    /// the decoder is currently reading. Returns `nil` when none of the
    /// matcher / heistId keys are present; throws if at least one key is
    /// present but the resulting target fails ElementTarget's own validation.
    public static func decodeInlineIfPresent(from decoder: Decoder) throws -> ElementTarget? {
        let probe = try decoder.container(keyedBy: CodingKeys.self)
        let hasTargetFields = CodingKeys.allInlineKeys.contains { probe.contains($0) }
        guard hasTargetFields else { return nil }
        return try ElementTarget(from: decoder)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if let ordinal, ordinal < 0 {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "ordinal must be non-negative, got \(ordinal)"
            ))
        }
        if let heistId = try container.decodeIfPresent(HeistId.self, forKey: .heistId) {
            let hasMatcherFields = [
                CodingKeys.label, .identifier, .value, .traits, .excludeTraits,
            ].contains { container.contains($0) }
            if ordinal != nil || hasMatcherFields {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: container.codingPath,
                    debugDescription: "ElementTarget heistId cannot be combined with matcher fields or ordinal; use either a capture handle or a semantic matcher"
                ))
            }
            self = .heistId(heistId)
            return
        }
        let matcher = ElementMatcher(
            label: try container.decodeIfPresent(String.self, forKey: .label),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            value: try container.decodeIfPresent(String.self, forKey: .value),
            traits: try container.decodeIfPresent([HeistTrait].self, forKey: .traits),
            excludeTraits: try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits)
        )
        if let match = matcher.nonEmpty {
            self = .matcher(match, ordinal: ordinal)
        } else if ordinal != nil {
            self = .matcher(matcher, ordinal: ordinal)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "ElementTarget requires heistId, ordinal, or at least one matcher field (label, identifier, value, traits, excludeTraits)"
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
