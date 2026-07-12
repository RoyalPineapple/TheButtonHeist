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

public struct RepeatUntilStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case predicate, timeout, body
        case elseBody = "else_body"
    }

    public let predicate: AccessibilityPredicate<RootContext>
    /// Seconds. `0` means only the initial predicate evaluation is checked before any else body.
    public let timeout: Double
    public let body: [HeistStep]
    public let elseBody: [HeistStep]?

    public init(
        predicate: AccessibilityPredicate<RootContext>,
        timeout: Double,
        body: [HeistStep],
        elseBody: [HeistStep]? = nil
    ) throws {
        guard timeout >= 0 else {
            throw HeistPlanError.negativeTimeout(timeout)
        }
        guard !body.isEmpty else {
            throw HeistPlanError.emptyRepeatUntilSteps
        }
        self.predicate = predicate
        self.timeout = timeout
        self.body = body
        self.elseBody = elseBody
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "repeat_until step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            predicate: try container.decode(AccessibilityPredicate<RootContext>.self, forKey: .predicate),
            timeout: try container.decode(Double.self, forKey: .timeout),
            body: try container.decode([HeistStep].self, forKey: .body),
            elseBody: try container.decodeIfPresent([HeistStep].self, forKey: .elseBody)
        )
    }
}

package struct ResolvedRepeatUntilStep: Sendable, Equatable {
    package let predicateExpression: AccessibilityPredicate<RootContext>
    package let predicate: AccessibilityPredicate<RootContext>
    package let timeout: Double
    package let body: [HeistStep]
    package let elseBody: [HeistStep]?

    package init(
        predicateExpression: AccessibilityPredicate<RootContext>,
        predicate: AccessibilityPredicate<RootContext>,
        timeout: Double,
        body: [HeistStep],
        elseBody: [HeistStep]? = nil
    ) {
        self.predicateExpression = predicateExpression
        self.predicate = predicate
        self.timeout = timeout
        self.body = body
        self.elseBody = elseBody
    }
}

package extension RepeatUntilStep {
    func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedRepeatUntilStep {
        ResolvedRepeatUntilStep(
            predicateExpression: predicate,
            predicate: try predicate.resolve(in: environment),
            timeout: timeout,
            body: body,
            elseBody: elseBody
        )
    }
}
