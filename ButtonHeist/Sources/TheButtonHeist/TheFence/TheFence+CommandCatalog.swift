import Foundation
import TheScore

extension TheFence {

    /// Canonical set of all commands supported by TheFence (CLI and MCP).
    public enum Command: String, CaseIterable, Sendable {
        case help
        case ping
        case quit
        case listDevices = "list_devices"
        case getInterface = "get_interface"
        case getScreen = "get_screen"
        case waitForChange = "wait_for_change"
        case oneFingerTap = "one_finger_tap"
        case longPress = "long_press"
        case swipe
        case drag
        case pinch
        case rotate
        case twoFingerTap = "two_finger_tap"
        case drawPath = "draw_path"
        case drawBezier = "draw_bezier"
        case scroll
        case scrollToVisible = "scroll_to_visible"
        case elementSearch = "element_search"
        case scrollToEdge = "scroll_to_edge"
        case activate
        case rotor
        case typeText = "type_text"
        case editAction = "edit_action"
        case setPasteboard = "set_pasteboard"
        case getPasteboard = "get_pasteboard"
        case waitFor = "wait_for"
        case dismissKeyboard = "dismiss_keyboard"
        case startRecording = "start_recording"
        case stopRecording = "stop_recording"
        case runBatch = "run_batch"
        case getSessionState = "get_session_state"
        case connect
        case listTargets = "list_targets"
        case getSessionLog = "get_session_log"
        case archiveSession = "archive_session"
        case startHeist = "start_heist"
        case stopHeist = "stop_heist"
        case playHeist = "play_heist"
    }
}

/// Canonical command descriptor for TheFence command surfaces.
///
/// The enum is the stable wire identity. This descriptor owns the contract
/// projected from that identity: adapter exposure, batch eligibility,
/// parameter shape, and user-facing help text.
public struct FenceCommandDescriptor: Sendable, Equatable {
    public let command: TheFence.Command
    public var canonicalName: String { command.rawValue }
    /// The server action method that unambiguously projects back to this public command.
    public let actionResultMethod: ActionMethod?
    public let requestPayloadKind: FenceRequestPayloadKind
    public let cliExposure: CLIExposure
    public let mcpExposure: MCPExposure
    public let isBatchExecutable: Bool
    public var isPlaybackExecutable: Bool { isBatchExecutable }
    public var isHeistRecordable: Bool { isPlaybackExecutable }
    public let requiresConnectionBeforeDispatch: Bool
    public let humanPositionalSyntax: FenceHumanPositionalSyntax
    public let parameters: [FenceParameterSpec]
    public let mcpAnnotations: MCPToolAnnotationSpec?
    public let recordsActionCompletion: Bool
    public let description: String

    public var isPublicRequestContract: Bool {
        cliExposure != .notExposed || mcpExposure != .notExposed || isBatchExecutable
    }

    /// Parameter keys that identify an element target for this command.
    ///
    /// Adapters use this projection when they need to talk about target matcher
    /// fields without knowing how the catalog orders or composes parameter blocks.
    public var elementTargetParameterKeys: [String] {
        let elementTargetKeys = Set(FenceParameterBlocks.elementTarget.map(\.key))
        return parameters.map(\.key).filter(elementTargetKeys.contains)
    }

    public init(
        command: TheFence.Command,
        actionResultMethod: ActionMethod? = nil,
        requestPayloadKind: FenceRequestPayloadKind,
        cliExposure: CLIExposure,
        mcpExposure: MCPExposure,
        isBatchExecutable: Bool,
        requiresConnectionBeforeDispatch: Bool = true,
        humanPositionalSyntax: FenceHumanPositionalSyntax = .target,
        parameters: [FenceParameterSpec],
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        recordsActionCompletion: Bool = true,
        description: String
    ) {
        self.command = command
        self.actionResultMethod = actionResultMethod
        self.requestPayloadKind = requestPayloadKind
        self.cliExposure = cliExposure
        self.mcpExposure = mcpExposure
        self.isBatchExecutable = isBatchExecutable
        self.requiresConnectionBeforeDispatch = requiresConnectionBeforeDispatch
        self.humanPositionalSyntax = humanPositionalSyntax
        self.parameters = parameters
        self.mcpAnnotations = mcpAnnotations
        self.recordsActionCompletion = recordsActionCompletion
        self.description = description
    }
}

/// Catalog-owned request payload family for a Fence command.
///
/// This keeps request parsing routed by command metadata instead of a separate
/// switch in request decoding. The individual family decoders still own field
/// validation for their typed payloads.
public enum FenceRequestPayloadKind: Sendable, Equatable {
    case none
    case observation
    case waitForChange
    case gesture
    case elementAction
    case session
}

/// Catalog-owned positional grammar for the CLI's human command parser.
///
/// The CLI still owns tokenization and key=value parsing. Command-specific
/// meaning for positional tokens lives here so adapters do not mirror command
/// identity or parameter roles.
public enum FenceHumanPositionalSyntax: Sendable, Equatable {
    case target
    case joinedText(FenceParameterKey)
    case firstToken(FenceParameterKey)
    case targetThenJoinedText(FenceParameterKey)
    case leadingDirectionThenTarget(Set<String>)
    case leadingEdgeThenTarget(Set<String>)
}

extension FenceCommandDescriptor {
    func executionTimeout(for request: TheFence.ParsedRequest) throws -> TimeInterval {
        if actionResultMethod == .getPasteboard {
            return Timeouts.healthSeconds
        }
        if actionResultMethod == .elementSearch || actionResultMethod == .typeText {
            return Timeouts.longActionSeconds
        }
        if actionResultMethod == .waitFor {
            guard case .waitFor(let target) = request.payload else {
                throw FenceError.invalidRequest("command \"\(canonicalName)\" is missing wait_for payload")
            }
            return target.resolvedTimeout + 5
        }
        if actionResultMethod == .waitForChange {
            guard case .waitForChange(let payload) = request.payload else {
                throw FenceError.invalidRequest("command \"\(canonicalName)\" is missing wait_for_change payload")
            }
            let target = WaitForChangeTarget(expect: payload.expectation, timeout: payload.timeout)
            return target.resolvedTimeout + 5
        }
        return Timeouts.actionSeconds
    }
}

public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor {
        Self.descriptor(for: self)
    }

    static func descriptor(forActionResultMethod method: ActionMethod) -> FenceCommandDescriptor? {
        descriptors.first { $0.actionResultMethod == method }
    }

    static func canonicalName(forActionResultMethod method: ActionMethod) -> String {
        switch method {
        case .increment, .decrement, .customAction:
            return Self.activate.rawValue
        case .syntheticTap:
            return Self.oneFingerTap.rawValue
        case .syntheticDrawPath:
            return Self.drawPath.rawValue
        case .batchExecutionPlan:
            return Self.runBatch.rawValue
        default:
            break
        }
        return descriptor(forActionResultMethod: method)?.canonicalName ?? method.rawValue
    }

    static var descriptors: [FenceCommandDescriptor] {
        allCases.map(descriptor(for:))
    }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.cliExposure == .directCommand }
    }

    var canonicalName: String {
        descriptor.canonicalName
    }

    var cliCommandName: String {
        canonicalName
    }

    var cliExposure: CLIExposure {
        descriptor.cliExposure
    }

    var mcpExposure: MCPExposure {
        descriptor.mcpExposure
    }

    var parameters: [FenceParameterSpec] {
        descriptor.parameters
    }

    var requestPayloadKind: FenceRequestPayloadKind {
        descriptor.requestPayloadKind
    }

    func parameter(named key: FenceParameterKey) -> FenceParameterSpec? {
        parameters.first { $0.key == key.rawValue }
    }

    func defaultArgumentValue(for key: FenceParameterKey) -> HeistValue? {
        parameter(named: key)?.defaultValue
    }

    var humanPositionalSyntax: FenceHumanPositionalSyntax {
        descriptor.humanPositionalSyntax
    }

    static let humanDirectionValues = Set(fenceEnumValues(ScrollDirection.self))

    static let humanScrollEdgeValues = Set(fenceEnumValues(ScrollEdge.self))

    /// Commands that can execute as a run_batch step.
    ///
    /// Session-control and batch-orchestration commands are accepted at
    /// external edges but should not appear in batch schemas or execution.
    var isBatchExecutable: Bool {
        descriptor.isBatchExecutable
    }

    static var batchExecutableCases: [Self] {
        allCases.filter(\.catalogBatchExecutable)
    }

    /// Commands that can execute as a heist playback step.
    var isPlaybackExecutable: Bool {
        descriptor.isPlaybackExecutable
    }

    static var playbackExecutableCases: [Self] {
        batchExecutableCases
    }

    /// Commands that are persisted when a heist recording is active.
    var isHeistRecordable: Bool {
        descriptor.isHeistRecordable
    }

    /// Commands that should establish a device connection before dispatch.
    var requiresConnectionBeforeDispatch: Bool {
        descriptor.requiresConnectionBeforeDispatch
    }

    static var mcpToolContracts: [MCPToolContract] {
        descriptors.compactMap { descriptor in
            guard descriptor.mcpExposure == .directTool else { return nil }
            return MCPToolContract(
                name: descriptor.canonicalName,
                command: descriptor.command,
                description: descriptor.description,
                annotations: descriptor.mcpAnnotations
            )
        }
    }

    static func mcpToolContract(named name: String) -> MCPToolContract? {
        mcpToolContracts.first { $0.name == name }
    }
}

extension TheFence.Command {
    static func descriptor(for command: Self) -> FenceCommandDescriptor {
        FenceCommandDescriptor(
            command: command,
            actionResultMethod: command.catalogActionResultMethod,
            requestPayloadKind: command.catalogRequestPayloadKind,
            cliExposure: command.catalogCLIExposure,
            mcpExposure: command.catalogMCPExposure,
            isBatchExecutable: command.catalogBatchExecutable,
            requiresConnectionBeforeDispatch: command.catalogRequiresConnectionBeforeDispatch,
            humanPositionalSyntax: command.catalogHumanPositionalSyntax,
            parameters: command.catalogParameters,
            mcpAnnotations: command.catalogMCPAnnotations,
            recordsActionCompletion: command.catalogRecordsActionCompletion,
            description: presentationDescription(for: command.rawValue)
        )
    }

    var catalogActionResultMethod: ActionMethod? {
        switch self {
        case .waitForChange:
            return .waitForChange
        case .longPress:
            return .syntheticLongPress
        case .swipe:
            return .syntheticSwipe
        case .drag:
            return .syntheticDrag
        case .pinch:
            return .syntheticPinch
        case .rotate:
            return .syntheticRotate
        case .twoFingerTap:
            return .syntheticTwoFingerTap
        case .scroll:
            return .scroll
        case .scrollToVisible:
            return .scrollToVisible
        case .elementSearch:
            return .elementSearch
        case .scrollToEdge:
            return .scrollToEdge
        case .activate:
            return .activate
        case .rotor:
            return .rotor
        case .typeText:
            return .typeText
        case .editAction:
            return .editAction
        case .setPasteboard:
            return .setPasteboard
        case .getPasteboard:
            return .getPasteboard
        case .waitFor:
            return .waitFor
        case .dismissKeyboard:
            return .resignFirstResponder
        case .oneFingerTap, .drawPath, .drawBezier:
            // `syntheticTap` and `syntheticDrawPath` can come from multiple
            // public commands, so keep those action methods diagnostic-only.
            return nil
        case .help, .ping, .quit,
             .listDevices, .getInterface, .getScreen,
             .startRecording, .stopRecording, .runBatch,
             .getSessionState, .connect, .listTargets,
             .getSessionLog, .archiveSession,
             .startHeist, .stopHeist, .playHeist:
            return nil
        }
    }

    var catalogRequestPayloadKind: FenceRequestPayloadKind {
        switch self {
        case .help, .ping, .quit, .listDevices, .getPasteboard,
             .dismissKeyboard, .getSessionState, .listTargets, .getSessionLog:
            return .none
        case .getInterface, .getScreen, .stopRecording:
            return .observation
        case .waitForChange:
            return .waitForChange
        case .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate,
             .twoFingerTap, .drawPath, .drawBezier:
            return .gesture
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge,
             .activate,
             .rotor, .typeText, .editAction, .setPasteboard, .waitFor:
            return .elementAction
        case .startRecording, .runBatch, .connect, .archiveSession, .startHeist,
             .stopHeist, .playHeist:
            return .session
        }
    }

    var catalogCLIExposure: CLIExposure {
        switch self {
        case .help, .quit:
            return .sessionOnly
        default:
            return .directCommand
        }
    }

    var catalogMCPExposure: MCPExposure {
        switch self {
        case .help, .quit:
            return .notExposed
        default:
            return .directTool
        }
    }

    var catalogBatchExecutable: Bool {
        switch self {
        case .waitForChange,
             .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate,
             .twoFingerTap, .drawPath, .drawBezier,
             .scroll, .scrollToVisible, .elementSearch, .scrollToEdge,
             .activate,
             .rotor, .typeText, .editAction, .setPasteboard,
             .waitFor, .dismissKeyboard:
            return true
        case .help, .ping, .quit,
             .listDevices, .getInterface, .getScreen, .getPasteboard,
             .getSessionState, .connect, .listTargets,
             .getSessionLog, .archiveSession,
             .startRecording, .stopRecording, .runBatch,
             .startHeist, .stopHeist, .playHeist:
            return false
        }
    }

    var catalogRequiresConnectionBeforeDispatch: Bool {
        switch self {
        case .ping, .getSessionState, .listDevices, .connect, .listTargets,
             .getSessionLog, .archiveSession, .startHeist, .stopHeist:
            return false
        default:
            return true
        }
    }

    var catalogHumanPositionalSyntax: FenceHumanPositionalSyntax {
        switch self {
        case .typeText:
            return .joinedText(.text)
        case .editAction:
            return .firstToken(.action)
        case .scrollToEdge:
            return .leadingEdgeThenTarget(Self.humanScrollEdgeValues)
        case .swipe, .scroll, .rotor:
            return .leadingDirectionThenTarget(Self.humanDirectionValues)
        default:
            return .target
        }
    }

    var catalogMCPAnnotations: MCPToolAnnotationSpec? {
        switch self {
        case .ping,
             .getInterface,
             .getScreen,
             .listDevices,
             .getSessionState,
             .listTargets,
             .getSessionLog:
            return MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)

        case .waitForChange,
             .getPasteboard:
            return MCPToolAnnotationSpec(readOnlyHint: true)

        default:
            return nil
        }
    }

    var catalogRecordsActionCompletion: Bool {
        switch self {
        case .getPasteboard:
            return false
        default:
            return true
        }
    }
}
