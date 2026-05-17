import Foundation

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

public extension TheFence.Command {
    /// Commands that can execute as a run_batch step.
    ///
    /// Shell/session-control conveniences are accepted at external edges but
    /// should not appear in batch schemas or typed batch execution.
    var isBatchExecutable: Bool {
        switch self {
        case .help, .status, .quit, .exit:
            return false
        default:
            return true
        }
    }

    static var batchExecutableCases: [Self] {
        allCases.filter(\.isBatchExecutable)
    }
}
