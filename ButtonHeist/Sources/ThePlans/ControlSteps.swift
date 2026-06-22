import Foundation

public struct ConditionalStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case cases
        case elseBody = "else_body"
    }

    public let cases: [PredicateCase]
    public let elseBody: [HeistStep]?

    public init(cases: [PredicateCase], elseBody: [HeistStep]? = nil) throws {
        guard !cases.isEmpty else {
            throw HeistPlanError.emptyPredicateCases("conditional")
        }
        self.cases = cases
        self.elseBody = elseBody
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "conditional step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            cases: try container.decode([PredicateCase].self, forKey: .cases),
            elseBody: try container.decodeIfPresent([HeistStep].self, forKey: .elseBody)
        )
    }
}

public struct PredicateCase: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, body
    }

    public let predicate: AccessibilityPredicateExpr
    public let body: [HeistStep]

    public init(predicate: AccessibilityPredicateExpr, body: [HeistStep]) {
        self.predicate = predicate
        self.body = body
    }

    @_disfavoredOverload
    public init(predicate: AccessibilityPredicate, body: [HeistStep]) {
        self.init(predicate: .predicate(predicate), body: body)
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "predicate case")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(AccessibilityPredicateExpr.self, forKey: .predicate),
            body: try container.decode([HeistStep].self, forKey: .body)
        )
    }
}

public extension PredicateCase {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedPredicateCase {
        ResolvedPredicateCase(
            predicate: try predicate.resolve(in: environment),
            body: body
        )
    }
}

public struct ResolvedPredicateCase: Sendable, Equatable {
    public let predicate: AccessibilityPredicate
    public let body: [HeistStep]
}
