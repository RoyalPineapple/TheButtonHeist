import TheScore

private let accessibilityAdjustmentCountRange = 1...100

extension TheFence {

    func decodeAccessibilityActionDispatch(
        command: Command,
        input: some CommandArgumentReadable
    ) throws -> DecodedRequestDispatch {
        guard command == .activate else {
            throw FenceError.invalidRequest("Unexpected accessibility action command: \(command.rawValue)")
        }
        let target = try input.requiredElementTarget(command: .activate)
        let actionName = try input.optionalNonEmptyString("action")
        let count = try input.countArgument()
        return Self.clientActionDispatch(
            try Self.accessibilityClientMessages(
                target: target,
                actionName: actionName,
                count: count
            )
        )
    }

    static func accessibilityClientMessages(
        target: ElementTarget,
        actionName: String?,
        count: TheFence.CountArgument
    ) throws -> [ClientMessage] {
        guard let actionName else {
            try rejectCount(count)
            return [.activate(target)]
        }
        switch actionName {
        case ElementAction.increment.description:
            return try repeatedAdjustmentCommands(.increment(target), count: count)
        case ElementAction.decrement.description:
            return try repeatedAdjustmentCommands(.decrement(target), count: count)
        default:
            try rejectCount(count)
            return [.performCustomAction(CustomActionTarget(elementTarget: target, actionName: actionName))]
        }
    }

    static func repeatedAdjustmentCommands(
        _ message: ClientMessage,
        count countArgument: TheFence.CountArgument
    ) throws -> [ClientMessage] {
        let count = try accessibilityAdjustmentCount(countArgument)
        return Array(repeating: message, count: count)
    }

    static func accessibilityAdjustmentCount(_ countArgument: TheFence.CountArgument) throws -> Int {
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

    static func rejectCount(_ countArgument: TheFence.CountArgument) throws {
        guard countArgument.observed != nil else { return }
        throw SchemaValidationError(
            field: "count",
            observed: countArgument.observed ?? "missing",
            expected: "only valid with increment or decrement"
        )
    }
}
