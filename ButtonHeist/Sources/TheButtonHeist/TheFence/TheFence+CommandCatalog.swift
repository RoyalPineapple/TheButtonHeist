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

public extension TheFence.Command {
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
    static let humanCommandAliases: [String: FenceCommandAlias] = [
        "tap": .init(command: .oneFingerTap),
        "press": .init(command: .longPress),
        "ui": .init(command: .getInterface),
        "screen": .init(command: .getScreen),
        "screenshot": .init(command: .getScreen),
        "idle": .init(command: .waitForChange),
        "change": .init(command: .waitForChange),
        "wait": .init(command: .waitFor),
        "devices": .init(command: .listDevices),
        "list": .init(command: .listDevices),
        "type": .init(command: .typeText),
        "record": .init(command: .startRecording),
        "copy": .init(command: .editAction, parameters: [.action: .string(EditAction.copy.rawValue)]),
        "paste": .init(command: .editAction, parameters: [.action: .string(EditAction.paste.rawValue)]),
        "cut": .init(command: .editAction, parameters: [.action: .string(EditAction.cut.rawValue)]),
        "delete": .init(command: .editAction, parameters: [.action: .string(EditAction.delete.rawValue)]),
        "select": .init(command: .editAction, parameters: [.action: .string(EditAction.select.rawValue)]),
        "select_all": .init(command: .editAction, parameters: [.action: .string(EditAction.selectAll.rawValue)]),
    ]

    static func humanAlias(named name: String) -> FenceCommandAlias? {
        humanCommandAliases[name.lowercased()]
    }

    /// Commands that can execute as a run_batch step.
    ///
    /// Session-control and batch-orchestration commands are accepted at
    /// external edges but should not appear in batch schemas or execution.
    var isBatchExecutable: Bool {
        switch self {
        case .help, .status, .quit, .exit, .runBatch:
            return false
        default:
            return true
        }
    }

    static var batchExecutableCases: [Self] {
        allCases.filter(\.isBatchExecutable)
    }
}
