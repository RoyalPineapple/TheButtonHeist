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

    // Shared element targeting properties — 6-property block used by action/scroll/gesture tools.
    // Elements are found through real accessibility properties (label, value, traits) — the same
    // interface VoiceOver users navigate. heistId is the stable shorthand from get_interface.
    // Avoid identifier — it is a developer escape hatch that real users cannot see.
    static let elementTargetProperties: [String: Value] = [
        "heistId": ["type": "string", "description": "Target element by stable heistId from get_interface (preferred for known elements)"],
        "label": ["type": "string", "description": "Target by accessibility label — the text VoiceOver reads aloud (e.g. \"Sign In\", \"Mountain Sunset\")"],
        "value": ["type": "string", "description": "Target by accessibility value — current state or placeholder (e.g. \"Email\", \"50%\", \"selected\")"],
        "traits": [
            "type": "array", "items": ["type": "string"],
            "description": "Target by traits — role qualifiers like button, header, selected, textEntry. All must match.",
        ],
        "excludeTraits": ["type": "array", "items": ["type": "string"], "description": "Exclude elements with any of these traits"],
        "identifier": ["type": "string", "description": "Target by accessibilityIdentifier (escape hatch — prefer label/value/traits)"],
        "ordinal": [
            "type": "integer",
            "description": """
                0-based index to disambiguate when multiple elements match. \
                0 = first match, 1 = second, etc. (tree traversal order). \
                Omit to require a unique match — ambiguity errors show the valid range.
                """,
        ],
    ]

    // Shared element filter properties — 5-property block used by get_interface (no heistId, uses "Filter" descriptions)
    static let elementFilterProperties: [String: Value] = [
        "label": ["type": "string", "description": "Filter by accessibility label (the text VoiceOver reads)"],
        "value": ["type": "string", "description": "Filter by accessibility value (current state or placeholder)"],
        "traits": ["type": "array", "items": ["type": "string"], "description": "Filter: all listed traits must be present"],
        "excludeTraits": ["type": "array", "items": ["type": "string"], "description": "Filter: none of these traits may be present"],
        "identifier": ["type": "string", "description": "Filter by accessibilityIdentifier (escape hatch — prefer label/value/traits)"],
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

    // MARK: - Getting Started
    //
    // Button Heist navigates iOS apps through the real accessibility interface — the same
    // labels, values, traits, hints, and actions that VoiceOver users rely on. There are no
    // accessibility identifiers involved. If the agent can't find an element, a blind user
    // can't either, and the fix is better accessibility — not a test hook.
    //
    // Start with these 5 tools:
    //   1. connect         — establish a session with the iOS app
    //   2. get_interface   — see what's on screen (elements with heistId, label, traits)
    //   3. activate        — tap elements that have "activate" in their actions array
    //   4. scroll_to_visible — navigate long lists to find off-screen elements
    //   5. run_batch       — multi-step sequences with expectations
    //
    // Finding elements:
    //   Every element on screen has a heistId (deterministic, stable across refreshes)
    //   plus natural accessibility properties: label, value, traits, actions, hints.
    //
    //   - heistId: copy from get_interface, paste into activate. Zero ambiguity, preferred
    //     for targeting specific known elements.
    //   - label: match by the text a VoiceOver user would hear ("Sign In", "Mountain Sunset").
    //   - value: match by the element's current value ("Email", "50%", "3 items remaining").
    //     Text fields expose placeholder text as their value when empty.
    //   - traits: match by role — "button", "staticText", "header", "selected", "notEnabled",
    //     "textEntry", "secureTextField", "image", etc. Add traits to disambiguate when labels
    //     collide (e.g. label="Add" + traits=["button"] to skip the "Add Todo" header).
    //   - actions: elements advertise custom actions like "Delete", "Add to Queue",
    //     "Remove from Favorites". Use activate(action: "Delete") to invoke them.
    //
    //   All matcher fields are AND — every field you specify must match. Start with just
    //   label, add traits or value only if you get ambiguous matches. If multiple elements
    //   still match, the error tells you the valid ordinal range — pass ordinal (0-based)
    //   to pick by position: 0 = first match, 1 = second, etc.
    //
    // Then layer in: type_text (keyboard), swipe (gestures), wait_for (async),
    // get_screen (screenshots), get_interface(full: true) (full screen census).

    static let all: [Tool] = [
        getInterface, activate, typeText, swipe, getScreen,
        waitForIdle, waitFor, startRecording, stopRecording, listDevices,
        gesture, editAction, dismissKeyboard, setPasteboard, getPasteboard,
        scroll, scrollToVisible, elementSearch, scrollToEdge,
        runBatch, getSessionState,
        connect, listTargets,
        getSessionLog, archiveSession,
        startHeist, stopHeist, playHeist,
    ]

    // MARK: - Individual Tools

    static let getInterface = Tool(
        name: "get_interface",
        description: """
            Get the current UI element hierarchy from the connected iOS device. Returns elements with \
            heistId, label, value, traits, and actions. Use detail=full for geometry (frame, activation point). \
            Target elements in subsequent calls using heistId. \
            Filter with matcher fields (label, traits, excludeTraits, etc.) or a heistId list. \
            Set full=true to discover every element on screen including off-screen content inside \
            scrollable containers (scrolls each container to its limits and back, restoring positions).
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(([
                "detail": [
                    "type": "string",
                    "enum": .array(["summary", "full"].map { .string($0) }),
                    "description": "Level of detail: summary (default, no geometry) or full (includes frame, activation point, hints)",
                ],
                "full": [
                    "type": "boolean",
                    "description": """
                        When true, explores the entire screen including off-screen content \
                        in scroll views. Returns all elements, not just visible ones.
                        """,
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
            Activate a UI element — the primary way to tap buttons, follow links, and toggle controls. \
            Works like a VoiceOver double-tap: tries accessibility activation first, falls back to synthetic tap. \
            Only elements with "activate" in their actions array can be activated — static text, headers, and \
            images without actions will fail. Check the element's actions in get_interface before calling. \
            Target by heistId (from get_interface) or by natural properties: label (what VoiceOver reads), \
            value (current state), traits (role like "button", "selected"). \
            If a label matches multiple elements, add traits to disambiguate (e.g. label="Add", traits=["button"]). \
            If multiple elements still match, the error shows the valid ordinal range — pass ordinal to select \
            by position (0 = first, 1 = second, etc.). \
            Pass 'action' to invoke a custom action instead: "increment", "decrement", "Delete", or any action from the element's actions array.
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
            Target text fields by value (placeholder text, e.g. value="Email") or by heistId.
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
        description: """
            List iOS devices discovered via Bonjour that are running TheInsideJob. \
            Also includes named targets from .buttonheist.json config. \
            If Bonjour is blocked (e.g. MDM stealth mode) and no config targets exist, \
            this returns empty — use connect(device:token:) with the known address instead.
            """,
        inputSchema: ["type": "object", "properties": .object([:]), "additionalProperties": false],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    // MARK: - Scroll Tools

    static let scroll = Tool(
        name: "scroll",
        description: """
            Scroll a scroll view by one page in a direction. Targets the nearest scrollable ancestor \
            of the specified element, or the main scroll view if no element is specified. \
            The direction determines which axis to scroll — scrolling "right" on an element inside \
            a horizontal carousel scrolls the carousel, while scrolling "down" scrolls the outer list.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "direction": [
                    "type": "string",
                    "enum": .array(["up", "down", "left", "right", "next", "previous"].map { .string($0) }),
                    "description": "Scroll direction",
                ],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "required": .array([.string("direction")]),
            "additionalProperties": false,
        ])
    )

    static let scrollToVisible = Tool(
        name: "scroll_to_visible",
        description: """
            Jump to a known element's position in its scroll view. The element must already be in \
            the registry (seen in a previous get_interface or action delta). If the element is already \
            visible, this is a no-op. If the element has never been seen, use element_search instead.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "additionalProperties": false,
        ])
    )

    static let elementSearch = Tool(
        name: "element_search",
        description: """
            Search for an element by scrolling through all scrollable containers on screen. \
            Use when the element has never been seen (not in the registry). Describe the element \
            by its natural accessibility properties: label, value, and/or traits (all specified \
            fields must match). Automatically searches outermost containers first, adapting the \
            scroll direction to each container's natural axis. Returns the found element or \
            diagnostic info about the search.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "direction": ["type": "string", "enum": ["down", "up", "left", "right"], "description": "Starting scroll direction (default: down)"],
                "expect": expectProperty,
            ] as [String: Value]) { _, new in new }),
            "additionalProperties": false,
        ])
    )

    static let scrollToEdge = Tool(
        name: "scroll_to_edge",
        description: """
            Scroll to an edge. Useful for scrolling to the top or bottom of a list. \
            Targets the scrollable container that matches the edge's axis — "top"/"bottom" \
            scroll vertically, "left"/"right" scroll horizontally.
            """,
        inputSchema: .object([
            "type": "object",
            "properties": .object(elementTargetProperties.merging([
                "edge": [
                    "type": "string",
                    "enum": .array(["top", "bottom", "left", "right"].map { .string($0) }),
                    "description": "Edge to scroll to",
                ],
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
            Establish or switch the active connection to an iOS device running TheInsideJob. \
            Three connection patterns: \
            (1) Named target: connect(target: "my-sim") — reads from .buttonheist.json config. \
            (2) Direct address: connect(device: "127.0.0.1:{port}", token: "{token}") — port and token \
            come from the app's launch env vars (SIMCTL_CHILD_INSIDEJOB_PORT, SIMCTL_CHILD_INSIDEJOB_TOKEN). \
            (3) Environment: set BUTTONHEIST_DEVICE and BUTTONHEIST_TOKEN before starting the MCP server. \
            Tears down any existing session before connecting to the new target.
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

    static let getSessionLog = Tool(
        name: "get_session_log",
        description: """
            Get the current session manifest showing all commands executed and \
            artifacts produced during this session.
            """,
        inputSchema: [
            "type": "object",
            "properties": .object([:]),
            "additionalProperties": false,
        ],
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let archiveSession = Tool(
        name: "archive_session",
        description: """
            Close and compress the current session into a .tar.gz archive. \
            Returns the archive file path.
            """,
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
            Start recording a heist playback. All subsequent commands (actions, gestures, \
            text input) are captured as steps in a .heist file. Element targets are recorded \
            as matchers (label, traits, identifier) rather than heistIds so the heist can be \
            replayed against any session. Call get_interface before acting to ensure element \
            data is cached for matcher construction.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "app": [
                    "type": "string",
                    "description": "Bundle ID of the app being recorded (default: com.buttonheist.testapp)",
                ],
            ],
            "additionalProperties": false,
        ]
    )

    static let stopHeist = Tool(
        name: "stop_heist",
        description: """
            Stop recording and save the heist playback to a .heist file. \
            Returns the file path and number of steps recorded.
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
            Play back a recorded .heist file. Each step is executed sequentially. \
            Playback stops on the first error. Returns the number of completed steps \
            and total timing.
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
