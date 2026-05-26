import Foundation

import TheScore

private let accessibilityAdjustmentCountRange = 1...100

@ButtonHeistActor
extension TheFence {

    // MARK: - Handler: Interface

    func handlePing() async throws -> FenceResponse {
        let payload = try await sendAndAwaitPong(timeout: Timeouts.healthSeconds)
        return .pong(payload)
    }

    func handleGetInterface(_ request: GetInterfaceRequest) async throws -> FenceResponse {
        let interface = try await sendAndAwaitInterface(
            .requestInterface(request.query),
            timeout: Timeouts.exploreSeconds
        )
        return .interface(interface, detail: request.detail)
    }

    // MARK: - Handler: Gestures

    func handleOneFingerTap(_ payload: TouchTapGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchTap(payload.target))
    }

    func handleLongPress(_ payload: LongPressGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchLongPress(payload.target))
    }

    func handleSwipe(_ payload: SwipeGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchSwipe(payload.target))
    }

    func handleDrag(_ payload: DragGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchDrag(payload.target))
    }

    func handlePinch(_ payload: PinchGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchPinch(payload.target))
    }

    func handleRotate(_ payload: RotateGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchRotate(payload.target))
    }

    func handleTwoFingerTap(_ payload: TwoFingerTapGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchTwoFingerTap(payload.target))
    }

    func handleDrawPath(_ payload: DrawPathGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchDrawPath(payload.target))
    }

    func handleDrawBezier(_ payload: DrawBezierGesturePayload) async throws -> FenceResponse {
        try await sendAction(.touchDrawBezier(payload.target))
    }

    // MARK: - Handler: Scroll Actions & Explore

    func handleScrollAction(_ payload: ScrollPayload) async throws -> FenceResponse {
        switch payload {
        case .scroll(let target):
            return try await sendAction(.scroll(target))
        case .scrollToVisible(let target):
            let result = try await sendAndAwaitAction(.scrollToVisible(target), timeout: Timeouts.actionSeconds)
            recordCompletedAction(result)
            return .action(result: result)
        case .elementSearch(let target):
            let result = try await sendAndAwaitAction(.elementSearch(target), timeout: Timeouts.longActionSeconds)
            recordCompletedAction(result)
            return .action(result: result)
        case .scrollToEdge(let target):
            return try await sendAction(.scrollToEdge(target))
        }
    }

    // MARK: - Handler: Accessibility Actions

    func handleAccessibilityAction(_ payload: AccessibilityPayload) async throws -> FenceResponse {
        switch payload {
        case .activate(let target, let actionName, let count):
            guard let actionName else {
                try rejectCount(count)
                return try await sendAction(.activate(target))
            }
            return try await handleNamedAccessibilityAction(
                target: target,
                actionName: actionName,
                count: count
            )
        case .increment(let target, let count):
            let count = try accessibilityAdjustmentCount(count)
            return try await sendRepeatedAdjustment(.increment(target), count: count)
        case .decrement(let target, let count):
            let count = try accessibilityAdjustmentCount(count)
            return try await sendRepeatedAdjustment(.decrement(target), count: count)
        case .performCustomAction(let target, let count):
            return try await handleNamedAccessibilityAction(
                target: target,
                count: count
            )
        }
    }

    private func handleNamedAccessibilityAction(
        target: CustomActionTarget,
        count: CountArgument
    ) async throws -> FenceResponse {
        if let elementTarget = target.elementTarget {
            return try await handleNamedAccessibilityAction(
                target: elementTarget,
                actionName: target.actionName,
                count: count
            )
        }
        try rejectCount(count)
        return try await sendAction(.performCustomAction(target))
    }

    private func handleNamedAccessibilityAction(
        target: ElementTarget,
        actionName: String,
        count: CountArgument
    ) async throws -> FenceResponse {
        // "action:foo" prefix forces custom action dispatch and escapes built-in names.
        if actionName.hasPrefix("action:") {
            try rejectCount(count)
            let customName = String(actionName.dropFirst("action:".count))
            guard !customName.isEmpty else {
                throw FenceError.invalidRequest("action: prefix requires a name (e.g. \"action:myAction\")")
            }
            return try await sendAction(.performCustomAction(
                CustomActionTarget(elementTarget: target, actionName: customName)))
        }

        switch actionName {
        case Command.increment.rawValue:
            let count = try accessibilityAdjustmentCount(count)
            return try await sendRepeatedAdjustment(.increment(target), count: count)
        case Command.decrement.rawValue:
            let count = try accessibilityAdjustmentCount(count)
            return try await sendRepeatedAdjustment(.decrement(target), count: count)
        default:
            try rejectCount(count)
            return try await sendAction(.performCustomAction(
                CustomActionTarget(elementTarget: target, actionName: actionName)))
        }
    }

    private func accessibilityAdjustmentCount(_ countArgument: CountArgument) throws -> Int {
        let count = countArgument.value ?? 1
        guard accessibilityAdjustmentCountRange.contains(count) else {
            throw SchemaValidationError(
                field: "count",
                observed: count,
                expected: "integer in \(accessibilityAdjustmentCountRange.lowerBound)...\(accessibilityAdjustmentCountRange.upperBound)"
            )
        }
        return count
    }

    private func rejectCount(_ countArgument: CountArgument) throws {
        guard countArgument.observed != nil else { return }
        throw SchemaValidationError(
            field: "count",
            observed: countArgument.observed,
            expected: "only valid with increment or decrement"
        )
    }

    private func sendRepeatedAdjustment(
        _ message: ClientMessage,
        count: Int
    ) async throws -> FenceResponse {
        let firstResult = try await sendAndAwaitAction(message, timeout: Timeouts.actionSeconds)
        recordCompletedAction(firstResult)
        if !firstResult.success || count == 1 {
            return .action(result: firstResult)
        }

        var finalResult = firstResult
        for _ in 2...count {
            let result = try await sendAndAwaitAction(message, timeout: Timeouts.actionSeconds)
            recordCompletedAction(result)
            finalResult = result
            if !result.success {
                return .action(result: result)
            }
        }
        return .action(result: finalResult)
    }

    func handleRotor(_ target: RotorTarget) async throws -> FenceResponse {
        return try await sendAction(.rotor(target))
    }

    // MARK: - Handler: Text Input

    func handleTypeText(_ target: TypeTextTarget) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(.typeText(target), timeout: Timeouts.longActionSeconds)
        recordCompletedAction(result)
        return .action(result: result)
    }

    func handleEditAction(_ target: EditActionTarget) async throws -> FenceResponse {
        return try await sendAction(.editAction(target))
    }

    // MARK: - Handler: Pasteboard

    func handleSetPasteboard(_ target: SetPasteboardTarget) async throws -> FenceResponse {
        return try await sendAction(.setPasteboard(target))
    }

    func handleGetPasteboard() async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(.getPasteboard, timeout: Timeouts.healthSeconds)
        return .action(result: result)
    }

    // MARK: - Handler: Wait For

    func handleWaitFor(_ target: WaitForTarget) async throws -> FenceResponse {
        let result = try await sendAndAwaitAction(.waitFor(target), timeout: target.resolvedTimeout + 5)
        recordCompletedAction(result)
        return .action(result: result)
    }

    func missingElementTargetResponse(command: String) -> FenceResponse {
        let contract = "requires heistId, ordinal, or at least one matcher field (label, identifier, value, traits, or excludeTraits)"
        let next = "get_interface()"
        let message = "\(command) request contract failed: missing target; \(contract). " +
            "Next: \(next) to inspect the current app accessibility state, then retry \(command) with a heistId, exact matcher, or ordinal selector."
        return .error(
            message,
            details: FailureDetails(
                errorCode: FenceRequestErrorCode.missingTarget,
                phase: .request,
                retryable: false,
                hint: next
            )
        )
    }

    // MARK: - Handler: Wait For Change

    func handleWaitForChange(_ payload: ExpectationPayload) async throws -> FenceResponse {
        let target = WaitForChangeTarget(expect: payload.expectation, timeout: payload.timeout)
        let result = try await sendAndAwaitAction(.waitForChange(target), timeout: target.resolvedTimeout + 5)
        recordCompletedAction(result)
        return .action(result: result)
    }
}
