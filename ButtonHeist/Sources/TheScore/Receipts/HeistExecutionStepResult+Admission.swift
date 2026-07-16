import Foundation
import ThePlans

extension HeistExecutionStepResult {
    package static func admitAction(
        path: HeistExecutionPath,
        durationMs: Int,
        command: HeistActionCommand,
        completion: HeistActionCompletion
    ) -> HeistReceiptAdmission {
        guard let node = HeistExecutionStepNode.admitAction(command: command, completion: completion) else {
            return .rejected(.actionEvidenceMismatch)
        }
        return .admitted(.init(path: path, durationMs: durationMs, node: node))
    }

    package static func wait(
        path: HeistExecutionPath,
        durationMs: Int,
        predicate: AccessibilityPredicate,
        timeout: WaitTimeout,
        completion: HeistWaitCompletion
    ) -> Self {
        .init(path: path, durationMs: durationMs, node: .wait(predicate: predicate, timeout: timeout, completion: completion))
    }

    package static func conditional(
        path: HeistExecutionPath, durationMs: Int, completion: HeistCaseSelectionCompletion
    ) -> Self { .init(path: path, durationMs: durationMs, node: .conditional(completion: completion)) }

    package static func admitForEachElement(
        path: HeistExecutionPath,
        durationMs: Int,
        declaration: HeistForEachElementDeclaration,
        completion: HeistForEachElementCompletion
    ) -> HeistReceiptAdmission {
        guard let node = HeistExecutionStepNode.admitForEachElement(
            declaration: declaration,
            completion: completion,
            iteration: false
        ) else { return .rejected(.forEachElementEvidenceMismatch) }
        return .admitted(.init(path: path, durationMs: durationMs, node: node))
    }

    package static func admitForEachString(
        path: HeistExecutionPath,
        durationMs: Int,
        declaration: HeistForEachStringDeclaration,
        completion: HeistForEachStringCompletion
    ) -> HeistReceiptAdmission {
        guard let node = HeistExecutionStepNode.admitForEachString(
            declaration: declaration,
            completion: completion,
            iteration: false
        ) else { return .rejected(.forEachStringEvidenceMismatch) }
        return .admitted(.init(path: path, durationMs: durationMs, node: node))
    }

    package static func admitForEachElementIteration(
        path: HeistExecutionPath,
        durationMs: Int,
        declaration: HeistForEachElementDeclaration,
        completion: HeistForEachElementCompletion
    ) -> HeistReceiptAdmission {
        guard let node = HeistExecutionStepNode.admitForEachElement(
            declaration: declaration,
            completion: completion,
            iteration: true
        ) else { return .rejected(.forEachElementEvidenceMismatch) }
        return .admitted(.init(path: path, durationMs: durationMs, node: node))
    }

    package static func admitForEachStringIteration(
        path: HeistExecutionPath,
        durationMs: Int,
        declaration: HeistForEachStringDeclaration,
        completion: HeistForEachStringCompletion
    ) -> HeistReceiptAdmission {
        guard let node = HeistExecutionStepNode.admitForEachString(
            declaration: declaration,
            completion: completion,
            iteration: true
        ) else { return .rejected(.forEachStringEvidenceMismatch) }
        return .admitted(.init(path: path, durationMs: durationMs, node: node))
    }

    package static func admitRepeatUntil(
        path: HeistExecutionPath,
        durationMs: Int,
        declaration: HeistRepeatUntilDeclaration,
        completion: HeistRepeatUntilCompletion
    ) -> HeistReceiptAdmission {
        guard let node = HeistExecutionStepNode.admitRepeatUntil(
            declaration: declaration,
            completion: completion
        ) else { return .rejected(.repeatUntilEvidenceMismatch) }
        return .admitted(.init(path: path, durationMs: durationMs, node: node))
    }

    package static func admitRepeatUntilIteration(
        path: HeistExecutionPath,
        durationMs: Int,
        declaration: HeistRepeatUntilDeclaration,
        completion: HeistRepeatUntilIterationCompletion
    ) -> HeistReceiptAdmission {
        guard let node = HeistExecutionStepNode.admitRepeatUntil(
            declaration: declaration,
            completion: completion
        ) else { return .rejected(.repeatUntilEvidenceMismatch) }
        return .admitted(.init(path: path, durationMs: durationMs, node: node))
    }

    package static func skipped(
        path: HeistExecutionPath,
        durationMs: Int,
        step: HeistStep
    ) -> Self {
        var children = HeistSkippedChildren.empty
        if case .heist(let plan) = step {
            for (index, child) in plan.body.enumerated() {
                children.append(
                    path: path.heistBody().step(at: index),
                    durationMs: 0,
                    step: child
                )
            }
        }
        let node: HeistExecutionStepNode
        switch step {
        case .action(let action):
            node = .action(command: action.command, completion: .skipped(children: children))
        case .wait(let wait):
            node = .wait(predicate: wait.predicate, timeout: wait.timeout, completion: .skipped(children: children))
        case .conditional:
            node = .conditional(completion: .skipped(children: children))
        case .forEachElement(let loop):
            node = .forEachElement(declaration: .init(loop), completion: .skipped(children: children))
        case .forEachString(let loop):
            node = .forEachString(declaration: .init(loop), completion: .skipped(children: children))
        case .repeatUntil(let loop):
            node = .repeatUntil(declaration: .init(loop), completion: .skipped(children: children))
        case .warn(let warning):
            node = .warning(message: warning.message, completion: .skipped(children: children))
        case .fail(let failure):
            node = .failure(message: failure.message, completion: .skipped(children: children))
        case .heist(let plan):
            node = .heist(name: plan.name, completion: .skipped(children: children))
        case .invoke(let invocation):
            node = .invocation(
                path: invocation.path,
                argument: invocation.argument,
                completion: .skipped(children: children)
            )
        }
        return .init(path: path, durationMs: durationMs, node: node)
    }

    package static func warning(
        path: HeistExecutionPath, durationMs: Int, message: HeistWarningMessage, completion: HeistWarningCompletion
    ) -> Self { .init(path: path, durationMs: durationMs, node: .warning(message: message, completion: completion)) }

    package static func failure(
        path: HeistExecutionPath, durationMs: Int, message: HeistFailureMessage, completion: HeistFailureCompletion
    ) -> Self { .init(path: path, durationMs: durationMs, node: .failure(message: message, completion: completion)) }

    package static func heist(
        path: HeistExecutionPath, durationMs: Int, name: HeistPlanName?, completion: HeistGroupCompletion
    ) -> Self { .init(path: path, durationMs: durationMs, node: .heist(name: name, completion: completion)) }

    package static func invocation(
        path: HeistExecutionPath,
        durationMs: Int,
        invocationPath: HeistInvocationPath,
        argument: HeistArgument,
        completion: HeistInvocationCompletion
    ) -> Self {
        .init(
            path: path,
            durationMs: durationMs,
            node: .invocation(path: invocationPath, argument: argument, completion: completion)
        )
    }

}

package enum HeistReceiptAdmission: Sendable, Equatable {
    case admitted(HeistExecutionStepResult)
    case rejected(HeistReceiptAdmissionError)

    package var receipt: HeistExecutionStepResult? {
        guard case .admitted(let receipt) = self else { return nil }
        return receipt
    }
}

package enum HeistReceiptAdmissionError: String, Sendable, Equatable, CustomStringConvertible {
    case actionEvidenceMismatch
    case evidenceConstructionFailed
    case forEachElementEvidenceMismatch
    case forEachStringEvidenceMismatch
    case repeatUntilEvidenceMismatch

    package var description: String { rawValue }
}
