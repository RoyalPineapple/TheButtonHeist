import Foundation

// MARK: - Action Targets

/// Target for element actions.
///
/// An element is described by an ordered predicate check chain; `ordinal`
/// disambiguates among matches. String checks use `StringMatch` semantics;
/// exact matching is the default.
/// Broad string matches such as `.label(.contains(...))` are opt-in; there is no
/// automatic substring fallback. On miss, the resolver returns structured
/// suggestions.
public enum ElementTarget: Sendable, Equatable, Hashable {
    /// Element predicate: ordered checks over semantic accessibility fields.
    /// `ordinal` is a 0-based selection index into the list of matches
    /// after semantic narrowing. When nil, requires a unique match and reports
    /// ambiguity on 2+ hits. When set, selects the Nth narrowed match.
    /// This is a disambiguator for match results, NOT durable identity.
    case predicate(ElementPredicate, ordinal: Int? = nil)

}

public extension ElementTarget {
    enum SchemaFieldKind: Sendable, Equatable {
        case predicateChecks
        case string
        case stringMatch
        case stringArray
        case stringMatchArray
        case actionArray
        case customContentMatch
        case nonNegativeInteger
    }

    struct SchemaField: Sendable, Equatable {
        public let name: String
        public let kind: SchemaFieldKind
    }

    static var predicateSchemaFields: [SchemaField] {
        [schemaField(for: .checks)]
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

    static var disambiguatorFieldNames: [String] {
        disambiguatorSchemaFields.map(\.name)
    }

    static var inlineFieldNames: [String] {
        inlineSchemaFields.map(\.name)
    }

    private static func schemaField(for key: CodingKeys) -> SchemaField {
        switch key {
        case .checks:
            return SchemaField(name: key.stringValue, kind: .predicateChecks)
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
        case checks
        case ordinal

        static let allInlineKeys: [CodingKeys] = [.checks, .ordinal]
    }

    /// Decode an optional `ElementTarget` flattened into the same JSON object
    /// the decoder is currently reading. Returns `nil` when none of the
    /// predicate keys are present; throws if at least one key is present but the
    /// resulting target fails ElementTarget's own validation.
    public static func decodeInlineIfPresent(from decoder: Decoder) throws -> ElementTarget? {
        let probe = try decoder.container(keyedBy: CodingKeys.self)
        let hasTargetFields = CodingKeys.allInlineKeys.contains { probe.contains($0) }
        guard hasTargetFields else { return nil }
        return try decodeCanonical(from: decoder, shouldRejectUnknownKeys: false)
    }

    /// Decode a required `ElementTarget` in a command payload that may also
    /// contain command-specific fields.
    public static func decodeInline(from decoder: Decoder) throws -> ElementTarget {
        try decodeCanonical(from: decoder, shouldRejectUnknownKeys: false)
    }

    public init(from decoder: Decoder) throws {
        self = try Self.decodeCanonical(from: decoder, shouldRejectUnknownKeys: true)
    }

    public static func decodeSubtreeElement(from decoder: Decoder, ordinal: Int?) throws -> ElementTarget {
        try decodeCanonical(
            from: decoder,
            externalOrdinal: ordinal,
            allowsInlineOrdinal: false,
            shouldRejectUnknownKeys: true
        )
    }

    private static func decodeCanonical(
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
        let hasChecks = container.contains(.checks)
        let predicate = ElementPredicate(try container.decodeIfPresent(
            [ElementPredicateCheck<String>].self,
            forKey: .checks
        ) ?? [])
        return try targetOrDecodingError(
            predicate: predicate,
            predicateWasProvided: hasChecks,
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
            if !predicate.checks.isEmpty { try container.encode(predicate.checks, forKey: .checks) }
            try container.encodeIfPresent(ordinal, forKey: .ordinal)
        }
    }
}
