import Foundation
import ThePlans

struct HeistStepFacts {
    let status: HeistExecutionStepStatus
    let failure: HeistFailureDetail?
    let children: [HeistExecutionStepResult]
    let abortedAtChildPath: HeistExecutionPath?
}

package enum HeistExecutionStepNode: Codable, Sendable, Equatable {
    case action(command: HeistActionCommand, completion: HeistActionCompletion)
    case wait(predicate: AccessibilityPredicate, timeout: WaitTimeout, completion: HeistWaitCompletion)
    case conditional(completion: HeistCaseSelectionCompletion)
    case forEachElement(declaration: HeistForEachElementDeclaration, completion: HeistForEachElementCompletion)
    case forEachElementIteration(
        declaration: HeistForEachElementDeclaration,
        completion: HeistForEachElementCompletion
    )
    case forEachString(declaration: HeistForEachStringDeclaration, completion: HeistForEachStringCompletion)
    case forEachStringIteration(
        declaration: HeistForEachStringDeclaration,
        completion: HeistForEachStringCompletion
    )
    case repeatUntil(declaration: HeistRepeatUntilDeclaration, completion: HeistRepeatUntilCompletion)
    case repeatUntilIteration(
        declaration: HeistRepeatUntilDeclaration,
        completion: HeistRepeatUntilIterationCompletion
    )
    case warning(message: HeistWarningMessage, completion: HeistWarningCompletion)
    case failure(message: HeistFailureMessage, completion: HeistFailureCompletion)
    case heist(name: HeistPlanName?, completion: HeistGroupCompletion)
    case invocation(path: HeistInvocationPath, argument: HeistArgument, completion: HeistInvocationCompletion)

    package var constructionError: HeistReceiptConstructionError? {
        switch self {
        case .action(let command, let completion):
            let evidence: HeistActionEvidence?
            switch completion {
            case .passed(let value, _), .childAborted(let value, _, _): evidence = value.value
            case .failed(let value, _, _): evidence = value.value
            case .skipped: evidence = nil
            }
            return evidence?.matches(command: command) == false ? .actionEvidenceMismatch : nil

        case .forEachElement(let declaration, let completion),
             .forEachElementIteration(let declaration, let completion):
            let evidence: HeistForEachElementEvidence?
            let requiresAdmittedCount: Bool
            switch completion {
            case .passed(let value, _):
                evidence = value.value
                requiresAdmittedCount = true
            case .failed(let value, _, _):
                evidence = value.value?.value
                requiresAdmittedCount = false
            case .childAborted(let value, _, _):
                evidence = value.value
                requiresAdmittedCount = true
            case .skipped:
                evidence = nil
                requiresAdmittedCount = false
            }
            let iteration = isForEachIteration
            let legal = evidence.map {
                (!requiresAdmittedCount || $0.matchedCount <= declaration.limit)
                    && ($0.iterationOrdinal != nil) == iteration
            } ?? true
            return legal ? nil : .forEachElementEvidenceMismatch

        case .forEachString(let declaration, let completion),
             .forEachStringIteration(let declaration, let completion):
            let evidence: HeistForEachStringEvidence?
            switch completion {
            case .passed(let value, _): evidence = value.value
            case .failed(let value, _, _): evidence = value.value?.value
            case .childAborted(let value, _, _): evidence = value.value
            case .skipped: evidence = nil
            }
            let iteration = isForEachIteration
            let legal = evidence.map {
                $0.iterationCount <= declaration.count && ($0.iterationOrdinal != nil) == iteration
            } ?? true
            return legal ? nil : .forEachStringEvidenceMismatch

        case .repeatUntil(let declaration, let completion):
            let evidence: HeistRepeatUntilEvidence?
            switch completion {
            case .passed(let value, _): evidence = value.value
            case .failed(let value, _, _): evidence = value.value?.value
            case .childAborted(let value, _, _): evidence = value.value
            case .skipped: evidence = nil
            }
            return Self.repeatEvidence(evidence, matches: declaration, iteration: false)
                ? nil
                : .repeatUntilEvidenceMismatch

        case .repeatUntilIteration(let declaration, let completion):
            let evidence: HeistRepeatUntilEvidence?
            switch completion {
            case .passed(let value, _): evidence = value.value
            case .failed(let value, _, _): evidence = value.value?.value
            case .childAborted(let value, _, _): evidence = value.value
            case .skipped: evidence = nil
            }
            return Self.repeatEvidence(evidence, matches: declaration, iteration: true)
                ? nil
                : .repeatUntilEvidenceMismatch

        case .wait, .conditional, .warning, .failure, .heist, .invocation:
            return nil
        }
    }

    private var isForEachIteration: Bool {
        switch self {
        case .forEachElementIteration, .forEachStringIteration:
            return true
        default:
            return false
        }
    }

    private static func repeatEvidence(
        _ evidence: HeistRepeatUntilEvidence?,
        matches declaration: HeistRepeatUntilDeclaration,
        iteration: Bool
    ) -> Bool {
        guard let evidence else { return true }
        return (evidence.expectation.predicate.map { $0 == declaration.predicate } ?? true)
            && (evidence.iterationOrdinal != nil) == iteration
    }

    var facts: HeistStepFacts {
        switch self {
        case .action(_, let completion): completion.facts
        case .wait(_, _, let completion): completion.facts
        case .conditional(let completion): completion.facts
        case .forEachElement(_, let completion),
             .forEachElementIteration(_, let completion): completion.facts
        case .forEachString(_, let completion),
             .forEachStringIteration(_, let completion): completion.facts
        case .repeatUntil(_, let completion): completion.facts
        case .repeatUntilIteration(_, let completion): completion.facts
        case .invocation(_, _, let completion): completion.facts
        case .warning(_, .passed(let children)):
            .init(status: .passed, failure: nil, children: children.values, abortedAtChildPath: nil)
        case .warning(_, .skipped(let children)), .failure(_, .skipped(let children)):
            .init(status: .skipped, failure: nil, children: children.values, abortedAtChildPath: nil)
        case .failure(_, .failed(let failure, let children)):
            .init(status: .failed, failure: failure, children: children.values, abortedAtChildPath: nil)
        case .failure(_, .childAborted(let failure, let children)):
            .init(
                status: .failed,
                failure: failure,
                children: children.values,
                abortedAtChildPath: children.abortedAtPath
            )
        case .heist(_, .passed(let children)):
            .init(status: .passed, failure: nil, children: children.values, abortedAtChildPath: nil)
        case .heist(_, .childAborted(let failure, let children)):
            .init(
                status: .failed,
                failure: failure,
                children: children.values,
                abortedAtChildPath: children.abortedAtPath
            )
        case .heist(_, .skipped(let children)):
            .init(status: .skipped, failure: nil, children: children.values, abortedAtChildPath: nil)
        }
    }

}
