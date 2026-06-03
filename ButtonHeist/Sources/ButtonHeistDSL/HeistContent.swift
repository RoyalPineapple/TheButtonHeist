import Foundation
import TheScore

public protocol HeistContent {
    var heistSteps: [HeistStep] { get }
}

public struct Heist: HeistContent {
    public let plan: HeistPlan

    public var heistSteps: [HeistStep] { plan.steps }

    public func validate(_ mode: HeistPlanValidationMode) -> [HeistPlanValidationFinding] {
        plan.validate(mode)
    }

    public init(@HeistBuilder _ content: () throws -> some HeistContent) throws {
        let steps = try content().heistSteps
        self.plan = try HeistPlan.validatedDSLPlan(steps: steps)
    }
}

private extension HeistPlan {
    static func validatedDSLPlan(steps: [HeistStep]) throws -> HeistPlan {
        guard !steps.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [HeistPlanCodingKey("steps")],
                debugDescription: "HeistPlan requires at least one step"
            ))
        }
        return HeistPlan(steps: steps)
    }
}

private struct HeistPlanCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

extension HeistStep: HeistContent {
    public var heistSteps: [HeistStep] { [self] }
}

extension HeistPlan: HeistContent {
    public var heistSteps: [HeistStep] { steps }
}

public struct EmptyHeistContent: HeistContent {
    public let heistSteps: [HeistStep] = []

    public init() {}
}

@resultBuilder
public enum HeistBuilder {
    public static func buildExpression(_ expression: some HeistContent) -> some HeistContent {
        expression
    }

    public static func buildExpression(_ expression: HeistStep) -> some HeistContent {
        expression
    }

    public static func buildExpression(_ expression: HeistPlan) -> some HeistContent {
        expression
    }

    public static func buildBlock(_ components: any HeistContent...) -> some HeistContent {
        HeistStepList(components.flatMap(\.heistSteps))
    }

    public static func buildOptional(_ component: (any HeistContent)?) -> some HeistContent {
        HeistStepList(component?.heistSteps ?? [])
    }

    public static func buildEither(first component: some HeistContent) -> some HeistContent {
        component
    }

    public static func buildEither(second component: some HeistContent) -> some HeistContent {
        component
    }

    public static func buildLimitedAvailability(_ component: some HeistContent) -> some HeistContent {
        component
    }
}

private struct HeistStepList: HeistContent {
    let heistSteps: [HeistStep]

    init(_ heistSteps: [HeistStep]) {
        self.heistSteps = heistSteps
    }
}

public struct ElementMatches: Sendable, Equatable {
    public let predicate: ElementPredicate

    public init(predicate: ElementPredicate) {
        self.predicate = predicate
    }

    public static func matching(_ predicate: ElementPredicate) -> ElementMatches {
        ElementMatches(predicate: predicate)
    }
}

public struct ForEach<Content: HeistContent>: HeistContent {
    public let heistSteps: [HeistStep]

    public init(
        _ values: [String],
        parameter: String = "item",
        @HeistBuilder content: (StringExpr) throws -> Content
    ) throws {
        let item = try StringExpr(ref: parameter)
        let steps = try content(item).heistSteps
        self.heistSteps = [
            .forEachString(try ForEachStringStep(
                values: values,
                parameter: parameter,
                steps: steps
            )),
        ]
    }

    public init(
        _ matches: ElementMatches,
        limit: Int = 20,
        parameter: String = "target",
        @HeistBuilder _ content: (ElementTargetExpr) throws -> Content
    ) throws {
        let target = try ElementTargetExpr(ref: parameter)
        let steps = try content(target).heistSteps
        let step = try ForEachElementStep(
            matching: matches.predicate,
            limit: limit,
            parameter: parameter,
            steps: steps
        )
        self.heistSteps = [.forEachElement(step)]
    }
}
