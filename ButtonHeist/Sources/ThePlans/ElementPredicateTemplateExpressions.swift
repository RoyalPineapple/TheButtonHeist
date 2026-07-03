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
        hint: StringMatch<StringExpr>? = nil,
        actions: [ElementAction] = [],
        customContent: CustomContentMatch<StringExpr>? = nil,
        rotors: [StringMatch<StringExpr>] = []
    ) {
        self.init(Self.checks(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits,
            hint: hint,
            actions: actions,
            customContent: customContent,
            rotors: rotors
        ))
    }

    public init(
        _ checks: [ElementPredicateCheck<StringExpr>],
        traits: [HeistTrait] = [],
        actions: [ElementAction] = []
    ) {
        self.init(checks + Self.setChecks(
            traits: traits,
            actions: actions
        ))
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
        hint: StringMatch<StringExpr>?,
        actions: [ElementAction],
        customContent: CustomContentMatch<StringExpr>?,
        rotors: [StringMatch<StringExpr>]
    ) -> [ElementPredicateCheck<StringExpr>] {
        var checks: [ElementPredicateCheck<StringExpr>] = []
        if let label { checks.append(.label(label)) }
        if let identifier { checks.append(.identifier(identifier)) }
        if let value { checks.append(.value(value)) }
        if let hint { checks.append(.hint(hint)) }
        if let customContent { checks.append(.customContent(customContent)) }
        if !rotors.isEmpty { checks.append(.rotors(rotors)) }
        checks += setChecks(
            traits: traits,
            actions: actions
        )
        return checks
    }

    private static func setChecks(
        traits: [HeistTrait],
        actions: [ElementAction]
    ) -> [ElementPredicateCheck<StringExpr>] {
        var checks: [ElementPredicateCheck<StringExpr>] = []
        let traits = traits.heistTraitSet
        if !traits.isEmpty { checks.append(.traits(traits)) }
        let actions = Set(actions)
        if !actions.isEmpty { checks.append(.actions(actions)) }
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
        case .hint(let match):
            guard match.hasPredicateLiteral else { return nil }
            return "hint=\(match)"
        case .traits(let traits):
            let traits = traits.canonicalHeistTraitArray
            return ScoreDescription.listField("traits", traits.isEmpty ? nil : traits)
        case .actions(let actions):
            return ScoreDescription.listField("actions", actions.isEmpty ? nil : actions.canonicalElementActionArray)
        case .customContent(let match):
            guard match.hasPredicateLiteral else { return nil }
            return "customContent=\(match)"
        case .rotors(let matches):
            return matches.isEmpty ? nil : "rotors=[\(matches.map(\.description).joined(separator: ", "))]"
        case .exclude(let check):
            guard let field = checkField(check) else { return nil }
            return "exclude(\(field))"
        }
    }
}

private extension ElementPredicateCheck where Text == StringExpr {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ElementPredicateCheck<String> {
        switch self {
        case .label(let match):
            return try .label(match.resolve(in: environment))
        case .identifier(let match):
            return try .identifier(match.resolve(in: environment))
        case .value(let match):
            return try .value(match.resolve(in: environment))
        case .hint(let match):
            return try .hint(match.resolve(in: environment))
        case .traits(let traits):
            return .traits(traits)
        case .actions(let actions):
            return .actions(actions)
        case .customContent(let match):
            return try .customContent(match.map { try $0.resolve(in: environment) })
        case .rotors(let matches):
            return try .rotors(matches.map { try $0.resolve(in: environment) })
        case .exclude(let check):
            return try .exclude(check.resolve(in: environment))
        }
    }
}
