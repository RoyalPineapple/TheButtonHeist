import Foundation

import TheScore

private let accessibilityAdjustmentCountRange = 1...100

@ButtonHeistActor
extension TheFence {

    struct BatchStepPlanBuildError: Error {
        let message: String
    }

    struct ClientMessageExecutionPlan {
        let messages: [ClientMessage]
        let timeout: TimeInterval
        let recordsCompletion: Bool
    }

    func clientMessageExecutionPlan(for request: ParsedRequest) throws -> ClientMessageExecutionPlan {
        let timeout = try actionTimeout(for: request)
        let messages = try clientMessages(for: request, mode: .singleCommand)
        return ClientMessageExecutionPlan(
            messages: messages,
            timeout: timeout,
            recordsCompletion: request.command != .getPasteboard
        )
    }

    func batchClientMessage(for request: ParsedRequest) throws -> ClientMessage {
        let messages = try clientMessages(for: request, mode: .batchStep)
        guard let message = messages.first, messages.count == 1 else {
            let commandName = request.command.rawValue
            throw BatchStepPlanBuildError(
                message: "run_batch step command \"\(commandName)\" expands to \(messages.count) actions; express repeats as separate ordered steps"
            )
        }
        return message
    }

    private enum LoweringMode {
        case singleCommand
        case batchStep
    }

    private func clientMessages(
        for request: ParsedRequest,
        mode: LoweringMode
    ) throws -> [ClientMessage] {
        switch request.payload {
        case .gesture(let payload):
            return [gestureCommand(payload)]
        case .scroll(let payload):
            return [scrollCommand(payload)]
        case .accessibility(let payload):
            return try accessibilityCommands(payload, request: request, mode: mode)
        case .rotor(let target):
            return [.rotor(target)]
        case .typeText(let target):
            return [.typeText(target)]
        case .editAction(let target):
            return [.editAction(target)]
        case .setPasteboard(let target):
            return [.setPasteboard(target)]
        case .none where request.command == .dismissKeyboard:
            return [.resignFirstResponder]
        case .none where request.command == .getPasteboard:
            return [.getPasteboard]
        case .waitFor(let target):
            return [.waitFor(target)]
        case .waitForChange(let payload):
            return [.waitForChange(WaitForChangeTarget(
                expect: payload.expectation,
                timeout: payload.timeout
            ))]
        default:
            throw BatchStepPlanBuildError(
                message: "command \"\(request.command.rawValue)\" is not an executable action command"
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

    private func accessibilityCommands(
        _ payload: AccessibilityPayload,
        request: ParsedRequest,
        mode: LoweringMode
    ) throws -> [ClientMessage] {
        switch payload {
        case .activate(let target, let actionName, let count):
            guard let actionName else {
                try rejectCount(count)
                return [.activate(target)]
            }
            return try namedAccessibilityCommands(
                target: target,
                actionName: actionName,
                count: count,
                mode: mode
            )
        case .increment(let target, let count):
            return try repeatedAdjustmentCommands(.increment(target), count: count, mode: mode, command: request.command)
        case .decrement(let target, let count):
            return try repeatedAdjustmentCommands(.decrement(target), count: count, mode: mode, command: request.command)
        case .performCustomAction(let target, let count):
            try rejectCount(count)
            return [.performCustomAction(target)]
        }
    }

    private func namedAccessibilityCommands(
        target: ElementTarget,
        actionName: String,
        count: CountArgument,
        mode: LoweringMode
    ) throws -> [ClientMessage] {
        if actionName.hasPrefix("action:") {
            try rejectCount(count)
            let customName = String(actionName.dropFirst("action:".count))
            guard !customName.isEmpty else {
                throw FenceError.invalidRequest("action: prefix requires a name (e.g. \"action:myAction\")")
            }
            return [.performCustomAction(CustomActionTarget(elementTarget: target, actionName: customName))]
        }

        switch actionName {
        case Command.increment.rawValue:
            return try repeatedAdjustmentCommands(.increment(target), count: count, mode: mode, command: .increment)
        case Command.decrement.rawValue:
            return try repeatedAdjustmentCommands(.decrement(target), count: count, mode: mode, command: .decrement)
        default:
            try rejectCount(count)
            return [.performCustomAction(CustomActionTarget(elementTarget: target, actionName: actionName))]
        }
    }

    private func repeatedAdjustmentCommands(
        _ message: ClientMessage,
        count countArgument: CountArgument,
        mode: LoweringMode,
        command: Command
    ) throws -> [ClientMessage] {
        let count = try accessibilityAdjustmentCount(countArgument)
        guard mode != .batchStep || count == 1 else {
            throw BatchStepPlanBuildError(
                message: "run_batch step command \"\(command.rawValue)\" expands to \(count) actions; express repeats as separate ordered steps"
            )
        }
        return Array(repeating: message, count: count)
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

    private func actionTimeout(for request: ParsedRequest) throws -> TimeInterval {
        switch request.payload {
        case .scroll(.elementSearch), .typeText:
            return Timeouts.longActionSeconds
        case .waitFor(let target):
            return target.resolvedTimeout + 5
        case .waitForChange(let payload):
            let target = WaitForChangeTarget(expect: payload.expectation, timeout: payload.timeout)
            return target.resolvedTimeout + 5
        case .none where request.command == .getPasteboard:
            return Timeouts.healthSeconds
        default:
            return Timeouts.actionSeconds
        }
    }
}
