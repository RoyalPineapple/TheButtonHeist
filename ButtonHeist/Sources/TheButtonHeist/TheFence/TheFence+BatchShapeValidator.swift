import Foundation

import TheScore

extension TheFence {

    enum BatchShapeValidator {
        static func rejectUnsupportedShapes(request: ParsedRequest) throws {
            switch request.payload {
            case .scroll(.scroll(let target)):
                try rejectContainerTargetedScroll(target.containerTarget, command: request.command)
            case .scroll(.scrollToEdge(let target)):
                try rejectContainerTargetedScroll(target.containerTarget, command: request.command)
            case .accessibility(.increment(_, let count)):
                try rejectRepeatedCount(count, command: request.command)
            case .accessibility(.decrement(_, let count)):
                try rejectRepeatedCount(count, command: request.command)
            case .accessibility(.performCustomAction(_, let count)):
                try rejectObservedCount(count, command: request.command)
            default:
                return
            }
        }

        static func rejectRepeatedCount(_ count: CountArgument, command: Command) throws {
            guard let value = count.value, value != 1 else { return }
            throw BatchStepPlanBuildError(
                message: "run_batch step command \"\(command.rawValue)\" with count > 1 is not supported by typed batch execution"
            )
        }

        static func rejectObservedCount(_ count: CountArgument, command: Command) throws {
            guard count.observed != nil else { return }
            throw BatchStepPlanBuildError(
                message: "run_batch step command \"\(command.rawValue)\" does not support count in typed batch execution"
            )
        }

        static func rejectContainerTargetedScroll(
            _ containerTarget: ScrollContainerTarget?,
            command: Command
        ) throws {
            guard containerTarget != nil else { return }
            throw BatchStepPlanBuildError(
                message: "run_batch step command \"\(command.rawValue)\" does not support container-targeted scrolling; " +
                    "use an element target in run_batch or call \(command.rawValue) outside run_batch"
            )
        }
    }

    private enum BatchAccessibilityActionKind {
        case activate
        case increment
        case decrement
        case custom(String)
    }

    struct BatchAccessibilityActionShape {
        private let kind: BatchAccessibilityActionKind

        init(actionName: String?, count: CountArgument, command: Command) throws {
            guard let actionName else {
                try BatchShapeValidator.rejectObservedCount(count, command: command)
                kind = .activate
                return
            }

            switch actionName {
            case Command.increment.rawValue:
                try BatchShapeValidator.rejectRepeatedCount(count, command: command)
                kind = .increment
            case Command.decrement.rawValue:
                try BatchShapeValidator.rejectRepeatedCount(count, command: command)
                kind = .decrement
            default:
                try BatchShapeValidator.rejectObservedCount(count, command: command)
                let customName = actionName.hasPrefix("action:")
                    ? String(actionName.dropFirst("action:".count))
                    : actionName
                guard !customName.isEmpty else {
                    throw BatchStepPlanBuildError(message: "action: prefix requires a name (e.g. \"action:myAction\")")
                }
                kind = .custom(customName)
            }
        }

        func action(target: SemanticActionTarget) -> TheScore.Action {
            switch kind {
            case .activate:
                return .activate(target)
            case .increment:
                return .increment(target)
            case .decrement:
                return .decrement(target)
            case .custom(let name):
                return .performCustomAction(BatchCustomActionTarget(target: target, actionName: name))
            }
        }
    }
}
