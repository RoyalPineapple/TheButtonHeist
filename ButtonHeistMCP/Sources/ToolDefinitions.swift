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

    // Shared expect property for action tools — matches the batch step schema
    static let expectProperty: Value = [
        "description": """
            Outcome signal for this action. Delivery is always checked implicitly. \
            String values: "screen_changed" (did the view controller change?), \
            "layout_changed" (were elements added or removed? does not match value-only changes). \
            Object value: {"value": "expected"} to check the post-action field value.
            """,
        "oneOf": .array([
            [
                "type": "string",
                "enum": .array(["screen_changed", "layout_changed"].map { .string($0) }),
            ],
            [
                "type": "object",
                "properties": ["value": ["type": "string"]],
                "required": .array([.string("value")]),
                "additionalProperties": false,
            ],
        ]),
    ]

    static let all: [Tool] = [
        getInterface, activate, typeText, swipe, getScreen,
        waitForIdle, startRecording, stopRecording, listDevices,
        gesture, accessibilityAction, setPasteboard, getPasteboard,
        scroll, scrollToVisible, scrollToEdge,
        runBatch, getSessionState,
    ]

    // MARK: - Individual Tools

    static let getInterface = Tool(
        name: "get_interface",
        description: """
            Get the current UI element hierarchy from the connected iOS device. Returns elements with \
            heistId, label, value, traits, and actions. Use detail=full for geometry (frame, activation point). \
            Target elements in subsequent calls using heistId.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "detail": [
                    "type": "string",
                    "enum": .array(["summary", "full"].map { .string($0) }),
                    "description": "Level of detail: summary (default, no geometry) or full (includes frame, activation point, hints)",
                ],
            ],
            "additionalProperties": false,
        ],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let activate = Tool(
        name: "activate",
        description: """
            Activate a UI element. This is the primary way to interact with buttons, links, and controls. \
            Uses the activation-first pattern: tries accessibility activation (like VoiceOver double-tap) first, \
            falls back to synthetic tap at the element's activation point. \
            Target by heistId (preferred), identifier, or order from get_interface.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "heistId": ["type": "string", "description": "Target element by stable heistId (preferred)"],
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "expect": expectProperty,
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
                "clearFirst": ["type": "boolean", "description": "Clear all existing text before typing (select-all + delete)"],
                "identifier": ["type": "string", "description": "Element to tap for focus (reads value back)"],
                "order": ["type": "integer", "description": "Element order index to tap for focus"],
                "expect": expectProperty,
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
                "heistId": ["type": "string", "description": "Target element by stable heistId (preferred)"],
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "direction": ["type": "string", "description": "Swipe direction: up, down, left, right"],
                "startX": ["type": "number", "description": "Start X coordinate"],
                "startY": ["type": "number", "description": "Start Y coordinate"],
                "endX": ["type": "number", "description": "End X coordinate"],
                "endY": ["type": "number", "description": "End Y coordinate"],
                "distance": ["type": "number", "description": "Swipe distance in points (for direction-based)"],
                "duration": ["type": "number", "description": "Swipe duration in seconds"],
                "expect": expectProperty,
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
                "heistId": ["type": "string", "description": "Target element by stable heistId (preferred)"],
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "direction": [
                    "type": "string",
                    "enum": .array(["up", "down", "left", "right", "next", "previous"].map { .string($0) }),
                    "description": "Scroll direction",
                ],
                "expect": expectProperty,
            ],
            "required": .array([.string("direction")]),
            "additionalProperties": false,
        ]
    )

    static let scrollToVisible = Tool(
        name: "scroll_to_visible",
        description: """
            Scroll the nearest scroll view ancestor until the target element is fully visible. \
            Target by heistId (preferred), identifier, or order from get_interface.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "heistId": ["type": "string", "description": "Target element by stable heistId (preferred)"],
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "expect": expectProperty,
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
                "heistId": ["type": "string", "description": "Target element by stable heistId (preferred)"],
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "edge": [
                    "type": "string",
                    "enum": .array(["top", "bottom", "left", "right"].map { .string($0) }),
                    "description": "Edge to scroll to",
                ],
                "expect": expectProperty,
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
            draw_bezier: startX, startY required; segments array of {cp1X, cp1Y, cp2X, cp2Y, endX, endY}.
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
                "heistId": ["type": "string", "description": "Target element by stable heistId (preferred)"],
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "x": ["type": "number", "description": "X coordinate"],
                "y": ["type": "number", "description": "Y coordinate"],
                "startX": ["type": "number", "description": "Start X coordinate (draw_bezier)"],
                "startY": ["type": "number", "description": "Start Y coordinate (draw_bezier)"],
                "endX": ["type": "number", "description": "End X coordinate (drag)"],
                "endY": ["type": "number", "description": "End Y coordinate (drag)"],
                "duration": ["type": "number", "description": "Duration in seconds (long_press, draw_path, draw_bezier)"],
                "scale": ["type": "number", "description": "Pinch scale factor (>1 zoom in, <1 zoom out)"],
                "angle": ["type": "number", "description": "Rotation angle in radians"],
                "points": ["type": "array", "description": "Array of {x, y} waypoints (draw_path)"],
                "segments": ["type": "array", "description": "Array of bezier segments: {cp1X, cp1Y, cp2X, cp2Y, endX, endY} (draw_bezier)"],
                "expect": expectProperty,
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
            Target by heistId (preferred), identifier, or order from get_interface. \
            increment/decrement: for sliders, steppers. \
            perform_custom_action: requires actionName. \
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
                "heistId": ["type": "string", "description": "Target element by stable heistId (preferred)"],
                "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
                "order": ["type": "integer", "description": "Target element by traversal order index"],
                "actionName": ["type": "string", "description": "Custom action name (for perform_custom_action)"],
                "action": ["type": "string", "description": "Edit action: copy, paste, cut, select, selectAll (for edit_action)"],
                "expect": expectProperty,
            ],
            "required": .array([.string("type")]),
            "additionalProperties": false,
        ]
    )

    static let setPasteboard = Tool(
        name: "set_pasteboard",
        description: """
            Write text to the general pasteboard from within the app. Content written by the app \
            itself does not trigger the iOS "Allow Paste" dialog when subsequently read. \
            Use this for automation workflows that need clipboard content without system prompts.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "text": ["type": "string", "description": "Text to write to the pasteboard"],
                "expect": expectProperty,
            ],
            "required": .array([.string("text")]),
            "additionalProperties": false,
        ]
    )

    static let getPasteboard = Tool(
        name: "get_pasteboard",
        description: """
            Read text from the general pasteboard. If the content was written by another app, \
            iOS may show an "Allow Paste" system dialog.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "expect": expectProperty,
            ],
            "additionalProperties": false,
        ],
        annotations: .init(readOnlyHint: true)
    )

    static let runBatch = Tool(
        name: "run_batch",
        description: """
            Execute a batch of Button Heist commands in a single MCP call. \
            Each step is a JSON request matching the CLI session format (must include 'command'). \
            Every action implicitly checks delivery (success==true). \
            Steps can include an 'expect' field to classify the expected outcome: \
            "screen_changed", "layout_changed", or {"value": "expected text"}. \
            Results report what actually happened — the caller decides what to do with it. \
            The policy controls whether the batch stops on first error or unmet expectation.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "steps": [
                    "type": "array",
                    "description": "Ordered list of Button Heist requests to execute",
                    "items": [
                        "type": "object",
                        "properties": [
                            "command": ["type": "string", "description": "Fence command (e.g., activate, type_text, scroll)"],
                            "expect": expectProperty,
                        ],
                        "required": .array([.string("command")]),
                        "additionalProperties": true,
                    ],
                ],
                "policy": [
                    "type": "string",
                    "enum": .array(["stop_on_error", "continue_on_error"].map { .string($0) }),
                    "description": "Batch policy: stop_on_error (default) or continue_on_error",
                ],
            ],
            "required": .array([.string("steps")]),
            "additionalProperties": false,
        ]
    )

    static let getSessionState = Tool(
        name: "get_session_state",
        description: """
            Inspect the current Button Heist session state without performing any actions. \
            Returns connection status, active device/app identity, recording state, client timeouts, \
            and a lightweight summary of the last action (if any).
            """,
        inputSchema: [
            "type": "object",
            "properties": .object([:]),
            "additionalProperties": false,
        ],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )
}
