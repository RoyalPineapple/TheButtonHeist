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

    // Shared element targeting properties — 6-property block used by action/scroll/gesture tools
    static let elementTargetProperties: [String: Value] = [
        "heistId": ["type": "string", "description": "Target element by stable heistId (preferred)"],
        "identifier": ["type": "string", "description": "Target element by accessibility identifier"],
        "label": ["type": "string", "description": "Target by accessibility label (first match)"],
        "value": ["type": "string", "description": "Target by accessibility value (first match)"],
        "traits": ["type": "array", "items": ["type": "string"], "description": "Target: all listed traits must be present"],
        "excludeTraits": ["type": "array", "items": ["type": "string"], "description": "Target: none of these traits may be present"],
    ]

    // Shared element filter properties — 5-property block used by get_interface (no heistId, uses "Filter" descriptions)
    static let elementFilterProperties: [String: Value] = [
        "label": ["type": "string", "description": "Filter by accessibility label (first match)"],
        "identifier": ["type": "string", "description": "Filter by accessibility identifier (first match)"],
        "value": ["type": "string", "description": "Filter by accessibility value (first match)"],
        "traits": ["type": "array", "items": ["type": "string"], "description": "Filter: all listed traits must be present"],
        "excludeTraits": ["type": "array", "items": ["type": "string"], "description": "Filter: none of these traits may be present"],
    ]

    // Shared expect property for action tools — matches the batch step schema
    static let expectProperty: Value = [
        "description": """
            Outcome signal for this action. Delivery is always checked implicitly. \
            String values: "screen_changed" (did the view controller change?), \
            "elements_changed" (were elements added, removed, or updated?). \
            Object value: {"elementUpdated": {"heistId": "slider", "property": "value", "newValue": "5"}} \
            to check specific property changes on elements. \
            elementUpdated follows "say what you know" — provide only the fields you care about \
            (heistId, property, oldValue, newValue). Omitted fields are wildcards.
            """,
        "oneOf": .array([
            [
                "type": "string",
                "enum": .array(["screen_changed", "elements_changed"].map { .string($0) }),
            ],
            [
                "type": "object",
                "properties": [
                    "elementUpdated": [
                        "type": "object",
                        "properties": [
                            "heistId": ["type": "string", "description": "Match a specific element"],
                            "property": [
                                "type": "string",
                                "description": "Match a specific property (label, value, traits, hint, actions, frame, activationPoint)",
                                "enum": .array(["label", "value", "traits", "hint", "actions", "frame", "activationPoint"].map { .string($0) }),
                            ],
                            "oldValue": ["type": "string", "description": "Expected previous value"],
                            "newValue": ["type": "string", "description": "Expected new value"],
                        ],
                        "additionalProperties": false,
                    ],
                ],
                "required": .array([.string("elementUpdated")]),
                "additionalProperties": false,
            ],
        ]),
    ]

    static let all: [Tool] = [
        getInterface, activate, typeText, swipe, getScreen,
        waitForIdle, waitFor, startRecording, stopRecording, listDevices,
        gesture, editAction, dismissKeyboard, setPasteboard, getPasteboard,
        scroll, scrollToVisible, scrollToEdge,
        runBatch, getSessionState,
        connect, listTargets,
    ]

    // MARK: - Individual Tools

    static let getInterface = Tool(
        name: "get_interface",
        description: """
            Get the current UI element hierarchy from the connected iOS device. Returns elements with \
            heistId, label, value, traits, and actions. Use detail=full for geometry (frame, activation point). \
            Target elements in subsequent calls using heistId. \
            Filter with matcher fields (label, traits, excludeTraits, etc.) or a heistId list.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(([
                "detail": [
                    "type": "string",
                    "enum": .array(["summary", "full"].map { .string($0) }),
                    "description": "Level of detail: summary (default, no geometry) or full (includes frame, activation point, hints)",
                ],
                "elements": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional list of heistIds to filter. Returns only matching elements. Omit for full tree.",
                ],
            ] as [String: Value]).merging(elementFilterProperties) { _, new in new }),
            "additionalProperties": false,
        ]),
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let activate = Tool(
        name: "activate",
        description: """
            Activate a UI element. This is the primary way to interact with buttons, links, and controls. \
            Uses the activation-first pattern: tries accessibility activation (like VoiceOver double-tap) first, \
            falls back to synthetic tap at the element's activation point. \
            Target by heistId (preferred), or by matcher fields (label, traits, identifier, etc.). \
            Matcher fields return the first match — add more fields to narrow if needed. \
            Pass 'action' to perform a named action instead: "increment", "decrement", or any custom action from the element's actions array.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "action": ["type": "string", "description": "Named action (e.g. \"increment\", \"decrement\", or a custom action name)"],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "additionalProperties": false,
        ])
    )

    static let typeText = Tool(
        name: "type_text",
        description: """
            Type text and/or delete characters via keyboard injection. Optionally target an element \
            to focus it first and read back the resulting value. \
            Target by heistId (preferred), matcher fields (label, traits), or identifier.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "text": ["type": "string", "description": "Text to type character-by-character"],
                "deleteCount": ["type": "integer", "description": "Number of delete key taps before typing"],
                "clearFirst": ["type": "boolean", "description": "Clear all existing text before typing (select-all + delete)"],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "additionalProperties": false,
        ])
    )

    static let swipe = Tool(
        name: "swipe",
        description: """
            Swipe on an element. Use direction for cardinal swipes (up/down/left/right) or \
            start/end unit points (0-1 relative to element frame) for precise control. \
            Unit points are device-independent: (0,0) is top-left, (1,1) is bottom-right, \
            values outside 0-1 extend beyond the element frame.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "direction": [
                    "type": "string",
                    "description": "Swipe direction: up, down, left, right",
                ],
                "start": [
                    "type": "object",
                    "description": "Start unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    "properties": [
                        "x": ["type": "number", "description": "X position (0-1, values outside extend beyond frame)"],
                        "y": ["type": "number", "description": "Y position (0-1, values outside extend beyond frame)"],
                    ],
                    "required": .array([.string("x"), .string("y")]),
                ],
                "end": [
                    "type": "object",
                    "description": "End unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    "properties": [
                        "x": ["type": "number", "description": "X position (0-1, values outside extend beyond frame)"],
                        "y": ["type": "number", "description": "Y position (0-1, values outside extend beyond frame)"],
                    ],
                    "required": .array([.string("x"), .string("y")]),
                ],
                "duration": ["type": "number", "description": "Swipe duration in seconds"],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "additionalProperties": false,
        ])
    )

    static let waitFor = Tool(
        name: "wait_for",
        description: """
            Wait for an element matching a predicate to appear (or disappear). \
            Polls the accessibility tree on UI settle events — no busy-waiting. \
            Returns the matched element on success, or diagnostic info on timeout. \
            Use 'absent: true' to wait for an element to disappear.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "absent": ["type": "boolean", "description": "Wait for element to NOT exist (default: false)"],
                "timeout": ["type": "number", "description": "Max seconds to wait (default: 10, max: 30)"],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "additionalProperties": false,
        ])
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
                "max_duration": ["type": "number", "description": "Maximum recording duration in seconds (default: 60)"],
                "inactivity_timeout": ["type": "number", "description": "Auto-stop after N seconds of no interactions (default: 5)"],
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
            of the specified element, or the main scroll view if no element is specified. \
            Use scrollViewHeistId to target a specific scroll view (e.g., an outer scroll view in nested layouts).
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "direction": [
                    "type": "string",
                    "enum": .array(["up", "down", "left", "right", "next", "previous"].map { .string($0) }),
                    "description": "Scroll direction",
                ],
                "scrollViewHeistId": ["type": "string", "description": "Explicit scroll view heistId to target (overrides automatic ancestor discovery)"],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "required": .array([.string("direction")]),
            "additionalProperties": false,
        ])
    )

    static let scrollToVisible = Tool(
        name: "scroll_to_visible",
        description: """
            Search for an element by scrolling through scroll views. Target the element \
            by heistId or describe it by accessibility properties: identifier, label, value, and/or traits. \
            All specified matcher fields must match (AND). Returns the found element or diagnostic info about the search. \
            For UITableView/UICollectionView, provides exhaustive search with item count tracking. \
            Supports nested scroll views: tries innermost first, falls back to outer ones on stagnation.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "maxScrolls": ["type": "integer", "description": "Maximum scroll attempts (default: 50)"],
                "direction": ["type": "string", "enum": ["down", "up", "left", "right"], "description": "Starting scroll direction (default: down)"],
                "scrollViewHeistId": ["type": "string", "description": "Explicit scroll view heistId to target (overrides automatic discovery)"],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "additionalProperties": false,
        ])
    )

    static let scrollToEdge = Tool(
        name: "scroll_to_edge",
        description: """
            Scroll the nearest scroll view ancestor to an edge. Useful for scrolling to the top or bottom of a list. \
            Use scrollViewHeistId to target a specific scroll view in nested layouts.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "edge": [
                    "type": "string",
                    "enum": .array(["top", "bottom", "left", "right"].map { .string($0) }),
                    "description": "Edge to scroll to",
                ],
                "scrollViewHeistId": ["type": "string", "description": "Explicit scroll view heistId to target (overrides automatic ancestor discovery)"],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "required": .array([.string("edge")]),
            "additionalProperties": false,
        ])
    )

    // MARK: - Grouped Tools

    static let gesture = Tool(
        name: "gesture",
        description: """
            Perform low-level touch gestures. For element interactions, prefer 'activate' instead. \
            Set 'type' to one of: one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier. \
            Common params: heistId or matcher fields (element target) or x/y (coordinates). \
            one_finger_tap: synthetic tap at coordinates (use 'activate' for element interactions instead). \
            drag: endX, endY required. \
            long_press: duration (seconds, default 1.0). \
            pinch: scale required (>1 zoom in, <1 zoom out). \
            rotate: angle required (radians). \
            draw_path: points array of {x, y} objects. \
            draw_bezier: startX, startY required; segments array of {cp1X, cp1Y, cp2X, cp2Y, endX, endY}.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "type": [
                    "type": "string",
                    "enum": .array([
                        "one_finger_tap", "drag", "long_press", "pinch",
                        "rotate", "two_finger_tap", "draw_path", "draw_bezier",
                    ].map { .string($0) }),
                    "description": "Gesture type",
                ],
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
            ] as [String: Value]) { _, new in new }),
            "required": .array([.string("type")]),
            "additionalProperties": false,
        ])
    )

    static let editAction = Tool(
        name: "edit_action",
        description: """
            Perform an edit menu action (copy, paste, cut, select, selectAll) on the current first responder.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": .array(["copy", "paste", "cut", "select", "selectAll"].map { .string($0) }),
                    "description": "Edit action to perform",
                ],
                "expect": expectProperty,
            ],
            "required": .array([.string("action")]),
            "additionalProperties": false,
        ]
    )

    static let dismissKeyboard = Tool(
        name: "dismiss_keyboard",
        description: "Dismiss the software keyboard by resigning first responder.",
        inputSchema: [
            "type": "object",
            "properties": [
                "expect": expectProperty,
            ],
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
            "screen_changed", "elements_changed", or {"elementUpdated": {"heistId": "...", "newValue": "..."}}. \
            Results report what actually happened — the caller decides what to do with it. \
            The policy controls whether the batch stops on first error or unmet expectation. \
            Valid commands: activate (with optional 'action' for custom actions), increment, decrement, \
            perform_custom_action, type_text, scroll, scroll_to_visible, scroll_to_edge, swipe, \
            one_finger_tap, long_press, drag, pinch, rotate, two_finger_tap, draw_path, draw_bezier, \
            edit_action, set_pasteboard, get_pasteboard, dismiss_keyboard, get_interface, get_screen.
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
                            "command": ["type": "string", "description": "Any fence command (activate, dismiss_keyboard, perform_custom_action, etc.)"],
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

    static let connect = Tool(
        name: "connect",
        description: """
            Switch the active connection to a different target at runtime without restarting the server. \
            Accepts either a named target from the config file (.buttonheist.json) or raw device/token \
            parameters. Tears down any existing session before connecting to the new target.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "target": [
                    "type": "string",
                    "description": "Named target from .buttonheist.json config file",
                ],
                "device": [
                    "type": "string",
                    "description": "Direct host:port address (e.g. 127.0.0.1:1455)",
                ],
                "token": [
                    "type": "string",
                    "description": "Auth token (overrides config file token if both provided)",
                ],
            ],
            "additionalProperties": false,
        ]
    )

    static let listTargets = Tool(
        name: "list_targets",
        description: """
            List named connection targets from the config file (.buttonheist.json or \
            ~/.config/buttonheist/config.json). Shows target names, device addresses, \
            and which target is the default.
            """,
        inputSchema: [
            "type": "object",
            "properties": .object([:]),
            "additionalProperties": false,
        ],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )
}
