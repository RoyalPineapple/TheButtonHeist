import Foundation

/// Durable semantic element target used by actionability execution plans.
///
/// `sourceHeistId` is in-memory diagnostic source metadata from the capture
/// that produced the matcher. It is never executable identity and is not part
/// of the persisted wire shape. Recorded files keep source handles under
/// `_recorded.heistId` evidence.
///
/// Current-capture heistIds must be converted to this form only at durable
/// boundaries such as heist recording, playback construction, or explicit
/// SemanticActionTarget creation.
public struct SemanticActionTarget: Codable, Sendable, Equatable {
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
        let target = try ElementTarget(from: decoder)
        switch target {
        case .matcher(let matcher, let ordinal):
            self.init(matcher: matcher, ordinal: ordinal)
        case .heistId:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: """
                SemanticActionTarget requires matcher fields; heistId is a capture-local handle and belongs under \
                _recorded.heistId evidence
                """
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        guard matcher.hasPredicates else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "SemanticActionTarget requires matcher predicates; ordinal only disambiguates matcher results"
            ))
        }
        try ElementTarget.matcher(matcher, ordinal: ordinal).encode(to: encoder)
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
