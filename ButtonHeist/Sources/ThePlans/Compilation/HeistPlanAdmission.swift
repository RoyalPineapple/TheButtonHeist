import Foundation

public enum HeistPlanSource: Sendable, Equatable {
    case artifactPath(String)
    case inlineDSL(String)
}

public struct HeistPlanLoadRequest: Sendable, Equatable {
    public let commandName: String
    public let source: HeistPlanSource

    public init(commandName: String, source: HeistPlanSource) {
        self.commandName = commandName
        self.source = source
    }
}

package enum HeistAdmissionFailure: Error, Sendable, Equatable, CustomStringConvertible {
    case missingPlanSource(commandName: String)
    case multiplePlanSources(commandName: String)
    case emptyPath(commandName: String)
    case unsupportedPath(commandName: String, path: String)
    case emptyInlineSource(commandName: String)
    case invalidArgument(source: String, reason: String)
    case invalidRootArgument(String)

    package var description: String {
        switch self {
        case .missingPlanSource(let commandName):
            return """
            \(commandName) requires exactly one plan source: ButtonHeist DSL source in `plan` \
            or a generated `.heist` package artifact in `path`.
            """
        case .multiplePlanSources(let commandName):
            return """
            \(commandName) accepts exactly one plan source: ButtonHeist DSL source in `plan` \
            or a generated `.heist` package artifact in `path`.
            """
        case .emptyPath(let commandName):
            return "\(commandName) path must not be empty."
        case .unsupportedPath(let commandName, let path):
            return """
            \(commandName) path must be a generated `.heist` package artifact for \(path). \
            Use ButtonHeist DSL source or `.heist`; raw `.json` HeistPlan IR and `plan.json` \
            are internal artifact content, not public run input.
            """
        case .emptyInlineSource(let commandName):
            return "\(commandName) ButtonHeist DSL source must not be empty."
        case .invalidArgument(let source, let reason):
            return "Invalid heist argument at \(source): \(reason)"
        case .invalidRootArgument(let reason):
            return "run_heist argument does not match root heist parameter: \(reason)"
        }
    }
}
