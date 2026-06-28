import Foundation
import TheScore

public enum FenceCommandFamily: String, Sendable, CaseIterable {
    case session
    case observation
    case assertion
    case semanticAction
    case spatialAction
    case viewportDebug
    case heistRuntime
}

protocol FenceCommand: RawRepresentable, CaseIterable, Sendable
where RawValue == String, AllCases: Sequence, AllCases.Element == Self {
    static var descriptors: [FenceCommandDescriptor] { get }
    var command: TheFence.Command { get }
    var descriptor: FenceCommandDescriptor { get }
}

extension FenceCommand {
    var command: TheFence.Command {
        guard let command = TheFence.Command(rawValue: rawValue) else {
            preconditionFailure("Fence command \(Self.self).\(rawValue) does not map to TheFence.Command")
        }
        return command
    }
}

extension FenceCommand where AllCases: Sequence, AllCases.Element == Self {
    static var descriptors: [FenceCommandDescriptor] {
        allCases.map(\.descriptor)
    }
}

struct FenceCommandFamilyRegistration: Sendable {
    let family: FenceCommandFamily
    let descriptors: [FenceCommandDescriptor]
}

enum FenceCommandRegistry {
    static let families: [FenceCommandFamilyRegistration] = [
        .init(family: .session, descriptors: SessionCommand.descriptors),
        .init(family: .observation, descriptors: ObservationCommand.descriptors),
        .init(family: .assertion, descriptors: AssertionCommand.descriptors),
        .init(family: .semanticAction, descriptors: SemanticActionCommand.descriptors),
        .init(family: .spatialAction, descriptors: SpatialActionCommand.descriptors),
        .init(family: .viewportDebug, descriptors: ViewportDebugCommand.descriptors),
        .init(family: .heistRuntime, descriptors: HeistRuntimeCommand.descriptors),
    ]

    static let descriptors: [FenceCommandDescriptor] = TheFence.Command.allCases.map(descriptor(for:))

    static func family(for command: TheFence.Command) -> FenceCommandFamily {
        descriptor(for: command).family
    }

    static func descriptor(for command: TheFence.Command) -> FenceCommandDescriptor {
        guard let descriptor = descriptorLookup[command] else {
            preconditionFailure("Missing descriptor for \(command.rawValue)")
        }
        return descriptor
    }

    static func isAppInteractionCommand(_ command: TheFence.Command) -> Bool {
        descriptor(for: command).execution.contains(.appInteraction)
    }

    static func isHeistPrimitiveCommand(_ command: TheFence.Command) -> Bool {
        descriptor(for: command).execution.contains(.heistPrimitive)
    }

    static func isPayloadCheckedHeistPrimitiveCommand(_ command: TheFence.Command) -> Bool {
        descriptor(for: command).execution.contains(.payloadCheckedHeistPrimitive)
    }

    static func viewportDebugCommand(for command: TheFence.Command) -> ViewportDebugCommand? {
        ViewportDebugCommand(rawValue: command.rawValue)
    }

    private static let descriptorLookup: [TheFence.Command: FenceCommandDescriptor] = {
        let familyDescriptors = families.flatMap(\.descriptors)
        let commandCounts = Dictionary(grouping: familyDescriptors, by: \.command).mapValues(\.count)
        let duplicates = commandCounts.filter { $0.value > 1 }.keys.map(\.rawValue).sorted()
        precondition(duplicates.isEmpty, "Duplicate Fence command descriptors: \(duplicates.joined(separator: ", "))")

        let missing = Set(TheFence.Command.allCases).subtracting(commandCounts.keys).map(\.rawValue).sorted()
        precondition(missing.isEmpty, "Missing Fence command descriptors: \(missing.joined(separator: ", "))")

        let extra = Set(commandCounts.keys).subtracting(TheFence.Command.allCases).map(\.rawValue).sorted()
        precondition(extra.isEmpty, "Unknown Fence command descriptors: \(extra.joined(separator: ", "))")

        return Dictionary(uniqueKeysWithValues: familyDescriptors.map { ($0.command, $0) })
    }()
}

extension TheFence {

    public enum Command: String, CaseIterable, Sendable {
        case ping
        case listDevices = "list_devices"
        case getInterface = "get_interface"
        case getScreen = "get_screen"
        case wait
        case oneFingerTap = "one_finger_tap"
        case longPress = "long_press"
        case swipe
        case drag
        case scroll
        case scrollToVisible = "scroll_to_visible"
        case scrollToEdge = "scroll_to_edge"
        case activate
        case rotor
        case typeText = "type_text"
        case editAction = "edit_action"
        case setPasteboard = "set_pasteboard"
        case getPasteboard = "get_pasteboard"
        case dismissKeyboard = "dismiss_keyboard"
        case perform
        case runHeist = "run_heist"
        case listHeists = "list_heists"
        case describeHeist = "describe_heist"
        case getSessionState = "get_session_state"
        case connect
        case listTargets = "list_targets"
    }
}

struct FenceCommandExecution: OptionSet, Sendable, Equatable {
    let rawValue: Int

    static let appInteraction = FenceCommandExecution(rawValue: 1 << 0)
    static let heistPrimitive = FenceCommandExecution(rawValue: 1 << 1)
    static let payloadCheckedHeistPrimitive = FenceCommandExecution(rawValue: 1 << 2)
}

public struct FenceCommandDescriptor: Sendable, Equatable {
    public let command: TheFence.Command
    public let family: FenceCommandFamily
    public let requiresConnectionBeforeDispatch: Bool
    public let parameters: [FenceParameterSpec]
    public let projection: FenceCommandProjection
    let execution: FenceCommandExecution
    let requestDecoder: TheFence.RequestDecoder

    public var cliExposure: CLIExposure { projection.cliExposure }
    public var mcpExposure: MCPExposure { projection.mcpExposure }
    public var mcpAnnotations: MCPToolAnnotationSpec? { projection.mcpAnnotations }
    public var description: String { projection.description }

    public var isPublicRequestContract: Bool {
        projection.isPublicRequestContract
    }

    public var elementTargetParameterKeys: [String] {
        let elementTargetKeys = Set(FenceParameterBlocks.elementTarget.map(\.key))
        return parameters.map(\.key).filter(elementTargetKeys.contains)
    }

    public var topLevelParameterKeys: Set<String> {
        Set(parameters.map(\.key))
    }

    public func parameter(named key: FenceParameterKey) -> FenceParameterSpec? {
        let matches = parameters.flatMap { $0.parameters(named: key) }
        guard let first = matches.first,
              matches.dropFirst().allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    public func defaultArgumentValue(for key: FenceParameterKey) -> HeistValue? {
        parameter(named: key)?.defaultValue
    }

    public func requiredDefaultString(for key: FenceParameterKey) -> String {
        guard case .string(let value)? = defaultArgumentValue(for: key) else {
            preconditionFailure("No string default registered for \(command.rawValue).\(key.rawValue)")
        }
        return value
    }

    public func requiredDefaultEnumValue<E>(
        for key: FenceParameterKey,
        as type: E.Type
    ) -> E where E: RawRepresentable, E.RawValue == String {
        let rawValue = requiredDefaultString(for: key)
        guard let value = E(rawValue: rawValue) else {
            preconditionFailure("Invalid default \(rawValue) for \(command.rawValue).\(key.rawValue)")
        }
        return value
    }

    init(
        command: TheFence.Command,
        family: FenceCommandFamily,
        requestDecoder: @escaping TheFence.RequestDecoder,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec],
        execution: FenceCommandExecution = [],
        projection: FenceCommandProjection
    ) {
        self.command = command
        self.family = family
        self.requestDecoder = requestDecoder
        self.requiresConnectionBeforeDispatch = requiresConnectionBeforeDispatch
        self.parameters = parameters
        self.execution = execution
        self.projection = projection
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Decoder closures are intentionally excluded: command identity owns the routing entrypoint.
        lhs.command == rhs.command &&
            lhs.family == rhs.family &&
            lhs.requiresConnectionBeforeDispatch == rhs.requiresConnectionBeforeDispatch &&
            lhs.parameters == rhs.parameters &&
            lhs.execution == rhs.execution &&
            lhs.projection == rhs.projection
    }
}

public struct FenceCommandProjection: Sendable, Equatable {
    public let cliExposure: CLIExposure
    public let mcpExposure: MCPExposure
    public let mcpAnnotations: MCPToolAnnotationSpec?
    public let description: String

    public var isPublicRequestContract: Bool {
        cliExposure != .notExposed || mcpExposure != .notExposed
    }

    init(
        cliExposure: CLIExposure = .directCommand,
        mcpExposure: MCPExposure = .directTool,
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        description: String
    ) {
        self.cliExposure = cliExposure
        self.mcpExposure = mcpExposure
        self.mcpAnnotations = mcpAnnotations
        self.description = description
    }

    static func cliAndMCP(
        _ description: String,
        mcpAnnotations: MCPToolAnnotationSpec? = nil
    ) -> Self {
        Self(mcpAnnotations: mcpAnnotations, description: description)
    }

    static func cliOnly(
        _ description: String,
        mcpAnnotations: MCPToolAnnotationSpec? = nil
    ) -> Self {
        // CLI-only commands may still keep MCP annotations as reference metadata for generated docs.
        Self(mcpExposure: .notExposed, mcpAnnotations: mcpAnnotations, description: description)
    }

    static func mcpOnly(
        _ description: String,
        mcpAnnotations: MCPToolAnnotationSpec? = nil
    ) -> Self {
        Self(cliExposure: .notExposed, mcpAnnotations: mcpAnnotations, description: description)
    }
}

public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor { FenceCommandRegistry.descriptor(for: self) }

    var family: FenceCommandFamily { FenceCommandRegistry.family(for: self) }

    static var descriptors: [FenceCommandDescriptor] { FenceCommandRegistry.descriptors }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.projection.cliExposure == .directCommand }
    }
}

extension TheFence.Command {

    var isAppInteractionCommand: Bool {
        FenceCommandRegistry.isAppInteractionCommand(self)
    }

    var isHeistPrimitiveCommand: Bool {
        FenceCommandRegistry.isHeistPrimitiveCommand(self)
    }

    var isPayloadCheckedHeistPrimitiveCommand: Bool {
        FenceCommandRegistry.isPayloadCheckedHeistPrimitiveCommand(self)
    }

    var viewportDebugCommand: ViewportDebugCommand? {
        FenceCommandRegistry.viewportDebugCommand(for: self)
    }

    static var heistPrimitiveCases: [Self] {
        descriptors
            .filter { $0.execution.contains(.heistPrimitive) }
            .map(\.command)
    }
}

extension TheFence.Command {
    static func descriptor(for command: Self) -> FenceCommandDescriptor {
        FenceCommandRegistry.descriptor(for: command)
    }

    static func commandDescriptor(
        _ command: Self,
        family: FenceCommandFamily,
        requestDecoder: @escaping TheFence.RequestDecoder,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec] = [],
        execution: FenceCommandExecution = [],
        projection: FenceCommandProjection
    ) -> FenceCommandDescriptor {
        FenceCommandDescriptor(
            command: command,
            family: family,
            requestDecoder: requestDecoder,
            requiresConnectionBeforeDispatch: requiresConnectionBeforeDispatch,
            parameters: parameters,
            execution: execution,
            projection: projection
        )
    }
}
