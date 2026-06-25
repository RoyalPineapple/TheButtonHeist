import Foundation

public struct HeistInvocationStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path, argument
    }

    public let path: [String]
    public let argument: HeistArgument

    public init(
        path: [String],
        argument: HeistArgument = .none
    ) {
        self.path = path
        self.argument = argument
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist invocation step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode([String].self, forKey: .path),
            argument: try container.decodeIfPresent(HeistArgument.self, forKey: .argument) ?? .none
        )
    }

    /// Dotted capability name, e.g. `LibraryScreen.addToCart`.
    public var capabilityName: String {
        path.joined(separator: ".")
    }

    /// Report/display summary of this run as `RunHeist("Name", argument)`.
    /// The frame is the product — reports surface this rather than a bare
    /// `invoke`, so a reader can see which capability ran and with what.
    public var runHeistSummary: String {
        let name = "\"\(capabilityName)\""
        switch argument {
        case .none:
            return "RunHeist(\(name))"
        case .string(let value):
            return "RunHeist(\(name), \(Self.stringArgumentSummary(value)))"
        case .elementTarget(let target):
            return "RunHeist(\(name), \(Self.targetArgumentSummary(target)))"
        }
    }

    private static func stringArgumentSummary(_ expr: StringExpr) -> String {
        switch expr {
        case .literal(let value):
            return "\"\(value)\""
        case .ref(let reference):
            return reference.rawValue
        }
    }

    private static func targetArgumentSummary(_ expr: ElementTargetExpr) -> String {
        switch expr {
        case .ref(let reference):
            return reference.rawValue
        default:
            return expr.description
        }
    }
}
