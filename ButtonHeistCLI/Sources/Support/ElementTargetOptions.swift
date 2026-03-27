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

    @Option(name: .long, help: "Accessibility value")
    var value: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Required traits (all must match)")
    var traits: [String] = []

    @Option(name: .customLong("exclude-traits"), parsing: .upToNextOption, help: "Excluded traits (none may be present)")
    var excludeTraits: [String] = []

    var elementMatcher: ElementMatcher? {
        let hasFields = identifier != nil || label != nil || value != nil
            || !traits.isEmpty || !excludeTraits.isEmpty
        guard hasFields else { return nil }
        return ElementMatcher(
            label: label,
            identifier: identifier,
            value: value,
            traits: traits.isEmpty ? nil : traits,
            excludeTraits: excludeTraits.isEmpty ? nil : excludeTraits
        )
    }

    var actionTarget: ActionTarget? {
        let match = elementMatcher
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
