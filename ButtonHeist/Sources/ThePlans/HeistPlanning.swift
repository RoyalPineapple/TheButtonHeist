import Foundation

public enum HeistPlanning {
    public static let rawStructuredJSONIRFieldNames: Set<String> = [
        "version",
        "name",
        "parameter",
        "definitions",
        "body",
    ]

    public static func readPlan(from url: URL) throws -> HeistPlan {
        try loadValidatedPlan(from: HeistPlanSourceRequest(
            commandName: "heist-plan",
            path: url.path
        ))
    }

    public static func loadValidatedPlan(from request: HeistPlanSourceRequest) throws -> HeistPlan {
        guard request.rawStructuredJSONIRFields.isEmpty else {
            throw HeistPlanningError.rawStructuredJSONIRFields(
                commandName: request.commandName,
                fields: request.rawStructuredJSONIRFields.sorted()
            )
        }

        let hasPath = request.path != nil
        let hasInlineSource = request.inlineButtonHeistSource != nil
        let sourceCount = [hasPath, hasInlineSource].filter { $0 }.count
        guard sourceCount == 1 else {
            if sourceCount == 0 {
                throw HeistPlanningError.missingPlanSource(commandName: request.commandName)
            }
            throw HeistPlanningError.multiplePlanSources(commandName: request.commandName)
        }

        if let path = request.path {
            return try loadValidatedArtifactPlan(path: path, commandName: request.commandName)
        }

        guard request.acceptsInlineButtonHeistSource else {
            throw HeistPlanningError.inlineSourceNotAccepted(commandName: request.commandName)
        }
        guard let source = request.inlineButtonHeistSource else {
            throw HeistPlanningError.missingPlanSource(commandName: request.commandName)
        }
        return try compileInlineButtonHeistSource(source, commandName: request.commandName)
    }

    public static func decodeArgumentJSON(
        _ data: Data,
        sourceURL: URL = URL(fileURLWithPath: "inline-heist-argument.json")
    ) throws -> HeistArgument {
        do {
            return try JSONDecoder().decode(HeistArgument.self, from: data)
        } catch {
            throw HeistPlanningError.invalidArgument(
                source: sourceURL.path,
                reason: String(describing: error)
            )
        }
    }

    public static func validateRootArgument(
        _ argument: HeistArgument,
        for plan: HeistPlan
    ) throws {
        do {
            _ = try HeistExecutionEnvironment.empty.binding(argument: argument, to: plan.parameter)
        } catch {
            throw HeistPlanningError.invalidRootArgument(String(describing: error))
        }
    }

    private static func loadValidatedArtifactPlan(path: String, commandName: String) throws -> HeistPlan {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HeistPlanningError.emptyPath(commandName: commandName)
        }

        let url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        guard url.pathExtension.lowercased() == "heist" else {
            throw HeistPlanningError.unsupportedPath(commandName: commandName, path: path)
        }

        do {
            return try HeistArtifactCodec.read(from: url).plan
        } catch let error as HeistArtifactCodecError {
            throw HeistPlanningError.invalidPlanSource(error.description)
        }
    }

    private static func compileInlineButtonHeistSource(_ source: String, commandName: String) throws -> HeistPlan {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HeistPlanningError.emptyInlineSource(commandName: commandName)
        }

        do {
            return try compileHeistPlanSource(
                source,
                sourceName: "\(commandName)-inline.plan"
            )
        } catch let error as HeistPlanSourceCompilerError {
            throw HeistPlanningError.invalidPlanSource(error.description)
        } catch {
            throw HeistPlanningError.invalidPlanSource(String(describing: error))
        }
    }
}

public struct HeistPlanSourceRequest: Sendable, Equatable {
    public let commandName: String
    public let path: String?
    public let inlineButtonHeistSource: String?
    public let rawStructuredJSONIRFields: Set<String>
    public let acceptsInlineButtonHeistSource: Bool

    public init(
        commandName: String,
        path: String? = nil,
        inlineButtonHeistSource: String? = nil,
        rawStructuredJSONIRFields: Set<String> = [],
        acceptsInlineButtonHeistSource: Bool = true
    ) {
        self.commandName = commandName
        self.path = path
        self.inlineButtonHeistSource = inlineButtonHeistSource
        self.rawStructuredJSONIRFields = rawStructuredJSONIRFields
        self.acceptsInlineButtonHeistSource = acceptsInlineButtonHeistSource
    }
}

public enum HeistPlanningError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingPlanSource(commandName: String)
    case multiplePlanSources(commandName: String)
    case inlineSourceNotAccepted(commandName: String)
    case emptyPath(commandName: String)
    case unsupportedPath(commandName: String, path: String)
    case emptyInlineSource(commandName: String)
    case rawStructuredJSONIRFields(commandName: String, fields: [String])
    case invalidPlanSource(String)
    case invalidArgument(source: String, reason: String)
    case invalidRootArgument(String)

    public var description: String {
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
            return """
            \(commandName) received raw JSON HeistPlan IR field(s): \(fields.joined(separator: ", ")). \
            Raw JSON IR and `plan.json` are internal generated artifact content. Use ButtonHeist DSL \
            source in `plan` or a generated `.heist` package artifact in `path`.
            """
        case .invalidPlanSource(let reason):
            return reason
        case .invalidArgument(let source, let reason):
            return "Invalid heist argument at \(source): \(reason)"
        case .invalidRootArgument(let reason):
            return "run_heist argument does not match root heist parameter: \(reason)"
        }
    }
}
