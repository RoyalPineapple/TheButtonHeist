import Foundation

package struct HeistPlanRuntimeSafetyLimits: Sendable, Equatable {
    package static let standard = HeistPlanRuntimeSafetyLimits()
    package static let standardMaxDefinitions = 250

    package let maxTotalSteps: Int
    package let maxNestedStepDepth: Int
    package let maxPredicateDepth: Int
    package let maxAllPredicateChildren: Int
    package let maxForEachStringValues: Int
    package let maxForEachElementLimit: Int
    package let maxRepeatUntilTimeout: WaitTimeout
    package let maxStringBytes: Int
    package let maxTotalStringBytes: Int
    package let maxParameterBytes: Int
    package let maxDefinitions: Int

    package init(
        maxTotalSteps: Int = 500,
        maxNestedStepDepth: Int = 16,
        maxPredicateDepth: Int = 12,
        maxAllPredicateChildren: Int = 20,
        maxForEachStringValues: Int = 100,
        maxForEachElementLimit: Int = 100,
        maxRepeatUntilTimeout: WaitTimeout = defaultWaitTimeout,
        maxStringBytes: Int = 4_096,
        maxTotalStringBytes: Int = 65_536,
        maxParameterBytes: Int = 64,
        maxDefinitions: Int = Self.standardMaxDefinitions
    ) {
        self.maxTotalSteps = maxTotalSteps
        self.maxNestedStepDepth = maxNestedStepDepth
        self.maxPredicateDepth = maxPredicateDepth
        self.maxAllPredicateChildren = maxAllPredicateChildren
        self.maxForEachStringValues = maxForEachStringValues
        self.maxForEachElementLimit = maxForEachElementLimit
        self.maxRepeatUntilTimeout = maxRepeatUntilTimeout
        self.maxStringBytes = maxStringBytes
        self.maxTotalStringBytes = maxTotalStringBytes
        self.maxParameterBytes = maxParameterBytes
        self.maxDefinitions = maxDefinitions
    }
}
