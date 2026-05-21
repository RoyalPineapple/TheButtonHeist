import Foundation
import TheScore

extension TheFence {

    /// Canonical set of all commands supported by TheFence (CLI and MCP).
    public enum Command: String, CaseIterable, Sendable {
        case help
        case status
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
                description: mcpDescription(for: toolName),
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
            humanAliases: command.catalogHumanAliases,
            cliExposure: command.catalogCLIExposure,
            mcpExposure: command.catalogMCPExposure,
            isBatchExecutable: command.catalogBatchExecutable,
            isPlaybackExecutable: command.catalogPlaybackExecutable,
            isHeistRecordable: command.catalogHeistRecordable,
            requiresConnectionBeforeDispatch: command.catalogRequiresConnectionBeforeDispatch,
            humanPositionalSyntax: command.catalogHumanPositionalSyntax,
            parameters: command.catalogParameters,
            description: mcpDescription(for: command.rawValue)
        )
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
        case .help, .status, .quit, .exit, .runBatch:
            return false
        default:
            return true
        }
    }

    var catalogPlaybackExecutable: Bool {
        switch self {
        case .help, .status, .quit, .exit,
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
        case .getSessionState, .listDevices, .connect, .listTargets,
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
                    ScrollMode.allCases.compactMap { mode in
                        Self(rawValue: mode.canonicalCommand).map { (mode.rawValue, $0) }
                    },
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
        case Self.getInterface.rawValue,
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

    private static func mcpDescription(for toolName: String) -> String {
        mcpObservationDescription(for: toolName) ??
            mcpInteractionDescription(for: toolName) ??
            mcpSessionDescription(for: toolName) ??
            "Execute the \(toolName) Button Heist tool."
    }

    private static func mcpObservationDescription(for toolName: String) -> String? {
        switch toolName {
        case Self.getInterface.rawValue:
            return """
                Read the app accessibility hierarchy. Call once on a new screen, then track changes via \
                action deltas — re-fetch only when you need elements the delta didn't cover. \
                Omit subtree for the whole hierarchy, or pass subtree to select the returned tree from \
                a selected leaf or container node.
                """

        case Self.getScreen.rawValue:
            return """
                Capture a PNG screenshot from the connected device. Returns metadata plus an artifact path \
                by default. Set inlineData=true to return capped base64 PNG data inline; set includeInterface=true \
                to include the fresh visible accessibility tree.
                """

        case Self.waitForChange.rawValue:
            return """
                Wait for the UI to change. With no expect, returns on any tree change. With expect, \
                rides through intermediate states (spinners, loading) until the expectation is met. \
                Use after an action whose delta showed a transient state and the expectation wasn't met yet.
                """

        case Self.waitFor.rawValue:
            return """
                Wait for an element matching a predicate to appear, or to disappear with absent=true. \
                Polls on UI settle events. Returns the matched element or diagnostic info on timeout.
                """

        default:
            return nil
        }
    }

    private static func mcpInteractionDescription(for toolName: String) -> String? {
        switch toolName {
        case Self.activate.rawValue:
            return """
                Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle \
                controls. Pass 'action' to invoke a named action like "increment", "decrement", or \
                any entry from the element's actions array.
                """

        case Self.rotor.rawValue:
            return """
                Move through a rotor exposed by an element. Defaults to next. Use rotors listed by \
                get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous \
                object result to continue like a VoiceOver user. For text-range results, also pass \
                the returned start and end offsets.
                """

        case Self.typeText.rawValue:
            return """
                Type non-empty text via keyboard injection. Optionally target an \
                element to focus it first and read back the resulting value.
                """

        case Self.scroll.rawValue:
            return """
                Scroll within scroll views. mode=page scrolls one page in 'direction'; \
                mode=to_visible brings a known element into view; mode=search scrolls until a \
                matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge.
                """

        case Self.gestureMCPToolName:
            return """
                Perform a touch gesture. Prefer 'activate' for element interactions — gestures are for \
                swipes, drags, pinches, rotates, and free-form path drawing. Set 'type' to one of: \
                swipe, one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier.
                """

        case Self.editAction.rawValue:
            return """
                Perform an edit or keyboard action on the current first responder. \
                Actions: copy, paste, cut, select, selectAll, delete, dismiss (dismiss the keyboard).
                """

        case Self.setPasteboard.rawValue:
            return """
                Write text to the general pasteboard from within the app. Content written by the app \
                itself does not trigger the iOS "Allow Paste" dialog when subsequently read.
                """

        case Self.getPasteboard.rawValue:
            return """
                Read text from the general pasteboard. iOS may show "Allow Paste" if the content \
                was written by another app.
                """

        default:
            return nil
        }
    }

    private static func mcpSessionDescription(for toolName: String) -> String? {
        switch toolName {
        case Self.startRecording.rawValue:
            return "Start an H.264/MP4 screen recording. Recording runs until max duration unless inactivity_timeout is explicitly supplied."

        case Self.stopRecording.rawValue:
            return """
                Stop an in-progress screen recording. Returns artifact path and metadata by default. \
                Set inlineData=true and/or includeInteractionLog=true for a capped expanded JSON response.
                """

        case Self.listDevices.rawValue:
            return """
                List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. \
                Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.
                """

        case Self.getSessionState.rawValue:
            return """
                Inspect the current Button Heist session: connection status, device/app identity, \
                recording state, client timeouts, and a lightweight summary of the last action.
                """

        case Self.connect.rawValue:
            return """
                Establish or switch the active connection to an iOS app with Button Heist enabled. \
                Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or \
                BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. \
                Returns session state; call get_interface explicitly to observe UI hierarchy.
                """

        case Self.listTargets.rawValue:
            return """
                List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), \
                including each target's address and which one is the default.
                """

        case Self.runBatch.rawValue:
            return """
                Execute multiple commands in one call. Each step is a JSON object with 'command' set \
                to a canonical TheFence.Command name plus that command's parameters; grouped MCP tool \
                names and selector shapes are not accepted inside batches. Attach 'expect' per step to verify \
                inline. Returns ordered per-step results. \
                policy=stop_on_error (default) or continue_on_error.
                """

        case Self.getSessionLog.rawValue:
            return "Return the current session log snapshot: commands executed and artifacts produced."

        case Self.archiveSession.rawValue:
            return "Close and compress the current session into a .tar.gz archive; returns the path."

        case Self.startHeist.rawValue:
            return """
                Start recording a heist. Successful commands become steps in a .heist file; \
                the recorder derives minimum matcher fields for durable element targeting; heistId remains recording evidence only. \
                Attach 'expect' to validate outcomes during playback.
                """

        case Self.stopHeist.rawValue:
            return """
                Stop recording and save the heist as a self-contained JSON playback script. \
                Returns the file path and step count. At least one step must have been recorded.
                """

        case Self.playHeist.rawValue:
            return """
                Play back a .heist file. Steps execute sequentially; playback stops on the first \
                failed step. On failure, returns full diagnostics: command, target, error, action \
                result, expectation result, and a complete interface snapshot at the failure point.
                """

        default:
            return nil
        }
    }
}
