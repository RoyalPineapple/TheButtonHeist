import Foundation

/// Canonical version string shared by CLI, MCP, and any other clients.
/// Update this constant when cutting a new release. See docs/VERSIONING.md.
public let buttonHeistVersion = "0.0.1"

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
        case waitForIdle = "wait_for_idle"
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
        case scrollToEdge = "scroll_to_edge"
        case activate
        case increment
        case decrement
        case performCustomAction = "perform_custom_action"
        case typeText = "type_text"
        case editAction = "edit_action"
        case dismissKeyboard = "dismiss_keyboard"
        case startRecording = "start_recording"
        case stopRecording = "stop_recording"
    }
}
