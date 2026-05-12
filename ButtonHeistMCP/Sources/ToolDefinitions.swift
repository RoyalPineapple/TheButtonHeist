import ButtonHeist
import MCP

// NOTE: Grouped tool dispatch
// The `gesture`, `scroll`, and `editAction` tools fan in multiple
// TheFence.Command cases under a single MCP tool. Their `type`, `mode`, and
// `action` enum values are the literal `TheFence.Command` rawValues — the
// actual routing happens in main.swift, which reads the field and rewrites
// the outgoing request's `"command"` key before dispatch. When a new
// grouped command case is added to TheFence.Command, update both the tool's
// enum values below and the switch in main.swift.
//
// Note: `dismiss` is a keyboard action that lives inside the `editAction`
// tool's `action` enum. main.swift rewrites it to the `dismiss_keyboard`
// command, so on the wire it dispatches through the same TheFence handler
// as the CLI's standalone `dismiss_keyboard` subcommand. Agents can reach
// `dismiss_keyboard` via either `editAction(action: "dismiss")` or
// `dismissKeyboard` — both paths land on the same backend.

enum ToolDefinitions {
    // NOTE: Video data handling
    // The MCP server intentionally omits raw base64 video data from responses.
    // Video payloads can be tens of megabytes which would overwhelm the MCP
    // context window. Instead, video metadata (dimensions, duration, frame count,
    // stop reason, interaction count) is returned as a JSON summary.
    //
    // Agents that need the actual video file should pass the "output" parameter
    // in stop_recording to write to disk and receive only the file path.

    // Shared element matcher properties — the 5 fields VoiceOver users rely on plus the
    // accessibilityIdentifier escape hatch. Used directly by get_interface (filtering) and
    // extended with heistId/ordinal by action tools (targeting). Same vocabulary either way.
    static let elementMatcherProperties: [String: Value] = [
        "label": ["type": "string", "description": "Accessibility label — the text VoiceOver reads (e.g. \"Sign In\")"],
        "value": ["type": "string", "description": "Accessibility value — current state or placeholder (e.g. \"50%\")"],
        "traits": [
            "type": "array", "items": ["type": "string"],
            "description": "Required traits (role qualifiers like button, header, selected). All must match.",
        ],
        "excludeTraits": ["type": "array", "items": ["type": "string"], "description": "Traits that must NOT be present"],
        "identifier": ["type": "string", "description": "accessibilityIdentifier (escape hatch — prefer label/value/traits)"],
    ]

    // Element targeting = matcher fields plus heistId and ordinal disambiguation.
    static let elementTargetProperties: [String: Value] = elementMatcherProperties.merging([
        "heistId": ["type": "string", "description": "Stable heistId from get_interface (preferred for known elements)"],
        "ordinal": [
            "type": "integer",
            "description": """
                0-based index to disambiguate when multiple elements match. \
                0 = first match, 1 = second, etc. (tree traversal order). \
                Omit to require a unique match — ambiguity errors show the valid range.
                """,
        ],
    ] as [String: Value]) { _, new in new }

    // Shared expect property for action tools — matches the batch step schema.
    // Wire shape uses a `type` discriminator that matches ActionExpectation's
    // Codable encoding, so JSON from a wire log can be pasted into a tool call.
    static let expectProperty: Value = [
        "description": """
            Inline verification for this action. String form: "screen_changed" or "elements_changed". \
            Object form: {"type": "element_updated"|"element_appeared"|"element_disappeared"|"compound", ...}. \
            See docs/MCP-AGENT-GUIDE.md for the full expectation vocabulary and recipes.
            """,
        "oneOf": .array([
            [
                "type": "string",
                "enum": .array(["screen_changed", "elements_changed"].map { .string($0) }),
            ],
            [
                "type": "object",
                "description": "Discriminated expectation. `type` selects the case; other fields depend on the case.",
                "required": .array([.string("type")]),
                "properties": [
                    "type": [
                        "type": "string",
                        "enum": .array([
                            "screen_changed", "elements_changed", "element_updated",
                            "element_appeared", "element_disappeared", "compound",
                        ].map { .string($0) }),
                    ],
                    "heistId": ["type": "string", "description": "element_updated: match a specific element"],
                    "property": [
                        "type": "string",
                        "description": "element_updated: match a specific property",
                        "enum": .array(["label", "value", "traits", "hint", "actions", "frame", "activationPoint"].map { .string($0) }),
                    ],
                    "oldValue": ["type": "string", "description": "element_updated: expected previous value"],
                    "newValue": ["type": "string", "description": "element_updated: expected new value"],
                    "matcher": [
                        "type": "object",
                        "description": "element_appeared / element_disappeared: predicate identifying the element",
                        "properties": [
                            "label": ["type": "string"],
                            "identifier": ["type": "string"],
                            "value": ["type": "string"],
                            "traits": ["type": "array", "items": ["type": "string"]],
                            "excludeTraits": ["type": "array", "items": ["type": "string"]],
                        ],
                        "additionalProperties": false,
                    ],
                    "expectations": [
                        "type": "array",
                        "description": "compound: array of sub-expectations (strings or objects)",
                    ],
                ],
                "additionalProperties": false,
            ],
        ]),
    ]

    static let all: [Tool] = [
        getInterface, activate, typeText, getScreen,
        waitForChange, waitFor, startRecording, stopRecording, listDevices,
        gesture, editAction, setPasteboard, getPasteboard,
        scroll,
        runBatch, getSessionState,
        connect, listTargets,
        getSessionLog, archiveSession,
        startHeist, stopHeist, playHeist,
    ]

    // MARK: - Individual Tools

    static let getInterface = Tool(
        name: "get_interface",
        description: """
            Read the UI element hierarchy. Call once on a new screen, then track changes via \
            action deltas — re-fetch only when you need elements the delta didn't cover. \
            Filter with matcher fields or heistId list; pass full=false for only visible elements.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(([
                "detail": [
                    "type": "string",
                    "enum": .array(["summary", "full"].map { .string($0) }),
                    "description": """
                        Level of detail. summary (default): identity fields, traits, and actions only \
                        — no hint, customContent, frames, or activation points. full: adds VoiceOver \
                        hint, customContent, frame, and activation point.
                        """,
                ],
                "full": [
                    "type": "boolean",
                    "description": """
                        Full exploration is on by default — set to false to return only \
                        visible elements (faster, but misses off-screen content in scroll views).
                        """,
                ],
                "elements": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional list of heistIds to filter. Returns only matching elements. Omit for full tree.",
                ],
            ] as [String: Value]).merging(elementMatcherProperties) { _, new in new }),
            "additionalProperties": false,
        ]),
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let activate = Tool(
        name: "activate",
        description: """
            Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle \
            controls. Pass 'action' to invoke a named action like "increment", "decrement", or \
            any entry from the element's actions array.
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
            Type text and/or delete characters via keyboard injection. Optionally target an \
            element to focus it first and read back the resulting value.
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

    static let waitFor = Tool(
        name: "wait_for",
        description: """
            Wait for an element matching a predicate to appear, or to disappear with absent=true. \
            Polls on UI settle events. Returns the matched element or diagnostic info on timeout.
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

    static let waitForChange = Tool(
        name: "wait_for_change",
        description: """
            Wait for the UI to change. With no expect, returns on any tree change. With expect, \
            rides through intermediate states (spinners, loading) until the expectation is met. \
            Use after an action whose delta showed a transient state and the expectation wasn't met yet.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "expect": expectProperty,
                "timeout": ["type": "number", "description": "Maximum wait time in seconds (default: 10, max: 30)"],
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
            Stop an in-progress screen recording. Returns metadata only by default (raw video \
            is too large for MCP context); pass 'output' to save the MP4 to a file path.
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
        description: """
            List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. \
            Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.
            """,
        inputSchema: ["type": "object", "properties": .object([:]), "additionalProperties": false],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    // MARK: - Scroll Tool

    static let scroll = Tool(
        name: "scroll",
        description: """
            Scroll within scroll views. mode=page scrolls one page in 'direction'; \
            mode=to_visible jumps to an element seen previously; mode=search scrolls all \
            containers to find an unseen element; mode=to_edge scrolls to a top/bottom/left/right edge.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "mode": [
                    "type": "string",
                    "enum": .array(["page", "to_visible", "search", "to_edge"].map { .string($0) }),
                    "description": "Scroll mode (default: page)",
                ],
                "direction": [
                    "type": "string",
                    "enum": .array(["up", "down", "left", "right", "next", "previous"].map { .string($0) }),
                    "description": "Scroll direction (required for mode page, optional starting direction for mode search)",
                ],
                "edge": [
                    "type": "string",
                    "enum": .array(["top", "bottom", "left", "right"].map { .string($0) }),
                    "description": "Edge to scroll to (required for mode to_edge)",
                ],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "additionalProperties": false,
        ])
    )

    // MARK: - Grouped Tools

    static let gesture = Tool(
        name: "gesture",
        description: """
            Perform a touch gesture. Prefer 'activate' for element interactions — gestures are for \
            swipes, drags, pinches, rotates, and free-form path drawing. Set 'type' to one of: \
            swipe, one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "type": [
                    "type": "string",
                    "enum": .array([
                        "swipe", "one_finger_tap", "drag", "long_press", "pinch",
                        "rotate", "two_finger_tap", "draw_path", "draw_bezier",
                    ].map { .string($0) }),
                    "description": "Gesture type",
                ],
                "direction": [
                    "type": "string",
                    "description": "Swipe direction: up, down, left, right",
                ],
                "start": [
                    "type": "object",
                    "description": "Swipe start unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    "properties": [
                        "x": ["type": "number", "description": "X position (0-1)"],
                        "y": ["type": "number", "description": "Y position (0-1)"],
                    ],
                    "required": .array([.string("x"), .string("y")]),
                ],
                "end": [
                    "type": "object",
                    "description": "Swipe end unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    "properties": [
                        "x": ["type": "number", "description": "X position (0-1)"],
                        "y": ["type": "number", "description": "Y position (0-1)"],
                    ],
                    "required": .array([.string("x"), .string("y")]),
                ],
                "x": ["type": "number", "description": "X coordinate"],
                "y": ["type": "number", "description": "Y coordinate"],
                "startX": ["type": "number", "description": "Start X coordinate (swipe, draw_bezier)"],
                "startY": ["type": "number", "description": "Start Y coordinate (swipe, draw_bezier)"],
                "endX": ["type": "number", "description": "End X coordinate (swipe, drag)"],
                "endY": ["type": "number", "description": "End Y coordinate (swipe, drag)"],
                "duration": ["type": "number", "description": "Duration in seconds (swipe, long_press default 0.5, draw_path, draw_bezier)"],
                "scale": ["type": "number", "description": "Pinch scale factor (>1 zoom in, <1 zoom out)"],
                "angle": ["type": "number", "description": "Rotation angle in radians"],
                "centerX": ["type": "number", "description": "Center X (pinch, rotate, two_finger_tap — defaults to element center or x)"],
                "centerY": ["type": "number", "description": "Center Y (pinch, rotate, two_finger_tap — defaults to element center or y)"],
                "spread": ["type": "number", "description": "Finger spread distance (pinch, two_finger_tap)"],
                "radius": ["type": "number", "description": "Rotation radius (rotate)"],
                "velocity": ["type": "number", "description": "Drawing velocity in points/sec (draw_path, draw_bezier)"],
                "samplesPerSegment": ["type": "integer", "description": "Bezier curve sampling resolution (draw_bezier)"],
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
            Perform an edit or keyboard action on the current first responder. \
            Actions: copy, paste, cut, select, selectAll, dismiss (dismiss the keyboard).
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": .array(["copy", "paste", "cut", "select", "selectAll", "dismiss"].map { .string($0) }),
                    "description": "Action to perform",
                ],
                "expect": expectProperty,
            ],
            "required": .array([.string("action")]),
            "additionalProperties": false,
        ]
    )

    static let setPasteboard = Tool(
        name: "set_pasteboard",
        description: """
            Write text to the general pasteboard from within the app. Content written by the app \
            itself does not trigger the iOS "Allow Paste" dialog when subsequently read.
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
            Read text from the general pasteboard. iOS may show "Allow Paste" if the content \
            was written by another app.
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
            Execute multiple commands in one call. Each step is a JSON object with 'command' plus \
            that command's parameters; attach 'expect' per step to verify inline. Returns per-step \
            results and a merged net delta. policy=stop_on_error (default) or continue_on_error.
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
            Inspect the current Button Heist session: connection status, device/app identity, \
            recording state, client timeouts, and a lightweight summary of the last action.
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
            Establish or switch the active connection to an iOS device running TheInsideJob. \
            Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or \
            BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first.
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
            List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), \
            including each target's address and which one is the default.
            """,
        inputSchema: [
            "type": "object",
            "properties": .object([:]),
            "additionalProperties": false,
        ],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let getSessionLog = Tool(
        name: "get_session_log",
        description: "Return the current session manifest: commands executed and artifacts produced.",
        inputSchema: [
            "type": "object",
            "properties": .object([:]),
            "additionalProperties": false,
        ],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let archiveSession = Tool(
        name: "archive_session",
        description: "Close and compress the current session into a .tar.gz archive; returns the path.",
        inputSchema: [
            "type": "object",
            "properties": [
                "delete_source": [
                    "type": "boolean",
                    "description": "Delete the session directory after archiving (default: false)",
                ],
            ],
            "additionalProperties": false,
        ]
    )

    static let startHeist = Tool(
        name: "start_heist",
        description: """
            Start recording a heist. Successful commands become steps in a .heist file; \
            read-only and meta-commands are filtered out. Target elements by matcher fields \
            (label, value, traits) — never by heistId — and attach 'expect' for replay validation.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "app": [
                    "type": "string",
                    "description": "Bundle ID of the app being recorded (default: \(Defaults.demoAppBundleID))",
                ],
                "identifier": [
                    "type": "string",
                    "description": "Session name for the recording (default: heist). Used as directory name if a new session is created.",
                ],
            ],
            "additionalProperties": false,
        ]
    )

    static let stopHeist = Tool(
        name: "stop_heist",
        description: """
            Stop recording and save the heist as a self-contained JSON playback script. \
            Returns the file path and step count. At least one step must have been recorded.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "output": [
                    "type": "string",
                    "description": "File path to write the .heist file",
                ],
            ],
            "required": .array(["output"]),
            "additionalProperties": false,
        ]
    )

    static let playHeist = Tool(
        name: "play_heist",
        description: """
            Play back a .heist file. Steps execute sequentially; playback stops on the first \
            failed step. On failure, returns full diagnostics: command, target, error, action \
            result, expectation result, and a complete interface snapshot at the failure point.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "input": [
                    "type": "string",
                    "description": "Path to the .heist file to play back",
                ],
            ],
            "required": .array(["input"]),
            "additionalProperties": false,
        ]
    )
}
