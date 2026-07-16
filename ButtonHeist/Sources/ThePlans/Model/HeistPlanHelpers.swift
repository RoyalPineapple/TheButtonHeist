import Foundation

public enum HeistPlanError: Error, Sendable, Equatable {
    case unsupportedActionCommand(String)
    case ambiguousExpectationContract
    case emptyExpectationWaiver
    case expectationElseBodyUnsupported
    case emptyPredicateCases(String)
    case negativeTimeout(Double)
    case emptyForEachPredicate
    case invalidForEachLimit(Int)
    case emptyForEachSteps
    case emptyForEachValues
    case emptyRepeatUntilSteps
    case nestedForEachUnsupported
}

public extension HeistPlan {
    func heistDefinition(at path: HeistDefinitionPath) -> HeistPlan? {
        let invocationPath = HeistInvocationPath(definitionPath: path)
        return HeistDefinitionScope(definitions: definitions).resolve(path: invocationPath)?.definition
    }
}
