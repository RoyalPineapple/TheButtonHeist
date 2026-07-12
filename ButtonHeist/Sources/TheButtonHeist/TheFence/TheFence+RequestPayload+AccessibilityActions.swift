import TheScore
import ThePlans

extension TheFence {

    static func decodeActivateRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let target = try input.requiredElementTarget(command: .activate)
        let actionName = try input.optionalNonEmptyValue(FenceParameters.actionName)
        return try appInteractionDispatch(
            Command.activate,
            Self.accessibilityActionCommand(target: target, actionName: actionName),
            expectationPayload: expectationPayload
        )
    }

    static func accessibilityActionCommand(
        target: ElementTarget,
        actionName: String?
    ) -> HeistActionCommand {
        guard let actionName else {
            return .activate(.target(target))
        }
        switch actionName {
        case ElementAction.increment.description:
            return .increment(.target(target))
        case ElementAction.decrement.description:
            return .decrement(.target(target))
        default:
            return .customAction(name: actionName, target: .target(target))
        }
    }
}
