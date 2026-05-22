import Foundation

import TheScore

extension TheFence {

    struct BatchStepPlanBuildError: Error {
        let message: String
    }

    @ButtonHeistActor
    struct BatchStepConstructor {
        private let targetResolver: BatchTargetResolver

        init(fence: TheFence) {
            targetResolver = BatchTargetResolver(fence: fence)
        }

        func plan(
            index: Int,
            operation: NormalizedOperation,
            request: ParsedRequest
        ) throws -> RunBatchPreparedStep {
            let context = BatchStepPlanningContext(originalIndex: index, operation: operation, request: request)
            switch request.payload {
            case .gesture(let payload):
                return try gestureStep(payload, context: context)
            case .scroll(let payload):
                return try scrollStep(payload, context: context)
            case .accessibility(let payload):
                return try accessibilityStep(payload, context: context)
            case .rotor(let target):
                return try context.plan(action: .rotor(BatchRotorTarget(
                    target: targetResolver.requiredTarget(from: operation, fallback: target.elementTarget),
                    rotor: target.rotor,
                    rotorIndex: target.rotorIndex,
                    direction: target.direction,
                    currentSourceHeistId: target.currentHeistId,
                    currentTextRange: target.currentTextRange
                )))
            case .typeText(let target):
                return try context.plan(action: .typeText(BatchTypeTextTarget(
                    text: target.text,
                    target: targetResolver.optionalTarget(from: operation, fallback: target.elementTarget)
                )))
            case .editAction(let target):
                return context.plan(action: .editAction(target))
            case .setPasteboard(let target):
                return context.plan(action: .setPasteboard(target))
            case .none where request.command == .dismissKeyboard:
                return context.plan(action: .resignFirstResponder)
            case .waitFor(let target):
                return try waitForStep(target, context: context)
            case .waitForChange:
                let expectation = context.expectation ?? .screenChanged
                return context.plan(
                    action: .waitForChange(WaitForChangeTarget(expect: expectation, timeout: context.timeout)),
                    expectation: expectation,
                    timeout: context.timeout
                )
            default:
                throw BatchStepPlanBuildError(
                    message: "run_batch step command \"\(request.command.rawValue)\" is not a non-read batch Action"
                )
            }
        }

        private func gestureStep(
            _ payload: GesturePayload,
            context: BatchStepPlanningContext
        ) throws -> RunBatchPreparedStep {
            switch payload {
            case .oneFingerTap(let payload):
                return try context.plan(action: .touchTap(BatchTouchTapTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    pointX: payload.pointX,
                    pointY: payload.pointY
                )))
            case .longPress(let payload):
                return try context.plan(action: .touchLongPress(BatchLongPressTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    pointX: payload.pointX,
                    pointY: payload.pointY,
                    duration: payload.duration
                )))
            case .swipe(let payload):
                return try context.plan(action: .touchSwipe(BatchSwipeTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    startX: payload.startX,
                    startY: payload.startY,
                    endX: payload.endX,
                    endY: payload.endY,
                    direction: payload.direction,
                    duration: payload.duration,
                    start: payload.start,
                    end: payload.end
                )))
            case .drag(let payload):
                return try context.plan(action: .touchDrag(BatchDragTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    startX: payload.startX,
                    startY: payload.startY,
                    endX: payload.endX,
                    endY: payload.endY,
                    duration: payload.duration
                )))
            case .pinch(let payload):
                return try context.plan(action: .touchPinch(BatchPinchTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    centerX: payload.centerX,
                    centerY: payload.centerY,
                    scale: payload.scale,
                    spread: payload.spread,
                    duration: payload.duration
                )))
            case .rotate(let payload):
                return try context.plan(action: .touchRotate(BatchRotateTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    centerX: payload.centerX,
                    centerY: payload.centerY,
                    angle: payload.angle,
                    radius: payload.radius,
                    duration: payload.duration
                )))
            case .twoFingerTap(let payload):
                return try context.plan(action: .touchTwoFingerTap(BatchTwoFingerTapTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    centerX: payload.centerX,
                    centerY: payload.centerY,
                    spread: payload.spread
                )))
            case .drawPath(let payload):
                return context.plan(action: .touchDrawPath(payload.target))
            case .drawBezier(let payload):
                return context.plan(action: .touchDrawBezier(payload.target))
            }
        }

        private func scrollStep(
            _ payload: ScrollPayload,
            context: BatchStepPlanningContext
        ) throws -> RunBatchPreparedStep {
            switch payload {
            case .scroll(let target):
                try BatchShapeValidator.rejectContainerTargetedScroll(
                    target.containerTarget,
                    command: context.request.command
                )
                return try context.plan(action: .scroll(BatchScrollTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: target.elementTarget),
                    direction: target.direction
                )))
            case .scrollToVisible(let target):
                return try context.plan(action: .scrollToVisible(BatchScrollToVisibleTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: target.elementTarget)
                )))
            case .elementSearch(let target):
                return try context.plan(action: .elementSearch(BatchElementSearchTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: target.elementTarget),
                    direction: target.direction
                )))
            case .scrollToEdge(let target):
                try BatchShapeValidator.rejectContainerTargetedScroll(
                    target.containerTarget,
                    command: context.request.command
                )
                return try context.plan(action: .scrollToEdge(BatchScrollToEdgeTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: target.elementTarget),
                    edge: target.edge
                )))
            }
        }

        private func accessibilityStep(
            _ payload: AccessibilityPayload,
            context: BatchStepPlanningContext
        ) throws -> RunBatchPreparedStep {
            switch payload {
            case .activate(let target, let actionName, let count):
                return try context.plan(action: BatchAccessibilityActionShape(
                    actionName: actionName,
                    count: count,
                    command: context.request.command
                ).action(target: targetResolver.requiredTarget(from: context.operation, fallback: target)))
            case .increment(let target, let count):
                try BatchShapeValidator.rejectRepeatedCount(count, command: context.request.command)
                return try context.plan(action: .increment(targetResolver.requiredTarget(from: context.operation, fallback: target)))
            case .decrement(let target, let count):
                try BatchShapeValidator.rejectRepeatedCount(count, command: context.request.command)
                return try context.plan(action: .decrement(targetResolver.requiredTarget(from: context.operation, fallback: target)))
            case .performCustomAction(let target, let count):
                try BatchShapeValidator.rejectObservedCount(count, command: context.request.command)
                return try context.plan(action: customActionStep(target, context: context))
            }
        }

        private func customActionStep(
            _ target: CustomActionTarget,
            context: BatchStepPlanningContext
        ) throws -> TheScore.Action {
            if let elementTarget = target.elementTarget {
                return try .performCustomAction(BatchCustomActionTarget(
                    target: targetResolver.requiredTarget(from: context.operation, fallback: elementTarget),
                    actionName: target.actionName
                ))
            }
            guard let containerTarget = target.containerTarget else {
                throw MissingElementTarget(command: context.request.command.rawValue)
            }
            return .performCustomAction(BatchCustomActionTarget(
                containerTarget: containerTarget,
                ordinal: target.containerOrdinal,
                actionName: target.actionName
            ))
        }

        private func waitForStep(
            _ target: WaitForTarget,
            context: BatchStepPlanningContext
        ) throws -> RunBatchPreparedStep {
            let semanticTarget = targetResolver.executionTarget(from: context.operation, fallback: target.elementTarget)
            let resolvedTimeout = target.timeout ?? context.timeout
            let waitAction = TheScore.Action.waitForElement(BatchWaitForTarget(
                target: try targetResolver.requiredExecutionTarget(semanticTarget),
                absent: target.absent,
                timeout: resolvedTimeout
            ))
            return try context.plan(
                action: waitAction,
                expectation: targetResolver.waitExpectation(target: semanticTarget, absent: target.absent),
                timeout: resolvedTimeout
            )
        }
    }

    private struct BatchStepPlanningContext {
        let originalIndex: Int
        let operation: NormalizedOperation
        let request: ParsedRequest
        let expectation: ActionExpectation?
        let timeout: Double?

        init(originalIndex: Int, operation: NormalizedOperation, request: ParsedRequest) {
            self.originalIndex = originalIndex
            self.operation = operation
            self.request = request
            expectation = request.expectationPayload.expectation
            timeout = request.expectationPayload.timeout
        }

        func plan(
            action: TheScore.Action,
            expectation overrideExpectation: ActionExpectation? = nil,
            timeout overrideTimeout: Double? = nil
        ) -> RunBatchPreparedStep {
            let stepTimeout = overrideTimeout ?? timeout
            return RunBatchPreparedStep(
                originalIndex: originalIndex,
                commandName: request.command.rawValue,
                action: action,
                expectation: overrideExpectation ?? expectation ?? action.defaultExpectation,
                deadline: deadline(for: action, timeout: stepTimeout)
            )
        }

        private func deadline(for action: TheScore.Action, timeout: Double?) -> TheScore.Deadline {
            timeout.map(TheScore.Deadline.init(timeout:)) ?? action.defaultDeadline
        }
    }

    @ButtonHeistActor
    struct BatchTargetResolver {
        private let fence: TheFence

        init(fence: TheFence) {
            self.fence = fence
        }

        func executionTarget(
            from operation: NormalizedOperation,
            fallback target: ElementTarget?
        ) -> BatchExecutionTarget? {
            let argumentTarget = targetFromArguments(operation.arguments)
            if argumentTarget != nil { return argumentTarget }
            return targetFromElementTarget(target)
        }

        func optionalTarget(
            from operation: NormalizedOperation,
            fallback target: ElementTarget?
        ) throws -> BatchExecutionTarget? {
            try optionalExecutionTarget(executionTarget(from: operation, fallback: target))
        }

        func requiredTarget(
            from operation: NormalizedOperation,
            fallback target: ElementTarget?
        ) throws -> BatchExecutionTarget {
            try requiredExecutionTarget(executionTarget(from: operation, fallback: target))
        }

        func optionalExecutionTarget(_ target: BatchExecutionTarget?) throws -> BatchExecutionTarget? {
            guard let target else { return nil }
            return try executionTarget(target)
        }

        func requiredExecutionTarget(_ target: BatchExecutionTarget?) throws -> BatchExecutionTarget {
            guard let target else {
                throw BatchStepPlanBuildError(message: "typed batch target requires matcher predicates or ordinal fallback")
            }
            return try executionTarget(target)
        }

        func waitExpectation(
            target: BatchExecutionTarget?,
            absent: Bool?
        ) throws -> ActionExpectation {
            let matcher = try expectationMatcher(target)
            if absent == true {
                return .elementDisappeared(matcher)
            }
            return .elementAppeared(matcher)
        }

        private func expectationMatcher(_ target: BatchExecutionTarget?) throws -> ElementMatcher {
            guard let target else {
                throw BatchStepPlanBuildError(message: "typed batch expectation requires matcher predicates")
            }
            guard target.matcher.hasPredicates else {
                if let sourceHeistId = target.sourceHeistId {
                    throw BatchStepPlanBuildError(
                        message: "run_batch target \"\(sourceHeistId)\" needs matcher predicates for typed batch expectation; heistId is source metadata only"
                    )
                }
                throw BatchStepPlanBuildError(
                    message: "typed batch expectation requires matcher predicates"
                )
            }
            return target.matcher
        }

        private func executionTarget(_ target: BatchExecutionTarget) throws -> BatchExecutionTarget {
            guard target.matcher.hasPredicates || target.ordinal != nil else {
                if let sourceHeistId = target.sourceHeistId {
                    throw BatchStepPlanBuildError(
                        message: "run_batch target \"\(sourceHeistId)\" needs matcher predicates or ordinal fallback; heistId is source metadata only"
                    )
                }
                throw BatchStepPlanBuildError(
                    message: "typed batch target requires matcher predicates or ordinal fallback; heistId is source metadata only"
                )
            }
            return target
        }

        private func targetFromArguments(_ arguments: [String: Any]) -> BatchExecutionTarget? {
            let sourceHeistId = try? arguments.schemaString("heistId")
            let ordinal = try? arguments.schemaInteger("ordinal")
            let parsedMatcher = (try? fence.elementMatcher(arguments)) ?? ElementMatcher()
            let matcher = ElementMatcher(
                label: parsedMatcher.label,
                identifier: parsedMatcher.identifier,
                value: parsedMatcher.value,
                traits: parsedMatcher.traits,
                excludeTraits: parsedMatcher.excludeTraits
            )
            guard sourceHeistId != nil || matcher.hasPredicates || ordinal != nil else { return nil }
            return BatchExecutionTarget(sourceHeistId: sourceHeistId, matcher: matcher, ordinal: ordinal)
        }

        private func targetFromElementTarget(_ target: ElementTarget?) -> BatchExecutionTarget? {
            guard let target else { return nil }
            switch target {
            case .heistId(let heistId):
                return BatchExecutionTarget(sourceHeistId: heistId, matcher: ElementMatcher())
            case .matcher(let matcher, let ordinal):
                return BatchExecutionTarget(matcher: matcher, ordinal: ordinal)
            }
        }
    }

    enum BatchShapeValidator {
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

        func action(target: BatchExecutionTarget) -> TheScore.Action {
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
