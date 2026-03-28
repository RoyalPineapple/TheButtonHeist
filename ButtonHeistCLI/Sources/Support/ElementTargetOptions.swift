import ArgumentParser
import ButtonHeist

/// Shared options for commands that target a UI element by identifier, heistId, or index.
struct ElementTargetOptions: ParsableArguments {
    @Option(name: .long, help: "Element identifier")
    var identifier: String?

    @Option(name: .long, help: "Target element by heistId")
    var heistId: String?

    @Option(name: .long, help: "Element index")
    var index: Int?

    var actionTarget: ActionTarget? {
        guard identifier != nil || heistId != nil || index != nil else { return nil }
        return ActionTarget(identifier: identifier, heistId: heistId, order: index)
    }

    func requireTarget() throws -> ActionTarget {
        guard let target = actionTarget else {
            throw ValidationError("Must specify --identifier, --heist-id, or --index")
        }
        return target
    }
}
