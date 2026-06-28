import Foundation

struct HeistInvocationPath: Sendable, Equatable, Hashable {
    enum ValidationError: Error, Sendable, Equatable, CustomStringConvertible {
        case emptyPath
        case emptyComponent(index: Int)

        var description: String {
            switch self {
            case .emptyPath:
                return "heist invocation path must not be empty"
            case .emptyComponent(let index):
                return "heist invocation path component at index \(index) must not be empty"
            }
        }
    }

    let components: [String]

    init(components: [String]) throws {
        guard !components.isEmpty else { throw ValidationError.emptyPath }
        for (index, component) in components.enumerated() where component.isEmpty {
            throw ValidationError.emptyComponent(index: index)
        }
        self.components = components
    }

    init(dottedName: String) throws {
        guard !dottedName.isEmpty else { throw ValidationError.emptyPath }
        try self.init(components: Self.strictComponents(fromDottedName: dottedName))
    }

    var dottedName: String {
        Self.render(components)
    }

    static func render(_ components: [String]) -> String {
        components.joined(separator: ".")
    }

    static func components(fromDottedName dottedName: String) -> [String] {
        dottedName.split(separator: ".").map(String.init)
    }

    private static func strictComponents(fromDottedName dottedName: String) -> [String] {
        dottedName.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }
}

public struct HeistInvocationStep: Codable, Sendable, Equatable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path, argument, expectation
    }

    public let path: [String]
    public let argument: HeistArgument
    public let expectation: WaitStep?
    let invocationPath: HeistInvocationPath?

    public init(
        path: [String],
        argument: HeistArgument = .none,
        expectation: WaitStep? = nil
    ) {
        self.path = path
        self.argument = argument
        self.expectation = expectation
        self.invocationPath = try? HeistInvocationPath(components: path)
    }

    init(
        invocationPath: HeistInvocationPath,
        argument: HeistArgument = .none,
        expectation: WaitStep? = nil
    ) {
        self.path = invocationPath.components
        self.argument = argument
        self.expectation = expectation
        self.invocationPath = invocationPath
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist invocation step")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pathComponents = try container.decode([String].self, forKey: .path)
        let invocationPath: HeistInvocationPath
        do {
            invocationPath = try HeistInvocationPath(components: pathComponents)
        } catch let error as HeistInvocationPath.ValidationError {
            throw DecodingError.dataCorruptedError(
                forKey: .path,
                in: container,
                debugDescription: error.description
            )
        }
        self.init(
            invocationPath: invocationPath,
            argument: try container.decodeIfPresent(HeistArgument.self, forKey: .argument) ?? .none,
            expectation: try container.decodeIfPresent(WaitStep.self, forKey: .expectation)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(argument, forKey: .argument)
        try container.encodeIfPresent(expectation, forKey: .expectation)
    }

    /// Dotted capability name, e.g. `LibraryScreen.addToCart`.
    public var capabilityName: String {
        invocationPath?.dottedName ?? HeistInvocationPath.render(path)
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
