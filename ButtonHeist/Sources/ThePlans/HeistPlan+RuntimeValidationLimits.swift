import Foundation

@_spi(ButtonHeistInternals) public struct HeistPlanRuntimeSafetyLimits: Sendable, Equatable {
    public static let standard = HeistPlanRuntimeSafetyLimits()

    public let maxTotalSteps: Int
    public let maxNestedStepDepth: Int
    public let maxPredicateDepth: Int
    public let maxAllPredicateChildren: Int
    public let maxForEachStringValues: Int
    public let maxForEachElementLimit: Int
    public let maxStringBytes: Int
    public let maxTotalStringBytes: Int
    public let maxParameterBytes: Int
    public let maxDefinitions: Int

    public init(
        maxTotalSteps: Int = 500,
        maxNestedStepDepth: Int = 16,
        maxPredicateDepth: Int = 12,
        maxAllPredicateChildren: Int = 20,
        maxForEachStringValues: Int = 100,
        maxForEachElementLimit: Int = 100,
        maxStringBytes: Int = 4_096,
        maxTotalStringBytes: Int = 65_536,
        maxParameterBytes: Int = 64,
        maxDefinitions: Int = .max
    ) {
        self.maxTotalSteps = maxTotalSteps
        self.maxNestedStepDepth = maxNestedStepDepth
        self.maxPredicateDepth = maxPredicateDepth
        self.maxAllPredicateChildren = maxAllPredicateChildren
        self.maxForEachStringValues = maxForEachStringValues
        self.maxForEachElementLimit = maxForEachElementLimit
        self.maxStringBytes = maxStringBytes
        self.maxTotalStringBytes = maxTotalStringBytes
        self.maxParameterBytes = maxParameterBytes
        self.maxDefinitions = maxDefinitions
    }
}
