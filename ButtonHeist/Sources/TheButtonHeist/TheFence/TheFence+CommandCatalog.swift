import Foundation
import TheScore

public enum FenceCommandFamily: String, Sendable, CaseIterable {
    case session
    case observation
    case semanticAction
    case spatialAction
    case viewportDebug
    case heistRuntime
    case heistRecording
}

protocol FenceCommandFamilyCase: RawRepresentable, CaseIterable, Sendable
where RawValue == String, AllCases: Sequence, AllCases.Element == Self {
    static var family: FenceCommandFamily { get }
    static var descriptors: [FenceCommandDescriptor] { get }
    var command: TheFence.Command { get }
    var descriptor: FenceCommandDescriptor { get }
}

extension FenceCommandFamilyCase {
    var command: TheFence.Command {
        guard let command = TheFence.Command(rawValue: rawValue) else {
            preconditionFailure("Fence command family case \(Self.self).\(rawValue) does not map to TheFence.Command")
        }
        return command
    }
}

extension FenceCommandFamilyCase where AllCases: Sequence, AllCases.Element == Self {
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
        .init(family: SessionCommand.family, descriptors: SessionCommand.descriptors),
        .init(family: ObservationCommand.family, descriptors: ObservationCommand.descriptors),
        .init(family: SemanticActionCommand.family, descriptors: SemanticActionCommand.descriptors),
        .init(family: SpatialActionCommand.family, descriptors: SpatialActionCommand.descriptors),
        .init(family: ViewportDebugCommand.family, descriptors: ViewportDebugCommand.descriptors),
        .init(family: HeistRuntimeCommand.family, descriptors: HeistRuntimeCommand.descriptors),
        .init(family: HeistRecordingCommand.family, descriptors: HeistRecordingCommand.descriptors),
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
        case runHeist = "run_heist"
        case getSessionState = "get_session_state"
        case connect
        case listTargets = "list_targets"
        case startHeist = "start_heist"
        case stopHeist = "stop_heist"
        case playHeist = "play_heist"
    }
}

public struct FenceCommandDescriptor: Sendable, Equatable {
    public let command: TheFence.Command
    public let family: FenceCommandFamily
    public let cliExposure: CLIExposure
    public let mcpExposure: MCPExposure
    public let requiresConnectionBeforeDispatch: Bool
    public let parameters: [FenceParameterSpec]
    public let mcpAnnotations: MCPToolAnnotationSpec?
    public let description: String
    let requestDecoder: TheFence.RequestDecoder

    public var isPublicRequestContract: Bool {
        cliExposure != .notExposed || mcpExposure != .notExposed || isDurableHeistPrimitive
    }

    public var isObservation: Bool {
        family == .observation
    }

    public var isViewportDebug: Bool {
        family == .viewportDebug
    }

    public var isSemanticAction: Bool {
        family == .semanticAction
    }

    public var isSpatialAction: Bool {
        family == .spatialAction
    }

    public var isNormalRecordable: Bool {
        switch family {
        case .semanticAction, .spatialAction:
            return true
        case .session, .observation, .viewportDebug, .heistRuntime, .heistRecording:
            return false
        }
    }

    public var recordsHeistStep: Bool {
        isNormalRecordable || command == .wait
    }

    public var isDurableHeistPrimitive: Bool {
        switch family {
        case .semanticAction, .spatialAction:
            return true
        case .observation:
            return command == .wait
        case .session, .viewportDebug, .heistRuntime, .heistRecording:
            return false
        }
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
        cliExposure: CLIExposure,
        mcpExposure: MCPExposure,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec],
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        description: String
    ) {
        self.command = command
        self.family = family
        self.requestDecoder = requestDecoder
        self.cliExposure = cliExposure
        self.mcpExposure = mcpExposure
        self.requiresConnectionBeforeDispatch = requiresConnectionBeforeDispatch
        self.parameters = parameters
        self.mcpAnnotations = mcpAnnotations
        self.description = description
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Decoder closures are intentionally excluded: command identity owns the routing entrypoint.
        lhs.command == rhs.command &&
            lhs.family == rhs.family &&
            lhs.cliExposure == rhs.cliExposure &&
            lhs.mcpExposure == rhs.mcpExposure &&
            lhs.requiresConnectionBeforeDispatch == rhs.requiresConnectionBeforeDispatch &&
            lhs.parameters == rhs.parameters &&
            lhs.mcpAnnotations == rhs.mcpAnnotations &&
            lhs.description == rhs.description
    }
}

public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor { FenceCommandRegistry.descriptor(for: self) }

    var family: FenceCommandFamily { FenceCommandRegistry.family(for: self) }

    static var descriptors: [FenceCommandDescriptor] { FenceCommandRegistry.descriptors }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.cliExposure == .directCommand }
    }

    static var durableHeistPrimitiveCases: [Self] {
        descriptors.filter(\.isDurableHeistPrimitive).map(\.command)
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
        cliExposure: CLIExposure = .directCommand,
        mcpExposure: MCPExposure = .directTool,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec] = [],
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        description: String
    ) -> FenceCommandDescriptor {
        FenceCommandDescriptor(
            command: command,
            family: family,
            requestDecoder: requestDecoder,
            cliExposure: cliExposure,
            mcpExposure: mcpExposure,
            requiresConnectionBeforeDispatch: requiresConnectionBeforeDispatch,
            parameters: parameters,
            mcpAnnotations: mcpAnnotations,
            description: description
        )
    }
}
