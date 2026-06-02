import Foundation
import TheScore

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
    public let cliExposure: CLIExposure
    public let mcpExposure: MCPExposure
    public let isHeistExecutable: Bool
    public let requiresConnectionBeforeDispatch: Bool
    public let parameters: [FenceParameterSpec]
    public let mcpAnnotations: MCPToolAnnotationSpec?
    public let description: String
    let requestDecoder: TheFence.RequestDecoder

    public var isPublicRequestContract: Bool {
        cliExposure != .notExposed || mcpExposure != .notExposed || isHeistExecutable
    }

    public var elementTargetParameterKeys: [String] {
        let elementTargetKeys = Set(FenceParameterBlocks.elementTarget.map(\.key))
        return parameters.map(\.key).filter(elementTargetKeys.contains)
    }

    public func parameter(named key: FenceParameterKey) -> FenceParameterSpec? {
        parameters.first { $0.key == key.rawValue }
    }

    public func defaultArgumentValue(for key: FenceParameterKey) -> HeistValue? {
        parameter(named: key)?.defaultValue
    }

    init(
        command: TheFence.Command,
        requestDecoder: @escaping TheFence.RequestDecoder,
        cliExposure: CLIExposure,
        mcpExposure: MCPExposure,
        isHeistExecutable: Bool,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec],
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        description: String
    ) {
        self.command = command
        self.requestDecoder = requestDecoder
        self.cliExposure = cliExposure
        self.mcpExposure = mcpExposure
        self.isHeistExecutable = isHeistExecutable
        self.requiresConnectionBeforeDispatch = requiresConnectionBeforeDispatch
        self.parameters = parameters
        self.mcpAnnotations = mcpAnnotations
        self.description = description
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        // Decoder closures are intentionally excluded: command identity owns the routing entrypoint.
        lhs.command == rhs.command &&
            lhs.cliExposure == rhs.cliExposure &&
            lhs.mcpExposure == rhs.mcpExposure &&
            lhs.isHeistExecutable == rhs.isHeistExecutable &&
            lhs.requiresConnectionBeforeDispatch == rhs.requiresConnectionBeforeDispatch &&
            lhs.parameters == rhs.parameters &&
            lhs.mcpAnnotations == rhs.mcpAnnotations &&
            lhs.description == rhs.description
    }
}

public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor { Self.descriptor(for: self) }

    static var descriptors: [FenceCommandDescriptor] { allCases.map(descriptor(for:)) }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.cliExposure == .directCommand }
    }

    static var heistExecutableCases: [Self] {
        heistExecutableCommandDescriptors.map(\.command)
    }

}

extension TheFence.Command {
    static func descriptor(for command: Self) -> FenceCommandDescriptor {
        guard let descriptor = descriptorLookup[command] else {
            preconditionFailure("Missing descriptor for \(command.rawValue)")
        }
        return descriptor
    }

    private static let descriptorLookup: [Self: FenceCommandDescriptor] = {
        Dictionary(uniqueKeysWithValues: commandDescriptors.map { ($0.command, $0) })
    }()

    private static var commandDescriptors: [FenceCommandDescriptor] {
        commandDescriptorsWithoutRunHeist + [runHeistCommandDescriptor]
    }

    private static var commandDescriptorsWithoutRunHeist: [FenceCommandDescriptor] {
        sessionCommandDescriptors
            + observationCommandDescriptors
            + actionCommandDescriptors
    }

    static var heistExecutableCommandDescriptors: [FenceCommandDescriptor] {
        commandDescriptorsWithoutRunHeist.filter(\.isHeistExecutable)
    }

    static func commandDescriptor(
        _ command: Self,
        requestDecoder: @escaping TheFence.RequestDecoder,
        cliExposure: CLIExposure = .directCommand,
        mcpExposure: MCPExposure = .directTool,
        isHeistExecutable: Bool = false,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec] = [],
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        description: String
    ) -> FenceCommandDescriptor {
        FenceCommandDescriptor(
            command: command,
            requestDecoder: requestDecoder,
            cliExposure: cliExposure,
            mcpExposure: mcpExposure,
            isHeistExecutable: isHeistExecutable,
            requiresConnectionBeforeDispatch: requiresConnectionBeforeDispatch,
            parameters: parameters,
            mcpAnnotations: mcpAnnotations,
            description: description
        )
    }
}
