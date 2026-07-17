import Foundation
import TheScore

@_spi(ButtonHeistTooling) public enum FenceCommandFamily: String, Sendable, CaseIterable {
    case session
    case observation
    case assertion
    case semanticAction
    case spatialAction
    case viewportDebug
    case heistRuntime
}

extension TheFence {

    public enum Command: String, CaseIterable, Sendable {
        case ping
        case listDevices = "list_devices"
        case getInterface = "get_interface"
        case getScreen = "get_screen"
        case getAnnouncements = "get_announcements"
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
        case validateHeist = "validate_heist"
        case listHeists = "list_heists"
        case describeHeist = "describe_heist"
        case getSessionState = "get_session_state"
        case connect
        case listTargets = "list_targets"
    }
}

@_spi(ButtonHeistTooling) public enum FenceCommandFixedTimeout: String, Sendable, Equatable, CaseIterable {
    case health
    case standardAction
    case longAction
    case explore
    case screenCapture

    public var seconds: TimeInterval {
        switch self {
        case .health:
            return 3
        case .standardAction:
            return 15
        case .longAction:
            return 30
        case .explore:
            return 60
        case .screenCapture:
            return 30
        }
    }
}

@_spi(ButtonHeistTooling) public enum FenceCommandTimeoutSemantics: Sendable, Equatable {
    case none
    case fixed(FenceCommandFixedTimeout)
    case wait
    case singleStepAction(base: FenceCommandFixedTimeout)
    case performStep

    public var fixedSeconds: TimeInterval? {
        guard case .fixed(let timeout) = self else { return nil }
        return timeout.seconds
    }

    public var singleStepBaseSeconds: TimeInterval? {
        guard case .singleStepAction(let timeout) = self else { return nil }
        return timeout.seconds
    }

    var requiredFixedSeconds: TimeInterval {
        guard let seconds = fixedSeconds else {
            preconditionFailure("Fence command timeout semantics are not fixed")
        }
        return seconds
    }

    var requiredSingleStepBaseSeconds: TimeInterval {
        guard let seconds = singleStepBaseSeconds else {
            preconditionFailure("Fence command timeout semantics are not single-step action")
        }
        return seconds
    }

    var requiredDirectDispatchSeconds: TimeInterval {
        switch self {
        case .fixed(let timeout), .singleStepAction(let timeout):
            return timeout.seconds
        case .none, .wait, .performStep:
            preconditionFailure("Fence command timeout semantics cannot direct-dispatch")
        }
    }
}

@_spi(ButtonHeistTooling) public struct FenceCommandDescriptor: Sendable, Equatable {
    public let command: TheFence.Command
    public let family: FenceCommandFamily
    public let requiresConnectionBeforeDispatch: Bool
    public let parameters: [FenceParameterSpec]
    public let projection: FenceCommandProjection
    public let timeout: FenceCommandTimeoutSemantics

    public var cliExposure: CLIExposure { projection.cliExposure }
    public var mcpExposure: MCPExposure { projection.mcpExposure }
    public var mcpAnnotations: MCPToolAnnotationSpec? { projection.mcpAnnotations }
    public var description: String { projection.description }

    public var isPublicRequestContract: Bool {
        projection.isPublicRequestContract
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

    public func defaultValue<Value>(for parameter: FenceParameter<Value>) -> Value? {
        _ = resolvedParameter(for: parameter)
        return parameter.defaultValue
    }

    public func requiredDefaultValue<Value>(for parameter: FenceParameter<Value>) -> Value {
        guard let value = defaultValue(for: parameter) else {
            preconditionFailure("No default registered for \(command.rawValue).\(parameter.key.rawValue)")
        }
        return value
    }

    public func allowedRawValues<Value>(for parameter: FenceParameter<Value>) -> [String] {
        _ = resolvedParameter(for: parameter)
        guard let values = parameter.allowedRawValues else {
            preconditionFailure("No enum values registered for \(command.rawValue).\(parameter.key.rawValue)")
        }
        return values
    }

    init(
        command: TheFence.Command,
        family: FenceCommandFamily,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec],
        timeout: FenceCommandTimeoutSemantics = .none,
        projection: FenceCommandProjection
    ) {
        self.command = command
        self.family = family
        self.requiresConnectionBeforeDispatch = requiresConnectionBeforeDispatch
        self.parameters = parameters
        self.timeout = timeout
        self.projection = projection
    }

    private func resolvedParameter<Value>(for parameter: FenceParameter<Value>) -> FenceParameterSpec {
        guard let spec = self.parameter(named: parameter.key),
              spec == parameter.spec else {
            preconditionFailure("No matching parameter registered for \(command.rawValue).\(parameter.key.rawValue)")
        }
        return spec
    }
}

@_spi(ButtonHeistTooling) public struct FenceCommandProjection: Sendable, Equatable {
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

@_spi(ButtonHeistTooling) public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor {
        switch self {
        case .ping, .listDevices, .getSessionState, .connect, .listTargets:
            return makeSessionDescriptor()
        case .getInterface, .getScreen, .getPasteboard, .getAnnouncements:
            return makeObservationDescriptor()
        case .wait:
            return makeAssertionDescriptor()
        case .oneFingerTap, .longPress, .swipe, .drag:
            return makeSpatialActionDescriptor()
        case .scroll, .scrollToVisible, .scrollToEdge:
            return makeViewportDebugDescriptor()
        case .activate, .rotor, .typeText, .editAction, .setPasteboard, .dismissKeyboard:
            return makeSemanticActionDescriptor()
        case .perform, .runHeist, .validateHeist, .listHeists, .describeHeist:
            return makeHeistRuntimeDescriptor()
        }
    }

    static var descriptors: [FenceCommandDescriptor] { allCases.map(\.descriptor) }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.projection.cliExposure == .directCommand }
    }
}

extension TheFence.Command {
    func makeDescriptor(
        family: FenceCommandFamily,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: [FenceParameterSpec] = [],
        timeout: FenceCommandTimeoutSemantics = .none,
        projection: FenceCommandProjection
    ) -> FenceCommandDescriptor {
        FenceCommandDescriptor(
            command: self,
            family: family,
            requiresConnectionBeforeDispatch: requiresConnectionBeforeDispatch,
            parameters: parameters,
            timeout: timeout,
            projection: projection
        )
    }
}
