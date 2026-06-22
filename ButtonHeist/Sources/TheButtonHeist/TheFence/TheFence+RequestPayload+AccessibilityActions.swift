@_spi(ButtonHeistInternals) import TheScore
import ThePlans

extension TheFence {

    static func decodeActivateRequest(
        _ fence: TheFence,
        _ input: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let target = try input.requiredElementTarget(command: .activate)
        let actionName = try input.optionalNonEmptyString("action")
        return appInteractionDispatch(
            SemanticActionCommand.activate,
            Self.accessibilityRuntimeActions(target: target, actionName: actionName)
        )
    }

    static func accessibilityRuntimeActions(
        target: ElementTarget,
        actionName: String?
    ) -> [RuntimeActionMessage] {
        guard let actionName else {
            return [.activate(target)]
        }
        switch actionName {
        case ElementAction.increment.description:
            return [.increment(target)]
        case ElementAction.decrement.description:
            return [.decrement(target)]
        default:
            return [.performCustomAction(CustomActionTarget(elementTarget: target, actionName: actionName))]
        }
    }
}
