import Foundation

// MARK: - Element Predicate Templates

public struct ElementPredicateTemplate: Codable, Sendable, Equatable, Hashable {
    public let labelMatches: [StringMatch<StringExpr>]
    public let identifierMatches: [StringMatch<StringExpr>]
    public let valueMatches: [StringMatch<StringExpr>]
    public let traits: [HeistTrait]
    public let excludeTraits: [HeistTrait]

    public var label: StringMatch<StringExpr>? { labelMatches.first }
    public var identifier: StringMatch<StringExpr>? { identifierMatches.first }
    public var value: StringMatch<StringExpr>? { valueMatches.first }

    public init(
        label: StringMatch<StringExpr>? = nil,
        identifier: StringMatch<StringExpr>? = nil,
        value: StringMatch<StringExpr>? = nil,
        labelMatches: [StringMatch<StringExpr>] = [],
        identifierMatches: [StringMatch<StringExpr>] = [],
        valueMatches: [StringMatch<StringExpr>] = [],
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) {
        self.labelMatches = Self.combined(label, with: labelMatches)
        self.identifierMatches = Self.combined(identifier, with: identifierMatches)
        self.valueMatches = Self.combined(value, with: valueMatches)
        self.traits = traits
        self.excludeTraits = excludeTraits
    }

    public init(
        _ checks: [ElementPredicateCheck<StringExpr>],
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) {
        var labelMatches: [StringMatch<StringExpr>] = []
        var identifierMatches: [StringMatch<StringExpr>] = []
        var valueMatches: [StringMatch<StringExpr>] = []
        for check in checks {
            switch check {
            case .label(let match):
                labelMatches.append(match)
            case .identifier(let match):
                identifierMatches.append(match)
            case .value(let match):
                valueMatches.append(match)
            }
        }
        self.init(
            labelMatches: labelMatches,
            identifierMatches: identifierMatches,
            valueMatches: valueMatches,
            traits: traits,
            excludeTraits: excludeTraits
        )
    }

    public init(_ predicate: ElementPredicate) {
        self.init(
            labelMatches: predicate.labelMatches.map { $0.map(StringExpr.literal) },
            identifierMatches: predicate.identifierMatches.map { $0.map(StringExpr.literal) },
            valueMatches: predicate.valueMatches.map { $0.map(StringExpr.literal) },
            traits: predicate.traits,
            excludeTraits: predicate.excludeTraits
        )
    }

    public var hasPredicates: Bool {
        labelMatches.contains { $0.hasPredicateLiteral } ||
            identifierMatches.contains { $0.hasPredicateLiteral } ||
            valueMatches.contains { $0.hasPredicateLiteral } ||
            !traits.isEmpty || !excludeTraits.isEmpty
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementPredicate {
        ElementPredicate(
            labelMatches: try labelMatches.map { try $0.resolve(in: environment) },
            identifierMatches: try identifierMatches.map { try $0.resolve(in: environment) },
            valueMatches: try valueMatches.map { try $0.resolve(in: environment) },
            traits: traits,
            excludeTraits: excludeTraits
        )
    }

    private static func combined(
        _ primary: StringMatch<StringExpr>?,
        with additional: [StringMatch<StringExpr>]
    ) -> [StringMatch<StringExpr>] {
        primary.map { [$0] + additional } ?? additional
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
        labelMatches = try Self.decodeStringMatchExprs(container, literalKey: .label, refKey: .labelRef)
        identifierMatches = try Self.decodeStringMatchExprs(container, literalKey: .identifier, refKey: .identifierRef)
        valueMatches = try Self.decodeStringMatchExprs(container, literalKey: .value, refKey: .valueRef)
        traits = try container.decodeIfPresent([HeistTrait].self, forKey: .traits) ?? []
        excludeTraits = try container.decodeIfPresent([HeistTrait].self, forKey: .excludeTraits) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encode(labelMatches, literalKey: .label, refKey: .labelRef, into: &container)
        try Self.encode(identifierMatches, literalKey: .identifier, refKey: .identifierRef, into: &container)
        try Self.encode(valueMatches, literalKey: .value, refKey: .valueRef, into: &container)
        if !traits.isEmpty { try container.encode(traits, forKey: .traits) }
        if !excludeTraits.isEmpty { try container.encode(excludeTraits, forKey: .excludeTraits) }
    }

    private static func decodeStringMatchExprs(
        _ container: KeyedDecodingContainer<CodingKeys>,
        literalKey: CodingKeys,
        refKey: CodingKeys
    ) throws -> [StringMatch<StringExpr>] {
        let literal = try StringMatch<StringExpr>.decodeOneOrMany(from: container, forKey: literalKey)
        let reference = try HeistReferenceName.decodeIfPresent(from: container, forKey: refKey)
        switch (literal.isEmpty, reference) {
        case (false, nil):
            return literal
        case (true, .some(let reference)):
            return [.exact(.ref(reference))]
        case (false, .some):
            throw DecodingError.dataCorruptedError(
                forKey: refKey,
                in: container,
                debugDescription: "element predicate accepts either \(literalKey.stringValue) or \(refKey.stringValue), not both"
            )
        case (true, nil):
            return []
        }
    }

    private static func encode(
        _ expressions: [StringMatch<StringExpr>],
        literalKey: CodingKeys,
        refKey: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if expressions.isEmpty {
            return
        }
        if expressions.count == 1, case .exact(.ref(let reference)) = expressions[0] {
            try container.encode(reference, forKey: refKey)
            return
        }
        try StringMatch<StringExpr>.encodeOneOrMany(expressions, to: &container, forKey: literalKey)
    }
}

extension ElementPredicateTemplate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("predicate", [
            Self.stringMatchFields("label", labelMatches),
            Self.stringMatchFields("identifier", identifierMatches),
            Self.stringMatchFields("value", valueMatches),
            ScoreDescription.listField("traits", traits.isEmpty ? nil : traits),
            ScoreDescription.listField("excludeTraits", excludeTraits.isEmpty ? nil : excludeTraits),
        ].compactMap { $0 })
    }

    private static func stringMatchFields(_ name: String, _ values: [StringMatch<StringExpr>]) -> String? {
        guard !values.isEmpty else { return nil }
        return values.map { "\(name)=\($0)" }.joined(separator: " ")
    }
}
