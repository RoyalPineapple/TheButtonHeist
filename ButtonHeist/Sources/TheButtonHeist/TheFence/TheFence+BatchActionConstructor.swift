import Foundation

import TheScore

extension TheFence {

    @ButtonHeistActor
    struct BatchActionConstructor {
        private let targetResolver: BatchTargetResolver

        init(targetResolver: BatchTargetResolver) {
            self.targetResolver = targetResolver
        }

        func construct(context: BatchStepPlanningContext) throws -> BatchStepActionPlan {
            switch context.request.payload {
            case .gesture(let payload):
                return try gestureAction(payload, context: context)
            case .scroll(let payload):
                return try scrollAction(payload, context: context)
            case .accessibility(let payload):
                return try accessibilityAction(payload, context: context)
            case .rotor(let target):
                return try BatchStepActionPlan(action: .rotor(BatchRotorTarget(
                    target: targetResolver.requiredTarget(from: context.operation, fallback: target.elementTarget),
                    rotor: target.rotor,
                    rotorIndex: target.rotorIndex,
                    direction: target.direction,
                    currentSourceHeistId: target.currentHeistId,
                    currentTextRange: target.currentTextRange
                )))
            case .typeText(let target):
                return try BatchStepActionPlan(action: .typeText(BatchTypeTextTarget(
                    text: target.text,
                    target: targetResolver.optionalTarget(from: context.operation, fallback: target.elementTarget)
                )))
            case .editAction(let target):
                return BatchStepActionPlan(action: .editAction(target))
            case .setPasteboard(let target):
                return BatchStepActionPlan(action: .setPasteboard(target))
            case .none where context.request.command == .dismissKeyboard:
                return BatchStepActionPlan(action: .resignFirstResponder)
            case .waitFor(let target):
                return try waitForAction(target, context: context)
            case .waitForChange:
                let expectation = context.expectation ?? .screenChanged
                return BatchStepActionPlan(
                    action: .waitForChange(WaitForChangeTarget(expect: expectation, timeout: context.timeout)),
                    expectation: expectation,
                    timeout: context.timeout
                )
            default:
                throw BatchStepPlanBuildError(
                    message: "run_batch step command \"\(context.request.command.rawValue)\" is not a non-read batch Action"
                )
            }
        }

        private func gestureAction(
            _ payload: GesturePayload,
            context: BatchStepPlanningContext
        ) throws -> BatchStepActionPlan {
            switch payload {
            case .oneFingerTap(let payload):
                return try BatchStepActionPlan(action: .touchTap(BatchTouchTapTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    pointX: payload.pointX,
                    pointY: payload.pointY
                )))
            case .longPress(let payload):
                return try BatchStepActionPlan(action: .touchLongPress(BatchLongPressTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    pointX: payload.pointX,
                    pointY: payload.pointY,
                    duration: payload.duration
                )))
            case .swipe(let payload):
                return try BatchStepActionPlan(action: .touchSwipe(BatchSwipeTarget(
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
                return try BatchStepActionPlan(action: .touchDrag(BatchDragTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    startX: payload.startX,
                    startY: payload.startY,
                    endX: payload.endX,
                    endY: payload.endY,
                    duration: payload.duration
                )))
            case .pinch(let payload):
                return try BatchStepActionPlan(action: .touchPinch(BatchPinchTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    centerX: payload.centerX,
                    centerY: payload.centerY,
                    scale: payload.scale,
                    spread: payload.spread,
                    duration: payload.duration
                )))
            case .rotate(let payload):
                return try BatchStepActionPlan(action: .touchRotate(BatchRotateTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    centerX: payload.centerX,
                    centerY: payload.centerY,
                    angle: payload.angle,
                    radius: payload.radius,
                    duration: payload.duration
                )))
            case .twoFingerTap(let payload):
                return try BatchStepActionPlan(action: .touchTwoFingerTap(BatchTwoFingerTapTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: payload.elementTarget),
                    centerX: payload.centerX,
                    centerY: payload.centerY,
                    spread: payload.spread
                )))
            case .drawPath(let payload):
                return BatchStepActionPlan(action: .touchDrawPath(payload.target))
            case .drawBezier(let payload):
                return BatchStepActionPlan(action: .touchDrawBezier(payload.target))
            }
        }

        private func scrollAction(
            _ payload: ScrollPayload,
            context: BatchStepPlanningContext
        ) throws -> BatchStepActionPlan {
            switch payload {
            case .scroll(let target):
                try BatchShapeValidator.rejectContainerTargetedScroll(
                    target.containerTarget,
                    command: context.request.command
                )
                return try BatchStepActionPlan(action: .scroll(BatchScrollTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: target.elementTarget),
                    direction: target.direction
                )))
            case .scrollToVisible(let target):
                return try BatchStepActionPlan(action: .scrollToVisible(BatchScrollToVisibleTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: target.elementTarget)
                )))
            case .elementSearch(let target):
                return try BatchStepActionPlan(action: .elementSearch(BatchElementSearchTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: target.elementTarget),
                    direction: target.direction
                )))
            case .scrollToEdge(let target):
                try BatchShapeValidator.rejectContainerTargetedScroll(
                    target.containerTarget,
                    command: context.request.command
                )
                return try BatchStepActionPlan(action: .scrollToEdge(BatchScrollToEdgeTarget(
                    target: targetResolver.optionalTarget(from: context.operation, fallback: target.elementTarget),
                    edge: target.edge
                )))
            }
        }

        private func accessibilityAction(
            _ payload: AccessibilityPayload,
            context: BatchStepPlanningContext
        ) throws -> BatchStepActionPlan {
            switch payload {
            case .activate(let target, let actionName, let count):
                return try BatchStepActionPlan(action: BatchAccessibilityActionShape(
                    actionName: actionName,
                    count: count,
                    command: context.request.command
                ).action(target: targetResolver.requiredTarget(from: context.operation, fallback: target)))
            case .increment(let target, let count):
                try BatchShapeValidator.rejectRepeatedCount(count, command: context.request.command)
                return try BatchStepActionPlan(action: .increment(targetResolver.requiredTarget(
                    from: context.operation,
                    fallback: target
                )))
            case .decrement(let target, let count):
                try BatchShapeValidator.rejectRepeatedCount(count, command: context.request.command)
                return try BatchStepActionPlan(action: .decrement(targetResolver.requiredTarget(
                    from: context.operation,
                    fallback: target
                )))
            case .performCustomAction(let target, let count):
                try BatchShapeValidator.rejectObservedCount(count, command: context.request.command)
                return try BatchStepActionPlan(action: customAction(target, context: context))
            }
        }

        private func customAction(
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

        private func waitForAction(
            _ target: WaitForTarget,
            context: BatchStepPlanningContext
        ) throws -> BatchStepActionPlan {
            let semanticTarget = targetResolver.executionTarget(from: context.operation, fallback: target.elementTarget)
            let resolvedTimeout = target.timeout ?? context.timeout
            let waitAction = TheScore.Action.waitForElement(BatchWaitForTarget(
                target: try targetResolver.requiredExecutionTarget(semanticTarget),
                absent: target.absent,
                timeout: resolvedTimeout
            ))
            return try BatchStepActionPlan(
                action: waitAction,
                expectation: targetResolver.waitExpectation(target: semanticTarget, absent: target.absent),
                timeout: resolvedTimeout
            )
        }
    }
}
