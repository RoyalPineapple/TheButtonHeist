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

private struct FenceCommandCatalogEntry {
    var actionResultMethod: ActionMethod?
    var requestPayloadKind: FenceRequestPayloadKind = .none
    var cliExposure: CLIExposure = .directCommand
    var mcpExposure: MCPExposure = .directTool
    var isBatchExecutable = false
    var requiresConnectionBeforeDispatch = true
    var humanPositionalSyntax: FenceHumanPositionalSyntax = .target
    var mcpAnnotations: MCPToolAnnotationSpec?
    var recordsActionCompletion = true
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
            guard case .waitFor(let target)? = request.executableMessages?.first else {
                throw FenceError.invalidRequest("command \"\(canonicalName)\" is missing wait_for payload")
            }
            return target.resolvedTimeout + 5
        }
        if actionResultMethod == .waitForChange {
            guard case .waitForChange(let target)? = request.executableMessages?.first else {
                throw FenceError.invalidRequest("command \"\(canonicalName)\" is missing wait_for_change payload")
            }
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
        allCases.filter { $0.catalogEntry.isBatchExecutable }
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
                description: descriptor.description,
                parameters: descriptor.parameters,
                annotations: descriptor.mcpAnnotations
            )
        }
    }

}

extension TheFence.Command {
    static func descriptor(for command: Self) -> FenceCommandDescriptor {
        let entry = command.catalogEntry
        return FenceCommandDescriptor(
            command: command,
            actionResultMethod: entry.actionResultMethod,
            requestPayloadKind: entry.requestPayloadKind,
            cliExposure: entry.cliExposure,
            mcpExposure: entry.mcpExposure,
            isBatchExecutable: entry.isBatchExecutable,
            requiresConnectionBeforeDispatch: entry.requiresConnectionBeforeDispatch,
            humanPositionalSyntax: entry.humanPositionalSyntax,
            parameters: command.catalogParameters,
            mcpAnnotations: entry.mcpAnnotations,
            recordsActionCompletion: entry.recordsActionCompletion,
            description: presentationDescription(for: command.rawValue)
        )
    }

    private var catalogEntry: FenceCommandCatalogEntry {
        var entry = FenceCommandCatalogEntry()
        switch self {
        case .help:
            entry.cliExposure = .sessionOnly
            entry.mcpExposure = .notExposed
            entry.requiresConnectionBeforeDispatch = false
        case .ping:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
        case .quit:
            entry.cliExposure = .sessionOnly
            entry.mcpExposure = .notExposed
        case .listDevices:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
        case .getInterface:
            entry.requestPayloadKind = .observation
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
        case .getScreen:
            entry.requestPayloadKind = .observation
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
        case .waitForChange:
            entry.actionResultMethod = .waitForChange
            entry.requestPayloadKind = .waitForChange
            entry.isBatchExecutable = true
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true)
        case .oneFingerTap:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
        case .longPress:
            entry.actionResultMethod = .syntheticLongPress
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
        case .swipe:
            entry.actionResultMethod = .syntheticSwipe
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .leadingDirectionThenTarget(Self.humanDirectionValues)
        case .drag:
            entry.actionResultMethod = .syntheticDrag
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
        case .pinch:
            entry.actionResultMethod = .syntheticPinch
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
        case .rotate:
            entry.actionResultMethod = .syntheticRotate
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
        case .twoFingerTap:
            entry.actionResultMethod = .syntheticTwoFingerTap
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
        case .drawPath:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
        case .drawBezier:
            entry.requestPayloadKind = .gesture
            entry.isBatchExecutable = true
        case .scroll:
            entry.actionResultMethod = .scroll
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .leadingDirectionThenTarget(Self.humanDirectionValues)
        case .scrollToVisible:
            entry.actionResultMethod = .scrollToVisible
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
        case .elementSearch:
            entry.actionResultMethod = .elementSearch
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
        case .scrollToEdge:
            entry.actionResultMethod = .scrollToEdge
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .leadingEdgeThenTarget(Self.humanScrollEdgeValues)
        case .activate:
            entry.actionResultMethod = .activate
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
        case .rotor:
            entry.actionResultMethod = .rotor
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .leadingDirectionThenTarget(Self.humanDirectionValues)
        case .typeText:
            entry.actionResultMethod = .typeText
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .joinedText(.text)
        case .editAction:
            entry.actionResultMethod = .editAction
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
            entry.humanPositionalSyntax = .firstToken(.action)
        case .setPasteboard:
            entry.actionResultMethod = .setPasteboard
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
        case .getPasteboard:
            entry.actionResultMethod = .getPasteboard
            entry.recordsActionCompletion = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true)
        case .waitFor:
            entry.actionResultMethod = .waitFor
            entry.requestPayloadKind = .elementAction
            entry.isBatchExecutable = true
        case .dismissKeyboard:
            entry.actionResultMethod = .resignFirstResponder
            entry.isBatchExecutable = true
        case .startRecording:
            entry.requestPayloadKind = .session
        case .stopRecording:
            entry.requestPayloadKind = .observation
        case .runBatch:
            entry.requestPayloadKind = .session
        case .getSessionState:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
        case .connect:
            entry.requestPayloadKind = .session
            entry.requiresConnectionBeforeDispatch = false
        case .listTargets:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
        case .getSessionLog:
            entry.requiresConnectionBeforeDispatch = false
            entry.mcpAnnotations = MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
        case .archiveSession:
            entry.requestPayloadKind = .session
            entry.requiresConnectionBeforeDispatch = false
        case .startHeist:
            entry.requestPayloadKind = .session
            entry.requiresConnectionBeforeDispatch = false
        case .stopHeist:
            entry.requestPayloadKind = .session
            entry.requiresConnectionBeforeDispatch = false
        case .playHeist:
            entry.requestPayloadKind = .session
        }
        return entry
    }
}
