import ArgumentParser
import ButtonHeist

/// Shared options for commands that target a UI element by heistId or accessibility properties.
struct ElementTargetOptions: ParsableArguments {
    @Option(name: .long, help: "Element heistId (from get_interface)")
    var heistId: String?

    @Option(name: .long, help: "Accessibility identifier")
    var identifier: String?

    @Option(name: .long, help: "Accessibility label")
    var label: String?

    var actionTarget: ActionTarget? {
        let hasMatcher = identifier != nil || label != nil
        let match: ElementMatcher? = hasMatcher ? ElementMatcher(
            label: label,
            identifier: identifier
        ) : nil
        guard heistId != nil || match != nil else { return nil }
        return ActionTarget(heistId: heistId, match: match)
    }

    func requireTarget() throws -> ActionTarget {
        guard let target = actionTarget else {
            throw ValidationError("Must specify --heist-id, --identifier, or --label")
        }
        return target
    }
}
