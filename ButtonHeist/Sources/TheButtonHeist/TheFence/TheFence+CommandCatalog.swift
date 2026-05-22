import Foundation
import TheScore

extension TheFence {

    /// Canonical set of all commands supported by TheFence (CLI and MCP).
    public enum Command: String, CaseIterable, Sendable {
        case help
        case status
        case ping
        case quit
        case exit
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
        case increment
        case decrement
        case performCustomAction = "perform_custom_action"
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

/// Canonical expansion for a user-facing command alias.
///
/// Aliases are part of the external command contract: adapters may parse and
/// transport them, but the command identity and default parameters live here.
public struct FenceCommandAlias: Sendable, Equatable {
    public let command: TheFence.Command
    public let parameters: [FenceParameterKey: HeistValue]

    public init(
        command: TheFence.Command,
        parameters: [FenceParameterKey: HeistValue] = [:]
    ) {
        self.command = command
        self.parameters = parameters
    }
}

/// Canonical command descriptor for TheFence command surfaces.
///
/// The enum is the stable wire identity. This descriptor owns the contract
/// projected from that identity: aliases, adapter exposure, batch eligibility,
/// parameter shape, and user-facing help text.
public struct FenceCommandDescriptor: Sendable, Equatable {
    public let command: TheFence.Command
    public let canonicalName: String
    /// The server action method that unambiguously projects back to this public command.
    public let actionResultMethod: ActionMethod?
    public let humanAliases: [String: FenceCommandAlias]
    public let cliName: String?
    public let cliExposure: CLIExposure
    public let mcpExposure: MCPExposure
    public let isBatchExecutable: Bool
    public let isPlaybackExecutable: Bool
    public let isHeistRecordable: Bool
    public let requiresConnectionBeforeDispatch: Bool
    public let humanPositionalSyntax: FenceHumanPositionalSyntax
    public let parameters: [FenceParameterSpec]
    public let description: String

    public init(
        command: TheFence.Command,
        actionResultMethod: ActionMethod? = nil,
        humanAliases: [String: FenceCommandAlias] = [:],
        cliName: String? = nil,
        cliExposure: CLIExposure,
        mcpExposure: MCPExposure,
        isBatchExecutable: Bool,
        isPlaybackExecutable: Bool? = nil,
        isHeistRecordable: Bool? = nil,
        requiresConnectionBeforeDispatch: Bool = true,
        humanPositionalSyntax: FenceHumanPositionalSyntax = .target,
        parameters: [FenceParameterSpec],
        description: String
    ) {
        self.command = command
        self.canonicalName = command.rawValue
        self.actionResultMethod = actionResultMethod
        self.humanAliases = humanAliases
        self.cliName = cliName ?? Self.defaultCLIName(for: command, exposure: cliExposure)
        self.cliExposure = cliExposure
        self.mcpExposure = mcpExposure
        self.isBatchExecutable = isBatchExecutable
        let resolvedPlaybackExecutable = isPlaybackExecutable ?? isBatchExecutable
        self.isPlaybackExecutable = resolvedPlaybackExecutable
        self.isHeistRecordable = isHeistRecordable ?? resolvedPlaybackExecutable
        self.requiresConnectionBeforeDispatch = requiresConnectionBeforeDispatch
        self.humanPositionalSyntax = humanPositionalSyntax
        self.parameters = parameters
        self.description = description
    }

    private static func defaultCLIName(
        for command: TheFence.Command,
        exposure: CLIExposure
    ) -> String? {
        switch exposure {
        case .directCommand, .sessionOnly:
            return command.rawValue
        case .groupedUnder(let name):
            return name
        case .notExposed:
            return nil
        }
    }
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

public extension TheFence.Command {
    static let gestureMCPToolName = "gesture"

    static func command(for gestureType: GestureType) -> Self {
        switch gestureType {
        case .oneFingerTap:
            return .oneFingerTap
        case .longPress:
            return .longPress
        case .swipe:
            return .swipe
        case .drag:
            return .drag
        case .pinch:
            return .pinch
        case .rotate:
            return .rotate
        case .twoFingerTap:
            return .twoFingerTap
        case .drawPath:
            return .drawPath
        case .drawBezier:
            return .drawBezier
        }
    }

    var descriptor: FenceCommandDescriptor {
        Self.descriptor(for: self)
    }

    static func descriptor(forActionResultMethod method: ActionMethod) -> FenceCommandDescriptor? {
        descriptors.first { $0.actionResultMethod == method }
    }

    static func canonicalName(forActionResultMethod method: ActionMethod) -> String {
        descriptor(forActionResultMethod: method)?.canonicalName ?? method.rawValue
    }

    static var descriptors: [FenceCommandDescriptor] {
        allCases.map(descriptor(for:))
    }

    var canonicalName: String {
        descriptor.canonicalName
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

    static func activationAlias(forActionName actionName: String?) -> FenceCommandAlias {
        switch actionName.flatMap({ TheFence.Command(rawValue: $0.lowercased()) }) {
        case .increment:
            return FenceCommandAlias(command: .increment)
        case .decrement:
            return FenceCommandAlias(command: .decrement)
        default:
            if let actionName {
                return FenceCommandAlias(
                    command: .performCustomAction,
                    parameters: [.action: .string(actionName)]
                )
            }
            return FenceCommandAlias(command: .activate)
        }
    }

    /// Human-friendly command aliases accepted by the CLI session parser.
    static var humanCommandAliases: [String: FenceCommandAlias] {
        Dictionary(
            descriptors.flatMap { descriptor in
                descriptor.humanAliases.map { ($0.key, $0.value) }
            },
            uniquingKeysWith: { _, newest in newest }
        )
    }

    static func humanAlias(named name: String) -> FenceCommandAlias? {
        humanCommandAliases[name.lowercased()]
    }

    var humanPositionalSyntax: FenceHumanPositionalSyntax {
        descriptor.humanPositionalSyntax
    }

    static let humanDirectionValues: Set<String> = [
        "up", "down", "left", "right", "next", "previous",
    ]

    static let humanScrollEdgeValues: Set<String> = [
        "top", "bottom", "left", "right",
    ]

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
        allCases.filter(\.catalogPlaybackExecutable)
    }

    static func command(for scrollMode: ScrollMode) -> Self {
        switch scrollMode {
        case .page:
            return .scroll
        case .toVisible:
            return .scrollToVisible
        case .search:
            return .elementSearch
        case .toEdge:
            return .scrollToEdge
        }
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
        var toolNames: [String] = []
        var commandsByToolName: [String: [Self]] = [:]

        func append(_ command: Self, to toolName: String) {
            if commandsByToolName[toolName] == nil {
                toolNames.append(toolName)
                commandsByToolName[toolName] = []
            }
            commandsByToolName[toolName]?.append(command)
        }

        for descriptor in descriptors {
            switch descriptor.mcpExposure {
            case .directTool:
                append(descriptor.command, to: descriptor.canonicalName)
            case .groupedUnder(let toolName):
                append(descriptor.command, to: toolName)
            case .notExposed:
                break
            }
        }

        return toolNames.compactMap { toolName in
            guard let commands = commandsByToolName[toolName] else { return nil }
            return MCPToolContract(
                name: toolName,
                commands: commands,
                selector: mcpSelector(for: toolName),
                description: presentationDescription(for: toolName),
                annotations: mcpAnnotations(for: toolName)
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
            humanAliases: command.catalogHumanAliases,
            cliExposure: command.catalogCLIExposure,
            mcpExposure: command.catalogMCPExposure,
            isBatchExecutable: command.catalogBatchExecutable,
            isPlaybackExecutable: command.catalogPlaybackExecutable,
            isHeistRecordable: command.catalogHeistRecordable,
            requiresConnectionBeforeDispatch: command.catalogRequiresConnectionBeforeDispatch,
            humanPositionalSyntax: command.catalogHumanPositionalSyntax,
            parameters: command.catalogParameters,
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
        case .increment:
            return .increment
        case .decrement:
            return .decrement
        case .performCustomAction:
            return .customAction
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
        case .help, .status, .ping, .quit, .exit,
             .listDevices, .getInterface, .getScreen,
             .startRecording, .stopRecording, .runBatch,
             .getSessionState, .connect, .listTargets,
             .getSessionLog, .archiveSession,
             .startHeist, .stopHeist, .playHeist:
            return nil
        }
    }

    var catalogCLIExposure: CLIExposure {
        switch self {
        case .help, .quit, .exit, .status:
            return .sessionOnly

        case .increment, .decrement, .performCustomAction:
            return .groupedUnder(Self.activate.rawValue)

        default:
            return .directCommand
        }
    }

    var catalogMCPExposure: MCPExposure {
        switch self {
        case .help, .quit, .exit, .status:
            return .notExposed

        case .increment, .decrement, .performCustomAction:
            return .notExposed

        case .dismissKeyboard:
            return .groupedUnder(Self.editAction.rawValue)

        case .swipe, .oneFingerTap, .longPress, .drag, .pinch, .rotate, .twoFingerTap,
             .drawPath, .drawBezier:
            return .groupedUnder(Self.gestureMCPToolName)

        case .scrollToVisible, .elementSearch, .scrollToEdge:
            return .groupedUnder(Self.scroll.rawValue)

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
             .activate, .increment, .decrement, .performCustomAction,
             .rotor, .typeText, .editAction, .setPasteboard,
             .waitFor, .dismissKeyboard:
            return true
        case .help, .status, .ping, .quit, .exit,
             .listDevices, .getInterface, .getScreen, .getPasteboard,
             .getSessionState, .connect, .listTargets,
             .getSessionLog, .archiveSession,
             .startRecording, .stopRecording, .runBatch,
             .startHeist, .stopHeist, .playHeist:
            return false
        }
    }

    var catalogPlaybackExecutable: Bool {
        switch self {
        case .help, .status, .ping, .quit, .exit,
             .listDevices, .getInterface, .getScreen, .getPasteboard,
             .getSessionState, .connect, .listTargets,
             .getSessionLog, .archiveSession,
             .startRecording, .stopRecording, .runBatch,
             .startHeist, .stopHeist, .playHeist:
            return false
        default:
            return catalogBatchExecutable
        }
    }

    var catalogHeistRecordable: Bool {
        catalogPlaybackExecutable
    }

    var catalogRequiresConnectionBeforeDispatch: Bool {
        switch self {
        case .status, .ping, .getSessionState, .listDevices, .connect, .listTargets,
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
        case .performCustomAction:
            return .targetThenJoinedText(.action)
        case .swipe, .scroll, .rotor:
            return .leadingDirectionThenTarget(Self.humanDirectionValues)
        default:
            return .target
        }
    }

    var catalogHumanAliases: [String: FenceCommandAlias] {
        switch self {
        case .oneFingerTap:
            return ["tap": .init(command: self)]
        case .longPress:
            return ["press": .init(command: self)]
        case .getInterface:
            return ["ui": .init(command: self)]
        case .getScreen:
            return [
                "screen": .init(command: self),
                "screenshot": .init(command: self),
            ]
        case .waitForChange:
            return [
                "idle": .init(command: self),
                "change": .init(command: self),
            ]
        case .waitFor:
            return ["wait": .init(command: self)]
        case .listDevices:
            return [
                "devices": .init(command: self),
                "list": .init(command: self),
            ]
        case .typeText:
            return ["type": .init(command: self)]
        case .startRecording:
            return ["record": .init(command: self)]
        case .editAction:
            return [
                "copy": .init(command: self, parameters: [.action: .string(EditAction.copy.rawValue)]),
                "paste": .init(command: self, parameters: [.action: .string(EditAction.paste.rawValue)]),
                "cut": .init(command: self, parameters: [.action: .string(EditAction.cut.rawValue)]),
                "delete": .init(command: self, parameters: [.action: .string(EditAction.delete.rawValue)]),
                "select": .init(command: self, parameters: [.action: .string(EditAction.select.rawValue)]),
                "select_all": .init(command: self, parameters: [.action: .string(EditAction.selectAll.rawValue)]),
            ]
        default:
            return [:]
        }
    }

    private static func mcpSelector(for toolName: String) -> MCPToolSelector? {
        switch toolName {
        case Self.gestureMCPToolName:
            return MCPToolSelector(
                parameter: .init(
                    key: "type", type: .string, required: true,
                    description: "Gesture type",
                    enumValues: fenceEnumValues(GestureType.self)
                ),
                commandByValue: Dictionary(
                    GestureType.allCases.compactMap { gestureType in
                        Self(rawValue: gestureType.rawValue).map { (gestureType.rawValue, $0) }
                    },
                    uniquingKeysWith: { _, newest in newest }
                )
            )

        case Self.scroll.rawValue:
            return MCPToolSelector(
                parameter: .init(
                    key: "mode", type: .string, optionalRole: .behaviorSwitch,
                    description: "Scroll mode (default: page)",
                    enumValues: fenceEnumValues(ScrollMode.self)
                ),
                defaultValue: ScrollMode.page.rawValue,
                commandByValue: Dictionary(
                    ScrollMode.allCases.map { mode in (mode.rawValue, Self.command(for: mode)) },
                    uniquingKeysWith: { _, newest in newest }
                )
            )

        case Self.editAction.rawValue:
            let dismissValue = "dismiss"
            return MCPToolSelector(
                parameter: .init(
                    key: "action", type: .string, required: true,
                    description: "Action to perform",
                    enumValues: fenceEnumValues(EditAction.self) + [dismissValue]
                ),
                commandByValue: Dictionary(
                    EditAction.allCases.map { ($0.rawValue, Self.editAction) } +
                        [(dismissValue, Self.dismissKeyboard)],
                    uniquingKeysWith: { _, newest in newest }
                ),
                consumedValues: [dismissValue]
            )

        default:
            return nil
        }
    }

    private static func mcpAnnotations(for toolName: String) -> MCPToolAnnotationSpec? {
        switch toolName {
        case Self.ping.rawValue,
             Self.getInterface.rawValue,
             Self.getScreen.rawValue,
             Self.listDevices.rawValue,
             Self.getSessionState.rawValue,
             Self.listTargets.rawValue,
             Self.getSessionLog.rawValue:
            return MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)

        case Self.waitForChange.rawValue,
             Self.getPasteboard.rawValue:
            return MCPToolAnnotationSpec(readOnlyHint: true)

        default:
            return nil
        }
    }
}
