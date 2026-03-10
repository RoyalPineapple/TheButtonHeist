import MCP

enum ToolDefinitions {
    // NOTE: Video data handling
    // The MCP server intentionally omits raw base64 video data from responses.
    // Video payloads can be tens of megabytes which would overwhelm the MCP
    // context window. Instead, video metadata (dimensions, duration, frame count,
    // stop reason, interaction count) is returned as a JSON summary.
    //
    // Agents that need the actual video file should pass the "output" parameter
    // in stop_recording to write to disk and receive only the file path.

    static let all: [Tool] = [
        getInterface, activate, typeText, swipe, getScreen,
        waitForIdle, startRecording, stopRecording, listDevices,
        gesture, accessibilityAction,
        scroll, scrollToVisible, scrollToEdge,
    ]

    // MARK: - Individual Tools

    static let getInterface = Tool(
        name: "get_interface",
        description: """
            Get the current UI element hierarchy from the connected iOS device. Returns a structured list \
            of all accessible elements with their order, label, value, identifier, traits, frame, \
            activation point, and available actions.
            """,
        inputSchema: ["type": "object", "properties": .object([:]), "additionalProperties": false],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let activate = Tool(
        name: "activate",
        description: """
            Activate a UI element. This is the primary way to interact with buttons, links, and controls. \
            Uses the activation-first pattern: tries accessibility activation (like VoiceOver double-tap) first, \
            falls back to synthetic tap at the element's activation point. \
            Provide identifier or order from get_interface.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
            ],
            "additionalProperties": false,
        ]
    )

    static let typeText = Tool(
        name: "type_text",
        description: """
            Type text and/or delete characters via keyboard injection. Optionally target an element \
            to focus it first and read back the resulting value.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "text": ["type": "string", "description": "Text to type character-by-character"],
                "deleteCount": ["type": "integer", "description": "Number of delete key taps before typing"],
                "identifier": ["type": "string", "description": "Element to tap for focus (reads value back)"],
                "order": ["type": "integer", "description": "Element order index to tap for focus"],
            ],
            "additionalProperties": false,
        ]
    )

    static let swipe = Tool(
        name: "swipe",
        description: """
            Swipe on an element or between coordinates. For element-based: provide identifier/order \
            and direction. For coordinate-based: provide startX/startY and endX/endY.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "direction": ["type": "string", "description": "Swipe direction: up, down, left, right"],
                "startX": ["type": "number", "description": "Start X coordinate"],
                "startY": ["type": "number", "description": "Start Y coordinate"],
                "endX": ["type": "number", "description": "End X coordinate"],
                "endY": ["type": "number", "description": "End Y coordinate"],
                "distance": ["type": "number", "description": "Swipe distance in points (for direction-based)"],
                "duration": ["type": "number", "description": "Swipe duration in seconds"],
            ],
            "additionalProperties": false,
        ]
    )

    static let getScreen = Tool(
        name: "get_screen",
        description: "Capture a PNG screenshot from the connected device. Returns inline base64 PNG image data. Use 'output' to save to a file path instead.",
        inputSchema: [
            "type": "object",
            "properties": [
                "output": ["type": "string", "description": "File path to save PNG (omit for inline base64)"],
            ],
            "additionalProperties": false,
        ],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let waitForIdle = Tool(
        name: "wait_for_idle",
        description: "Wait for UI animations to settle before reading state or performing actions.",
        inputSchema: [
            "type": "object",
            "properties": [
                "timeout": ["type": "number", "description": "Maximum wait time in seconds"],
            ],
            "additionalProperties": false,
        ],
        annotations: .init(readOnlyHint: true)
    )

    static let startRecording = Tool(
        name: "start_recording",
        description: "Start an H.264/MP4 screen recording. Recording auto-stops on inactivity or max duration.",
        inputSchema: [
            "type": "object",
            "properties": [
                "fps": ["type": "integer", "description": "Frames per second (default: 8, range: 1-15)"],
                "scale": ["type": "number", "description": "Resolution scale factor (default: 1.0, range: 0.25-1.0)"],
                "maxDuration": ["type": "number", "description": "Maximum recording duration in seconds (default: 60)"],
                "inactivityTimeout": ["type": "number", "description": "Auto-stop after N seconds of no interactions (default: 5)"],
            ],
            "additionalProperties": false,
        ]
    )

    static let stopRecording = Tool(
        name: "stop_recording",
        description: """
            Stop an in-progress screen recording. Video metadata is returned as JSON summary \
            (raw video is too large for MCP context). Use 'output' to save the MP4 to a file path.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "output": ["type": "string", "description": "File path to save MP4 (metadata-only response if omitted)"],
            ],
            "additionalProperties": false,
        ]
    )

    static let listDevices = Tool(
        name: "list_devices",
        description: "List iOS devices discovered via Bonjour that are running TheInsideJob.",
        inputSchema: ["type": "object", "properties": .object([:]), "additionalProperties": false],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    // MARK: - Scroll Tools

    static let scroll = Tool(
        name: "scroll",
        description: """
            Scroll a scroll view by one page in a direction. Targets the nearest scrollable ancestor \
            of the specified element, or the main scroll view if no element is specified.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "direction": [
                    "type": "string",
                    "enum": .array(["up", "down", "left", "right", "next", "previous"].map { .string($0) }),
                    "description": "Scroll direction",
                ],
            ],
            "required": .array([.string("direction")]),
            "additionalProperties": false,
        ]
    )

    static let scrollToVisible = Tool(
        name: "scroll_to_visible",
        description: "Scroll the nearest scroll view ancestor until the target element is fully visible. Provide identifier or order from get_interface.",
        inputSchema: [
            "type": "object",
            "properties": [
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
            ],
            "additionalProperties": false,
        ]
    )

    static let scrollToEdge = Tool(
        name: "scroll_to_edge",
        description: "Scroll the nearest scroll view ancestor to an edge. Useful for scrolling to the top or bottom of a list.",
        inputSchema: [
            "type": "object",
            "properties": [
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "edge": [
                    "type": "string",
                    "enum": .array(["top", "bottom", "left", "right"].map { .string($0) }),
                    "description": "Edge to scroll to",
                ],
            ],
            "required": .array([.string("edge")]),
            "additionalProperties": false,
        ]
    )

    // MARK: - Grouped Tools

    static let gesture = Tool(
        name: "gesture",
        description: """
            Perform low-level touch gestures. For element interactions, prefer 'activate' instead. \
            Set 'type' to one of: one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier. \
            Common params: identifier/order (element target) or x/y (coordinates). \
            one_finger_tap: synthetic tap at coordinates (use 'activate' for element interactions instead). \
            drag: endX, endY required. \
            long_press: duration (seconds, default 1.0). \
            pinch: scale required (>1 zoom in, <1 zoom out). \
            rotate: angle required (radians). \
            draw_path: points array of {x, y} objects. \
            draw_bezier: curves array of bezier curve objects.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "type": [
                    "type": "string",
                    "enum": .array([
                        "one_finger_tap", "drag", "long_press", "pinch",
                        "rotate", "two_finger_tap", "draw_path", "draw_bezier",
                    ].map { .string($0) }),
                    "description": "Gesture type",
                ],
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "x": ["type": "number", "description": "X coordinate"],
                "y": ["type": "number", "description": "Y coordinate"],
                "endX": ["type": "number", "description": "End X coordinate (drag)"],
                "endY": ["type": "number", "description": "End Y coordinate (drag)"],
                "duration": ["type": "number", "description": "Duration in seconds (long_press)"],
                "scale": ["type": "number", "description": "Pinch scale factor (>1 zoom in, <1 zoom out)"],
                "angle": ["type": "number", "description": "Rotation angle in radians"],
                "points": ["type": "array", "description": "Array of {x, y} waypoints (draw_path)"],
                "curves": ["type": "array", "description": "Array of bezier curve objects (draw_bezier)"],
            ],
            "required": .array([.string("type")]),
            "additionalProperties": false,
        ]
    )

    static let accessibilityAction = Tool(
        name: "accessibility_action",
        description: """
            Perform specialized accessibility actions on elements. For general element interaction, use 'activate' instead. \
            Set 'type' to one of: increment, decrement, perform_custom_action, edit_action, dismiss_keyboard. \
            increment/decrement: require identifier or order (for sliders, steppers). \
            perform_custom_action: requires identifier/order and actionName. \
            edit_action: requires action (copy, paste, cut, select, selectAll). \
            dismiss_keyboard: no additional params.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "type": [
                    "type": "string",
                    "enum": .array(["increment", "decrement", "perform_custom_action", "edit_action", "dismiss_keyboard"].map { .string($0) }),
                    "description": "Action type",
                ],
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "actionName": ["type": "string", "description": "Custom action name (for perform_custom_action)"],
                "action": ["type": "string", "description": "Edit action: copy, paste, cut, select, selectAll (for edit_action)"],
            ],
            "required": .array([.string("type")]),
            "additionalProperties": false,
        ]
    )
}
