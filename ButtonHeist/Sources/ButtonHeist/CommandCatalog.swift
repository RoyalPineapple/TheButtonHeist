/// Canonical version string shared by CLI, MCP, and any other clients.
/// Update this constant when cutting a new release.
public let buttonHeistVersion = "2.1.0"

public enum CommandCatalog {
    public static let all: [String] = [
        "help",
        "status",
        "quit",
        "exit",
        "list_devices",
        "get_interface",
        "get_screen",
        "wait_for_idle",
        "tap",
        "long_press",
        "swipe",
        "drag",
        "pinch",
        "rotate",
        "two_finger_tap",
        "draw_path",
        "draw_bezier",
        "activate",
        "increment",
        "decrement",
        "perform_custom_action",
        "type_text",
        "edit_action",
        "dismiss_keyboard",
        "start_recording",
        "stop_recording",
    ]
}
