import Foundation

public enum HeistPlanning {
    public static func readPlan(from url: URL) throws -> HeistPlan {
        try HeistArtifactCodec.readPlan(from: url)
    }

    public static func decodePlanJSON(
        _ data: Data,
        sourceURL: URL = URL(fileURLWithPath: "inline-heist-plan.json")
    ) throws -> HeistPlan {
        try HeistPlanJSONCodec.decodeValidatedPlan(data, sourceURL: sourceURL)
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
}

public enum HeistPlanningError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidArgument(source: String, reason: String)
    case invalidRootArgument(String)

    public var description: String {
        switch self {
        case .invalidArgument(let source, let reason):
            return "Invalid heist argument at \(source): \(reason)"
        case .invalidRootArgument(let reason):
            return "run_heist argument does not match root heist parameter: \(reason)"
        }
    }
}
