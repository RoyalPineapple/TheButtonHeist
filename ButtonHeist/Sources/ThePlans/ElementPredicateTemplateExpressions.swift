import Foundation

// MARK: - Element Predicate Templates

public struct ElementPredicateTemplate: Codable, Sendable, Equatable, Hashable {
    public let label: StringMatch<StringExpr>?
    public let identifier: StringMatch<StringExpr>?
    public let value: StringMatch<StringExpr>?
    public let traits: [HeistTrait]
    public let excludeTraits: [HeistTrait]

    public init(
        label: StringMatch<StringExpr>? = nil,
        identifier: StringMatch<StringExpr>? = nil,
        value: StringMatch<StringExpr>? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) {
        self.label = label
        self.identifier = identifier
        self.value = value
        self.traits = traits
        self.excludeTraits = excludeTraits
    }

    public init(_ predicate: ElementPredicate) {
        self.init(
            label: predicate.label.map { $0.map(StringExpr.literal) },
            identifier: predicate.identifier.map { $0.map(StringExpr.literal) },
            value: predicate.value.map { $0.map(StringExpr.literal) },
            traits: predicate.traits,
            excludeTraits: predicate.excludeTraits
        )
    }

    public var hasPredicates: Bool {
        label != nil || identifier != nil || value != nil || !traits.isEmpty || !excludeTraits.isEmpty
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementPredicate {
        ElementPredicate(
            label: try label?.resolve(in: environment),
            identifier: try identifier?.resolve(in: environment),
            value: try value?.resolve(in: environment),
            traits: traits,
            excludeTraits: excludeTraits
        )
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case label, labelRef = "label_ref"
        case identifier, identifierRef = "identifier_ref"
        case value, valueRef = "value_ref"
        case traits, excludeTraits
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element predicate template")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(container: container)
    }

    static func decodeAllowingAdditionalKeys(from decoder: Decoder) throws -> ElementPredicateTemplate {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        return try ElementPredicateTemplate(container: container)
    }

    init(container: KeyedDecodingContainer<CodingKeys>) throws {
        label = try Self.decodeStringMatchExpr(container, literalKey: .label, refKey: .labelRef)
        identifier = try Self.decodeStringMatchExpr(container, literalKey: .identifier, refKey: .identifierRef)
        value = try Self.decodeStringMatchExpr(container, literalKey: .value, refKey: .valueRef)
        traits = try container.decodeIfPresent([HeistTrait].self, forKey: .traits) ?? []
        excludeTraits = try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encode(label, literalKey: .label, refKey: .labelRef, into: &container)
        try Self.encode(identifier, literalKey: .identifier, refKey: .identifierRef, into: &container)
        try Self.encode(value, literalKey: .value, refKey: .valueRef, into: &container)
        if !traits.isEmpty { try container.encode(traits, forKey: .traits) }
        if !excludeTraits.isEmpty { try container.encode(excludeTraits, forKey: .excludeTraits) }
    }

    private static func decodeStringMatchExpr(
        _ container: KeyedDecodingContainer<CodingKeys>,
        literalKey: CodingKeys,
        refKey: CodingKeys
    ) throws -> StringMatch<StringExpr>? {
        let literal = try container.decodeIfPresent(StringMatch<StringExpr>.self, forKey: literalKey)
        let reference = try HeistReferenceName.decodeIfPresent(from: container, forKey: refKey)
        switch (literal, reference) {
        case (.some(let literal), nil):
            return literal
        case (nil, .some(let reference)):
            return .exact(.ref(reference))
        case (.some, .some):
            throw DecodingError.dataCorruptedError(
                forKey: refKey,
                in: container,
                debugDescription: "element predicate accepts either \(literalKey.stringValue) or \(refKey.stringValue), not both"
            )
        case (nil, nil):
            return nil
        }
    }

    private static func encode(
        _ expression: StringMatch<StringExpr>?,
        literalKey: CodingKeys,
        refKey: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch expression {
        case .some(.exact(.ref(let reference))):
            try container.encode(reference, forKey: refKey)
        case .some(let match):
            try container.encode(match, forKey: literalKey)
        case nil:
            break
        }
    }
}

extension ElementPredicateTemplate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("predicate", [
            label.map { "label=\($0)" },
            identifier.map { "identifier=\($0)" },
            value.map { "value=\($0)" },
            ScoreDescription.listField("traits", traits.isEmpty ? nil : traits),
            ScoreDescription.listField("excludeTraits", excludeTraits.isEmpty ? nil : excludeTraits),
        ].compactMap { $0 })
    }
}
