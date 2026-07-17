import Foundation
import ThePlans

extension HeistExecutionStepResult {
    package static func construct(
        path: HeistExecutionPath,
        durationMs: Int,
        node: HeistExecutionStepNode
    ) throws -> Self {
        .init(path: path, durationMs: durationMs, node: try node.admitted())
    }

    package static func conditional(
        path: HeistExecutionPath, durationMs: Int, completion: HeistCaseSelectionCompletion
    ) -> Self { .init(path: path, durationMs: durationMs, node: .conditional(completion: completion)) }

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

package struct HeistReceiptAdmissionError: Error, Sendable, Equatable, CustomStringConvertible {
    package let description: String
}
