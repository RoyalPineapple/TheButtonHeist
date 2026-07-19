import Foundation

public enum HeistPlanSource: Sendable, Equatable {
    case artifactPath(String)
    case inlineDSL(String)
}

public enum HeistPlanRejectedPublicSourceField: String, CaseIterable, Sendable, Hashable {
    case version
    case name
    case parameter
    case definitions
    case body

    public static func sourceFields<S: Sequence>(in fieldNames: S) -> Set<Self> where S.Element == String {
        Set(fieldNames.compactMap(Self.init(rawValue:)))
    }
}

public struct HeistPlanLoadRequest: Sendable, Equatable {
    public let commandName: String
    public let source: HeistPlanSource

    public init(commandName: String, source: HeistPlanSource) {
        self.commandName = commandName
        self.source = source
    }
}

public enum HeistPlanSourceAdmissionPolicy: Sendable, Equatable {
    case artifactOrInlineDSL
    case artifactOnly

    var acceptsInlineDSL: Bool {
        switch self {
        case .artifactOrInlineDSL:
            return true
        case .artifactOnly:
            return false
        }
    }
}

public struct HeistPlanSourceAdmissionRequest: Sendable, Equatable {
    public let commandName: String
    public let source: HeistPlanSource
    public let sourcePolicy: HeistPlanSourceAdmissionPolicy

    public init(
        commandName: String,
        source: HeistPlanSource,
        sourcePolicy: HeistPlanSourceAdmissionPolicy = .artifactOrInlineDSL
    ) {
        self.commandName = commandName
        self.source = source
        self.sourcePolicy = sourcePolicy
    }
}

package enum HeistAdmissionFailure: Error, Sendable, Equatable, CustomStringConvertible {
    case missingPlanSource(commandName: String)
    case multiplePlanSources(commandName: String)
    case inlineSourceNotAccepted(commandName: String)
    case emptyPath(commandName: String)
    case unsupportedPath(commandName: String, path: String)
    case emptyInlineSource(commandName: String)
    case rawStructuredJSONIRFields(commandName: String, fields: [HeistPlanRejectedPublicSourceField])
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
        case .inlineSourceNotAccepted(let commandName):
            return "\(commandName) does not accept inline ButtonHeist DSL source; use a generated `.heist` artifact."
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
        case .rawStructuredJSONIRFields(let commandName, let fields):
            let fieldNames = fields.map(\.rawValue).joined(separator: ", ")
            return """
            \(commandName) received raw JSON HeistPlan IR field(s): \(fieldNames). \
            Raw JSON IR and `plan.json` are internal generated artifact content. Use ButtonHeist DSL \
            source in `plan` or a generated `.heist` package artifact in `path`.
            """
        case .invalidArgument(let source, let reason):
            return "Invalid heist argument at \(source): \(reason)"
        case .invalidRootArgument(let reason):
            return "run_heist argument does not match root heist parameter: \(reason)"
        }
    }
}
