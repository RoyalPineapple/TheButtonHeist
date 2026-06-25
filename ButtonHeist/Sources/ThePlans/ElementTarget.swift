import Foundation

// MARK: - Action Targets

/// Target for element actions.
///
/// An element is described by a predicate (label, identifier, value, traits,
/// excludeTraits); `ordinal` disambiguates among matches. Predicate fields use
/// `StringMatch` semantics; exact matching is the default.
/// Broad string matches such as `.label(.contains(...))` are opt-in; there is no
/// automatic substring fallback. On miss, the resolver returns structured
/// suggestions.
public enum ElementTarget: Sendable, Equatable, Hashable {
    /// Element predicate: label, identifier, value, traits, excludeTraits.
    /// `ordinal` is a 0-based selection index into the list of matches
    /// after semantic narrowing. When nil, requires a unique match and reports
    /// ambiguity on 2+ hits. When set, selects the Nth narrowed match.
    /// This is a disambiguator for match results, NOT durable identity.
    case predicate(ElementPredicate, ordinal: Int? = nil)

}

public extension ElementTarget {
    enum SchemaFieldKind: Sendable, Equatable {
        case string
        case stringMatch
        case stringArray
        case nonNegativeInteger
    }

    struct SchemaField: Sendable, Equatable {
        public let name: String
        public let kind: SchemaFieldKind
    }

    static var predicateSchemaFields: [SchemaField] {
        CodingKeys.predicateKeys.map { schemaField(for: $0) }
    }

    static var disambiguatorSchemaFields: [SchemaField] {
        [schemaField(for: .ordinal)]
    }

    static var inlineSchemaFields: [SchemaField] {
        predicateSchemaFields + disambiguatorSchemaFields
    }

    static var predicateFieldNames: [String] {
        predicateSchemaFields.map(\.name)
    }

    static var selectorFieldNames: [String] {
        predicateFieldNames
    }

    static var disambiguatorFieldNames: [String] {
        disambiguatorSchemaFields.map(\.name)
    }

    static var inlineFieldNames: [String] {
        inlineSchemaFields.map(\.name)
    }

    private static func schemaField(for key: CodingKeys) -> SchemaField {
        switch key {
        case .label, .identifier, .value:
            return SchemaField(name: key.stringValue, kind: .stringMatch)
        case .traits, .excludeTraits:
            return SchemaField(name: key.stringValue, kind: .stringArray)
        case .ordinal:
            return SchemaField(name: key.stringValue, kind: .nonNegativeInteger)
        }
    }
}

extension ElementTarget: CustomStringConvertible {
    public var description: String {
        switch self {
        case .predicate(let predicate, let ordinal):
            return ScoreDescription.call("target", [
                predicate.description,
                ScoreDescription.valueField("ordinal", ordinal),
            ].compactMap { $0 })
        }
    }
}

// MARK: - ElementTarget Codable (flat wire format)

extension ElementTarget: Codable {
    public enum CodingKeys: String, CodingKey {
        case label, identifier, value, traits, excludeTraits
        case ordinal

        /// The predicate keys whose presence in a parent container indicates an
        /// `ElementTarget` is flattened at that level.
        static let predicateKeys: [CodingKeys] = [.label, .identifier, .value, .traits, .excludeTraits]
        static let allInlineKeys: [CodingKeys] = predicateKeys + [.ordinal]
    }

    /// Decode an optional `ElementTarget` flattened into the same JSON object
    /// the decoder is currently reading. Returns `nil` when none of the
    /// predicate keys are present; throws if at least one key is present but the
    /// resulting target fails ElementTarget's own validation.
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

    public static func decodeSubtreeElement(from decoder: Decoder, ordinal: Int?) throws -> ElementTarget {
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
        let predicate = ElementPredicate(
            label: try container.decodeIfPresent(StringMatch<String>.self, forKey: .label),
            identifier: try container.decodeIfPresent(StringMatch<String>.self, forKey: .identifier),
            value: try container.decodeIfPresent(StringMatch<String>.self, forKey: .value),
            traits: try container.decodeIfPresent([HeistTrait].self, forKey: .traits) ?? [],
            excludeTraits: try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits) ?? []
        )
        return try targetOrDecodingError(
            predicate: predicate,
            predicateWasProvided: hasPredicateFields(in: container),
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

    private static func hasPredicateFields(in container: KeyedDecodingContainer<CodingKeys>) -> Bool {
        CodingKeys.predicateKeys.contains { container.contains($0) }
    }

    private static func targetOrDecodingError(
        predicate: ElementPredicate,
        predicateWasProvided: Bool,
        ordinal: Int?,
        codingPath: [CodingKey]
    ) throws -> ElementTarget {
        do {
            return try ElementTargetGrammar.validatedTarget(
                predicate: predicate,
                predicateWasProvided: predicateWasProvided,
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
        case .predicate(let predicate, let ordinal):
            try container.encodeIfPresent(predicate.label, forKey: .label)
            try container.encodeIfPresent(predicate.identifier, forKey: .identifier)
            try container.encodeIfPresent(predicate.value, forKey: .value)
            if !predicate.traits.isEmpty { try container.encode(predicate.traits, forKey: .traits) }
            if !predicate.excludeTraits.isEmpty { try container.encode(predicate.excludeTraits, forKey: .excludeTraits) }
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        }
    }
}
