import Foundation

/// Durable semantic element target used by actionability execution plans.
///
/// `sourceHeistId` is diagnostic source metadata from the capture that produced
/// the matcher. It is never the executable identity. Execution resolves
/// `matcher` and `ordinal` against fresh live geometry.
///
/// Current-capture heistIds must be converted to this form only at durable
/// boundaries such as heist recording, playback construction, or explicit
/// SemanticActionTarget creation.
public struct SemanticActionTarget: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case sourceHeistId, matcher, ordinal
    }

    public let sourceHeistId: HeistId?
    public let matcher: ElementMatcher
    public let ordinal: Int?

    public init(
        sourceHeistId: HeistId? = nil,
        matcher: ElementMatcher,
        ordinal: Int? = nil
    ) {
        self.sourceHeistId = sourceHeistId
        self.matcher = ElementMatcher(
            label: matcher.label,
            identifier: matcher.identifier,
            value: matcher.value,
            traits: matcher.traits,
            excludeTraits: matcher.excludeTraits
        )
        self.ordinal = ordinal
    }

    public init(_ minimumMatcher: MinimumMatcher) {
        self.init(
            sourceHeistId: minimumMatcher.element.heistId,
            matcher: minimumMatcher.matcher,
            ordinal: minimumMatcher.ordinal
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceHeistId = try container.decodeIfPresent(HeistId.self, forKey: .sourceHeistId)
        let matcher = try container.decode(ElementMatcher.self, forKey: .matcher)
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if matcher.heistId != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .matcher,
                in: container,
                debugDescription: "SemanticActionTarget matcher must not carry heistId; use top-level sourceHeistId for metadata"
            )
        }
        if let ordinal, ordinal < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: "ordinal must be non-negative, got \(ordinal)"
            )
        }
        self.init(sourceHeistId: sourceHeistId, matcher: matcher, ordinal: ordinal)
        guard self.matcher.hasPredicates else {
            throw DecodingError.dataCorruptedError(
                forKey: .matcher,
                in: container,
                debugDescription: "SemanticActionTarget requires matcher predicates; ordinal only disambiguates matcher results"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard matcher.hasPredicates else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "SemanticActionTarget requires matcher predicates; ordinal only disambiguates matcher results"
            ))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(sourceHeistId, forKey: .sourceHeistId)
        try container.encode(matcher, forKey: .matcher)
        try container.encodeIfPresent(ordinal, forKey: .ordinal)
    }
}

extension SemanticActionTarget: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("semanticTarget", [
            ScoreDescription.stringField("sourceHeistId", sourceHeistId),
            matcher.description,
            ScoreDescription.valueField("ordinal", ordinal),
        ].compactMap { $0 })
    }
}
