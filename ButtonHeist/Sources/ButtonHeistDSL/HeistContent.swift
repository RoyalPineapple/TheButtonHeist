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
        let data = try JSONEncoder().encode(HeistPlan(steps: steps))
        return try JSONDecoder().decode(HeistPlan.self, from: data)
    }
}

extension HeistStep: HeistContent {
    public var heistSteps: [HeistStep] { [self] }
}

extension HeistPlan: HeistContent {
    public var heistSteps: [HeistStep] { steps }
}

extension Array: HeistContent where Element == HeistStep {
    public var heistSteps: [HeistStep] { self }
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

    public static func buildExpression(_ expression: [HeistStep]) -> some HeistContent {
        expression
    }

    public static func buildExpression(_ expression: [some HeistContent]) -> some HeistContent {
        HeistStepList(expression.flatMap(\.heistSteps))
    }

    public static func buildBlock(_ components: any HeistContent...) -> some HeistContent {
        HeistStepList(components.flatMap(\.heistSteps))
    }

    public static func buildArray(_ components: [any HeistContent]) -> some HeistContent {
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

    public init<Data: Sequence>(_ data: Data, @HeistBuilder content: (Data.Element) throws -> Content) rethrows {
        self.heistSteps = try data.flatMap { element in
            try content(element).heistSteps
        }
    }

    public init(
        _ matches: ElementMatches,
        limit: Int = 20,
        @HeistBuilder _ content: (ElementTarget) throws -> Content
    ) throws {
        let element = ElementTarget.predicate(matches.predicate, ordinal: ForEach.runtimeElementInitialOrdinal)
        self.heistSteps = [
            .forEach(try ForEachStep(
                matching: matches.predicate,
                limit: limit,
                element: element,
                steps: try content(element).heistSteps
            )),
        ]
    }

    private static var runtimeElementInitialOrdinal: Int { 0 }
}
