import TheScore

public protocol HeistContent {
    var heistSteps: [HeistStep] { get }
}

public struct Heist: HeistContent {
    public let plan: HeistPlan

    public var heistSteps: [HeistStep] { plan.steps }

    public init(@HeistBuilder _ content: () throws -> some HeistContent) rethrows {
        self.plan = HeistPlan(steps: try content().heistSteps)
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

public struct ForEach<Data: Sequence, Content: HeistContent>: HeistContent {
    public let heistSteps: [HeistStep]

    public init(_ data: Data, @HeistBuilder content: (Data.Element) throws -> Content) rethrows {
        self.heistSteps = try data.flatMap { element in
            try content(element).heistSteps
        }
    }
}
