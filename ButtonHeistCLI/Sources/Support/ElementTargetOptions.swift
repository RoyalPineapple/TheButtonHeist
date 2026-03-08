import ArgumentParser
import ButtonHeist

/// Shared options for commands that target a UI element by identifier or index.
struct ElementTargetOptions: ParsableArguments {
    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    var actionTarget: ActionTarget? {
        guard identifier != nil || index != nil else { return nil }
        return ActionTarget(identifier: identifier, order: index)
    }

    func requireTarget() throws -> ActionTarget {
        guard let target = actionTarget else {
            throw ValidationError("Must specify --identifier or --index")
        }
        return target
    }
}
