import Foundation

public struct ForEachElementStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case matching, limit, parameter, body
    }

    public let matching: ElementPredicate
    public let limit: Int
    public let parameter: HeistReferenceName
    public let body: [HeistStep]

    public init(
        matching: ElementPredicate,
        limit: Int,
        parameter: HeistReferenceName,
        body: [HeistStep]
    ) throws {
        guard matching.hasPredicates else {
            throw HeistPlanError.emptyForEachPredicate
        }
        guard limit > 0 else {
            throw HeistPlanError.invalidForEachLimit(limit)
        }
        guard !body.isEmpty else {
            throw HeistPlanError.emptyForEachSteps
        }
        let parameter = try HeistParameterName.normalized(parameter.rawValue)
        self.matching = matching
        self.limit = limit
        self.parameter = HeistReferenceName(rawValue: parameter)
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "for_each_element step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            matching: try container.decode(ElementPredicate.self, forKey: .matching),
            limit: try container.decode(Int.self, forKey: .limit),
            parameter: try HeistReferenceName.decode(from: container, forKey: .parameter, type: "for_each_element parameter"),
            body: try container.decode([HeistStep].self, forKey: .body)
        )
    }
}

public struct ForEachStringStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case values, parameter, body
    }

    public let values: [String]
    public let parameter: HeistReferenceName
    public let body: [HeistStep]

    public init(
        values: [String],
        parameter: HeistReferenceName,
        body: [HeistStep]
    ) throws {
        guard !values.isEmpty else {
            throw HeistPlanError.emptyForEachValues
        }
        guard !body.isEmpty else {
            throw HeistPlanError.emptyForEachSteps
        }
        let parameter = try HeistParameterName.normalized(parameter.rawValue)
        self.values = values
        self.parameter = HeistReferenceName(rawValue: parameter)
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "for_each_string step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            values: try container.decode([String].self, forKey: .values),
            parameter: try HeistReferenceName.decode(from: container, forKey: .parameter, type: "for_each_string parameter"),
            body: try container.decode([HeistStep].self, forKey: .body)
        )
    }
}
