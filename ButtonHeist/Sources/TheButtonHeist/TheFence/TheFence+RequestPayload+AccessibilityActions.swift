import TheScore
import ThePlans

extension TheFence {

    static func decodeActivateRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let target = try input.requiredAccessibilityTarget(command: .activate)
        let actionName = try input.optionalNonEmptyValue(FenceParameters.actionName)
        return try appInteractionDispatch(
            Command.activate,
            Self.accessibilityActionCommand(target: target, actionName: actionName),
            expectationPayload: expectationPayload
        )
    }

    static func accessibilityActionCommand(
        target: AccessibilityTarget,
        actionName: String?
    ) -> HeistActionCommand {
        guard let actionName else {
            return .activate(target)
        }
        switch actionName {
        case ElementAction.increment.description:
            return .increment(target)
        case ElementAction.decrement.description:
            return .decrement(target)
        default:
            return .customAction(name: actionName, target: target)
        }
    }
}
