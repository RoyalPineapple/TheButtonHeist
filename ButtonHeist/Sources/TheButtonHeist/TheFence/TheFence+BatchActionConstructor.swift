import TheScore

extension TheFence {

    @ButtonHeistActor
    struct BatchActionConstructor {
        private let targetResolver: BatchTargetResolver

        init(targetResolver: BatchTargetResolver) { self.targetResolver = targetResolver }

        func construct(context: BatchStepPlanningContext) throws -> BatchStepActionPlan {
            try BatchShapeValidator.rejectUnsupportedShapes(request: context.request)
            switch context.request.payload {
            case .gesture(let payload):
                return try BatchStepActionPlan(action: gestureAction(payload, request: context.request))
            case .scroll(let payload):
                return try BatchStepActionPlan(action: scrollAction(payload, request: context.request))
            case .accessibility(let payload):
                return try BatchStepActionPlan(action: accessibilityAction(payload, request: context.request))
            case .rotor(let target):
                return try BatchStepActionPlan(action: .rotor(BatchRotorTarget(
                    target: required(context.request, target.elementTarget),
                    rotor: target.rotor,
                    rotorIndex: target.rotorIndex,
                    direction: target.direction,
                    currentSourceHeistId: target.currentHeistId,
                    currentTextRange: target.currentTextRange
                )))
            case .typeText(let target):
                return try BatchStepActionPlan(action: .typeText(BatchTypeTextTarget(
                    text: target.text,
                    target: self.target(context.request, target.elementTarget)
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
                return BatchStepActionPlan(
                    action: .waitForChange(WaitForChangeTarget(expect: context.expectation, timeout: context.timeout))
                )
            default:
                throw BatchStepPlanBuildError(message: "run_batch step command \"\(context.request.command.rawValue)\" is not a non-read batch Action")
            }
        }

        private func gestureAction(_ payload: GesturePayload, request: ParsedRequest) throws -> TheScore.Action {
            switch payload {
            case .oneFingerTap(let payload):
                return try .touchTap(.init(target: target(request, payload.elementTarget), pointX: payload.pointX, pointY: payload.pointY))
            case .longPress(let payload):
                let resolved = try target(request, payload.elementTarget)
                return .touchLongPress(.init(target: resolved, pointX: payload.pointX, pointY: payload.pointY, duration: payload.duration))
            case .swipe(let payload):
                let resolved = try target(request, payload.elementTarget)
                return .touchSwipe(.init(
                    target: resolved, startX: payload.startX, startY: payload.startY, endX: payload.endX, endY: payload.endY,
                    direction: payload.direction, duration: payload.duration, start: payload.start, end: payload.end
                ))
            case .drag(let payload):
                let resolved = try target(request, payload.elementTarget)
                return .touchDrag(.init(
                    target: resolved, startX: payload.startX, startY: payload.startY,
                    endX: payload.endX, endY: payload.endY, duration: payload.duration
                ))
            case .pinch(let payload):
                let resolved = try target(request, payload.elementTarget)
                return .touchPinch(.init(
                    target: resolved, centerX: payload.centerX, centerY: payload.centerY,
                    scale: payload.scale, spread: payload.spread, duration: payload.duration
                ))
            case .rotate(let payload):
                let resolved = try target(request, payload.elementTarget)
                return .touchRotate(.init(
                    target: resolved, centerX: payload.centerX, centerY: payload.centerY,
                    angle: payload.angle, radius: payload.radius, duration: payload.duration
                ))
            case .twoFingerTap(let payload):
                let resolved = try target(request, payload.elementTarget)
                return .touchTwoFingerTap(.init(target: resolved, centerX: payload.centerX, centerY: payload.centerY, spread: payload.spread))
            case .drawPath(let payload):
                return .touchDrawPath(payload.target)
            case .drawBezier(let payload):
                return .touchDrawBezier(payload.target)
            }
        }

        private func scrollAction(_ payload: ScrollPayload, request: ParsedRequest) throws -> TheScore.Action {
            switch payload {
            case .scroll(let target):
                return try .scroll(.init(target: self.target(request, target.elementTarget), direction: target.direction))
            case .scrollToVisible(let target):
                return try .scrollToVisible(.init(target: self.target(request, target.elementTarget)))
            case .elementSearch(let target):
                return try .elementSearch(.init(target: self.target(request, target.elementTarget), direction: target.direction))
            case .scrollToEdge(let target):
                return try .scrollToEdge(.init(target: self.target(request, target.elementTarget), edge: target.edge))
            }
        }

        private func accessibilityAction(_ payload: AccessibilityPayload, request: ParsedRequest) throws -> TheScore.Action {
            switch payload {
            case .activate(let target, let actionName, let count):
                return try BatchAccessibilityActionShape(
                    actionName: actionName,
                    count: count,
                    command: request.command
                ).action(target: required(request, target))
            case .increment(let target, _):
                return try .increment(required(request, target))
            case .decrement(let target, _):
                return try .decrement(required(request, target))
            case .performCustomAction(let target, _):
                return try .performCustomAction(customActionTarget(target, request: request))
            }
        }

        private func customActionTarget(_ target: CustomActionTarget, request: ParsedRequest) throws -> BatchCustomActionTarget {
            if let elementTarget = target.elementTarget {
                return try BatchCustomActionTarget(target: required(request, elementTarget), actionName: target.actionName)
            }
            guard let containerTarget = target.containerTarget else {
                throw MissingElementTarget(command: request.command.rawValue)
            }
            return BatchCustomActionTarget(containerTarget: containerTarget, ordinal: target.containerOrdinal, actionName: target.actionName)
        }

        private func waitForAction(_ target: WaitForTarget, context: BatchStepPlanningContext) throws -> BatchStepActionPlan {
            let semanticTarget = targetResolver.executionTarget(from: context.request, commandTarget: target.elementTarget)
            return try BatchStepActionPlan(action: .waitForElement(.init(
                target: targetResolver.requiredExecutionTarget(semanticTarget),
                absent: target.absent,
                timeout: target.timeout ?? context.timeout
            )))
        }

        private func target(_ request: ParsedRequest, _ target: ElementTarget?) throws -> BatchExecutionTarget? {
            try targetResolver.optionalTarget(from: request, commandTarget: target)
        }

        private func required(_ request: ParsedRequest, _ target: ElementTarget?) throws -> BatchExecutionTarget {
            try targetResolver.requiredTarget(from: request, commandTarget: target)
        }
    }
}
