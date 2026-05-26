import TheScore

extension TheFence {

    @ButtonHeistActor
    struct BatchActionConstructor {

        func construct(context: BatchStepPlanningContext) throws -> BatchStepActionPlan {
            try BatchShapeValidator.rejectUnsupportedShapes(request: context.request)
            return try BatchStepActionPlan(command: command(from: context.request, context: context))
        }

        private func command(
            from request: ParsedRequest,
            context: BatchStepPlanningContext
        ) throws -> ClientMessage {
            switch request.payload {
            case .gesture(let payload):
                return gestureCommand(payload)
            case .scroll(let payload):
                return scrollCommand(payload)
            case .accessibility(let payload):
                return try accessibilityCommand(payload, request: request)
            case .rotor(let target):
                return .rotor(target)
            case .typeText(let target):
                return .typeText(target)
            case .editAction(let target):
                return .editAction(target)
            case .setPasteboard(let target):
                return .setPasteboard(target)
            case .none where request.command == .dismissKeyboard:
                return .resignFirstResponder
            case .waitFor(let target):
                return .waitFor(target)
            case .waitForChange:
                return .waitForChange(WaitForChangeTarget(
                    expect: context.expectation,
                    timeout: context.timeout
                ))
            default:
                throw BatchStepPlanBuildError(
                    message: "run_batch step command \"\(request.command.rawValue)\" is not a non-read batch command"
                )
            }
        }

        private func gestureCommand(_ payload: GesturePayload) -> ClientMessage {
            switch payload {
            case .oneFingerTap(let payload):
                return .touchTap(payload.target)
            case .longPress(let payload):
                return .touchLongPress(payload.target)
            case .swipe(let payload):
                return .touchSwipe(payload.target)
            case .drag(let payload):
                return .touchDrag(payload.target)
            case .pinch(let payload):
                return .touchPinch(payload.target)
            case .rotate(let payload):
                return .touchRotate(payload.target)
            case .twoFingerTap(let payload):
                return .touchTwoFingerTap(payload.target)
            case .drawPath(let payload):
                return .touchDrawPath(payload.target)
            case .drawBezier(let payload):
                return .touchDrawBezier(payload.target)
            }
        }

        private func scrollCommand(_ payload: ScrollPayload) -> ClientMessage {
            switch payload {
            case .scroll(let target):
                return .scroll(target)
            case .scrollToVisible(let target):
                return .scrollToVisible(target)
            case .elementSearch(let target):
                return .elementSearch(target)
            case .scrollToEdge(let target):
                return .scrollToEdge(target)
            }
        }

        private func accessibilityCommand(
            _ payload: AccessibilityPayload,
            request: ParsedRequest
        ) throws -> ClientMessage {
            switch payload {
            case .activate(let target, let actionName, let count):
                return try BatchAccessibilityActionShape(
                    actionName: actionName,
                    count: count,
                    command: request.command
                ).command(target: target)
            case .increment(let target, _):
                return .increment(target)
            case .decrement(let target, _):
                return .decrement(target)
            case .performCustomAction(let target, _):
                return .performCustomAction(target)
            }
        }
    }
}
