import Foundation
import ThePlans

struct HeistStepFacts {
    let status: HeistExecutionStepStatus
    let failure: HeistFailureDetail?
    let children: [HeistExecutionStepResult]
    let abortedAtChildPath: HeistExecutionPath?
}

enum HeistExecutionStepNode: Codable, Sendable, Equatable {
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

    static func admitAction(
        command: HeistActionCommand,
        completion: HeistActionCompletion
    ) -> Self? {
        let evidence: HeistActionEvidence?
        switch completion {
        case .passed(let value, _), .childAborted(let value, _, _): evidence = value.value
        case .failed(let value, _, _): evidence = value.value
        case .skipped: evidence = nil
        }
        guard evidence?.matches(command: command) ?? true else { return nil }
        return .action(command: command, completion: completion)
    }

    static func admitForEachElement(
        declaration: HeistForEachElementDeclaration,
        completion: HeistForEachElementCompletion,
        iteration: Bool
    ) -> Self? {
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
        guard evidence.map({ evidence in
            (!requiresAdmittedCount || evidence.matchedCount <= declaration.limit)
                && (evidence.iterationOrdinal != nil) == iteration
        }) ?? true else { return nil }
        return iteration
            ? .forEachElementIteration(declaration: declaration, completion: completion)
            : .forEachElement(declaration: declaration, completion: completion)
    }

    static func admitForEachString(
        declaration: HeistForEachStringDeclaration,
        completion: HeistForEachStringCompletion,
        iteration: Bool
    ) -> Self? {
        let evidence: HeistForEachStringEvidence?
        switch completion {
        case .passed(let value, _): evidence = value.value
        case .failed(let value, _, _): evidence = value.value?.value
        case .childAborted(let value, _, _): evidence = value.value
        case .skipped: evidence = nil
        }
        guard evidence.map({
            $0.iterationCount <= declaration.count && ($0.iterationOrdinal != nil) == iteration
        }) ?? true else { return nil }
        return iteration
            ? .forEachStringIteration(declaration: declaration, completion: completion)
            : .forEachString(declaration: declaration, completion: completion)
    }

    static func admitRepeatUntil(
        declaration: HeistRepeatUntilDeclaration,
        completion: HeistRepeatUntilCompletion
    ) -> Self? {
        let evidence: HeistRepeatUntilEvidence?
        switch completion {
        case .passed(let value, _): evidence = value.value
        case .failed(let value, _, _): evidence = value.value?.value
        case .childAborted(let value, _, _): evidence = value.value
        case .skipped: evidence = nil
        }
        guard repeatEvidence(evidence, matches: declaration, iteration: false) else { return nil }
        return .repeatUntil(declaration: declaration, completion: completion)
    }

    static func admitRepeatUntil(
        declaration: HeistRepeatUntilDeclaration,
        completion: HeistRepeatUntilIterationCompletion
    ) -> Self? {
        let evidence: HeistRepeatUntilEvidence?
        switch completion {
        case .passed(let value, _): evidence = value.value
        case .failed(let value, _, _): evidence = value.value?.value
        case .childAborted(let value, _, _): evidence = value.value
        case .skipped: evidence = nil
        }
        guard repeatEvidence(evidence, matches: declaration, iteration: true) else { return nil }
        return .repeatUntilIteration(declaration: declaration, completion: completion)
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
