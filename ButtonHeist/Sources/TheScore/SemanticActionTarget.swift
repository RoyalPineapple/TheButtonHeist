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
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case matcher, ordinal
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
        try Self.rejectUnknownKeys(decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.matcher) else {
            throw DecodingError.dataCorruptedError(
                forKey: .matcher,
                in: container,
                debugDescription: "SemanticActionTarget requires matcher predicates; ordinal only disambiguates matcher results"
            )
        }
        let matcher = try container.decode(ElementMatcher.self, forKey: .matcher)
        let ordinal = try container.decodeIfPresent(Int.self, forKey: .ordinal)
        if matcher.heistId != nil {
            throw DecodingError.dataCorruptedError(
                forKey: .matcher,
                in: container,
                debugDescription: "SemanticActionTarget matcher must not carry heistId; use _recorded.heistId metadata"
            )
        }
        if let ordinal, ordinal < 0 {
            throw DecodingError.dataCorruptedError(
                forKey: .ordinal,
                in: container,
                debugDescription: "ordinal must be non-negative, got \(ordinal)"
            )
        }
        self.init(matcher: matcher, ordinal: ordinal)
        guard self.matcher.hasPredicates else {
            throw DecodingError.dataCorruptedError(
                forKey: .matcher,
                in: container,
                debugDescription: "SemanticActionTarget requires matcher predicates; ordinal only disambiguates matcher results"
            )
        }
    }

    private static func rejectUnknownKeys(_ decoder: Decoder) throws {
        let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let unknownKey = dynamicContainer.allKeys.first(where: { !knownKeys.contains($0.stringValue) }) else {
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath + [unknownKey],
            debugDescription: "Unknown semantic action target field \"\(unknownKey.stringValue)\""
        ))
    }

    public func encode(to encoder: Encoder) throws {
        guard matcher.hasPredicates else {
            throw EncodingError.invalidValue(self, .init(
                codingPath: encoder.codingPath,
                debugDescription: "SemanticActionTarget requires matcher predicates; ordinal only disambiguates matcher results"
            ))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
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

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
