import Foundation

// MARK: - Element Predicate Templates

public struct ElementPredicateTemplate: Codable, Sendable, Equatable, Hashable {
    public let checks: [ElementPredicateCheck<StringExpr>]

    public init(_ checks: [ElementPredicateCheck<StringExpr>] = []) {
        self.checks = checks
    }

    public init(
        label: StringMatch<StringExpr>? = nil,
        identifier: StringMatch<StringExpr>? = nil,
        value: StringMatch<StringExpr>? = nil,
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) {
        self.init(Self.checks(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            excludeTraits: excludeTraits
        ))
    }

    public init(
        _ checks: [ElementPredicateCheck<StringExpr>],
        traits: [HeistTrait] = [],
        excludeTraits: [HeistTrait] = []
    ) {
        self.init(checks + Self.traitChecks(traits: traits, excludeTraits: excludeTraits))
    }

    public init(_ predicate: ElementPredicate) {
        self.init(predicate.checks.map { $0.map(StringExpr.literal) })
    }

    public var hasPredicates: Bool {
        checks.contains { $0.hasPredicateLiteral }
    }

    public func resolve(in environment: HeistExecutionEnvironment) throws -> ElementPredicate {
        ElementPredicate(try checks.map { try $0.resolve(in: environment) })
    }

    private static func checks(
        label: StringMatch<StringExpr>?,
        identifier: StringMatch<StringExpr>?,
        value: StringMatch<StringExpr>?,
        traits: [HeistTrait],
        excludeTraits: [HeistTrait]
    ) -> [ElementPredicateCheck<StringExpr>] {
        var checks: [ElementPredicateCheck<StringExpr>] = []
        if let label { checks.append(.label(label)) }
        if let identifier { checks.append(.identifier(identifier)) }
        if let value { checks.append(.value(value)) }
        checks += traitChecks(traits: traits, excludeTraits: excludeTraits)
        return checks
    }

    private static func traitChecks(
        traits: [HeistTrait],
        excludeTraits: [HeistTrait]
    ) -> [ElementPredicateCheck<StringExpr>] {
        var checks: [ElementPredicateCheck<StringExpr>] = []
        let traits = traits.heistTraitSet
        let excludeTraits = excludeTraits.heistTraitSet
        if !traits.isEmpty { checks.append(.traits(traits)) }
        if !excludeTraits.isEmpty { checks.append(.excludeTraits(excludeTraits)) }
        return checks
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case checks
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
        checks = try container.decodeIfPresent([ElementPredicateCheck<StringExpr>].self, forKey: .checks) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !checks.isEmpty { try container.encode(checks, forKey: .checks) }
    }

}

extension ElementPredicateTemplate: CustomStringConvertible {
    public var description: String {
        ScoreDescription.call("predicate", checks.compactMap(Self.checkField))
    }

    private static func checkField(_ check: ElementPredicateCheck<StringExpr>) -> String? {
        switch check {
        case .label(let match):
            guard match.hasPredicateLiteral else { return nil }
            return "label=\(match)"
        case .identifier(let match):
            guard match.hasPredicateLiteral else { return nil }
            return "identifier=\(match)"
        case .value(let match):
            guard match.hasPredicateLiteral else { return nil }
            return "value=\(match)"
        case .traits(let traits):
            let traits = traits.canonicalHeistTraitArray
            return ScoreDescription.listField("traits", traits.isEmpty ? nil : traits)
        case .excludeTraits(let traits):
            let traits = traits.canonicalHeistTraitArray
            return ScoreDescription.listField("excludeTraits", traits.isEmpty ? nil : traits)
        }
    }
}

private extension ElementPredicateCheck where Value == StringExpr {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ElementPredicateCheck<String> {
        switch self {
        case .label(let match):
            return try .label(match.resolve(in: environment))
        case .identifier(let match):
            return try .identifier(match.resolve(in: environment))
        case .value(let match):
            return try .value(match.resolve(in: environment))
        case .traits(let traits):
            return .traits(traits)
        case .excludeTraits(let traits):
            return .excludeTraits(traits)
        }
    }
}
