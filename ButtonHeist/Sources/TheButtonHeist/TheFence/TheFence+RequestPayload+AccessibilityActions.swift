import TheScore
import ThePlans

extension TheFence {

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
