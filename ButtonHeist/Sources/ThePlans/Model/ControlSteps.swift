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

    public let predicate: ChangeDeclaration.ScreenAssertion
    public let body: [HeistStep]

    public init(predicate: ChangeDeclaration.ScreenAssertion, body: [HeistStep]) {
        self.predicate = predicate
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "predicate case")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            predicate: try container.decode(ChangeDeclaration.ScreenAssertion.self, forKey: .predicate),
            body: try container.decode([HeistStep].self, forKey: .body)
        )
    }
}
