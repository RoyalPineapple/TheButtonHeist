import Foundation

public enum HeistStepEvidence: Codable, Sendable, Equatable {
    case action(HeistActionEvidence)
    case wait(HeistWaitEvidence)
    case caseSelection(HeistCaseSelectionEvidence)
    case forEachString(HeistForEachStringEvidence)
    case forEachElement(HeistForEachElementEvidence)
    case repeatUntil(HeistRepeatUntilEvidence)
    case invocation(HeistInvocationEvidence)
    case warning(HeistExecutionWarning)
}

public enum HeistPredicateEvidenceOutcome: String, Codable, Sendable, Equatable {
    case matched
    case continued
    case handledElse = "handled_else"
    case failed
}
