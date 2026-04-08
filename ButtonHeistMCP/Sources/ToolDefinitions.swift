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
            Inline verification for this action — match the expectation to what the action does. \
            Navigation (tap a link, back button): "screen_changed". \
            Insertion or deletion (add item, delete row): "elements_changed". \
            State change (toggle, picker, text input): \
            {"elementUpdated": {"heistId": "x", "property": "value", "newValue": "5"}} — \
            proves the specific property changed. All fields optional, omitted = wildcard. \
            {"elementAppeared": {"label": "Success"}} — check that a matching element was added. \
            {"elementDisappeared": {"label": "Loading"}} — check that a matching element was removed. \
            Expectations are most valuable inside run_batch: each step declares what should happen, \
            and a failed expectation stops the batch at the exact step that diverged — the agent \
            knows immediately what went wrong instead of discovering it turns later.
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
                    "elementAppeared": [
                        "type": "object",
                        "description": "Expect an element matching this predicate to appear in the delta's added list",
                        "properties": [
                            "label": ["type": "string"],
                            "identifier": ["type": "string"],
                            "value": ["type": "string"],
                            "traits": ["type": "array", "items": ["type": "string"]],
                            "excludeTraits": ["type": "array", "items": ["type": "string"]],
                        ],
                        "additionalProperties": false,
                    ],
                    "elementDisappeared": [
                        "type": "object",
                        "description": "Expect an element matching this predicate to disappear from the delta's removed list",
                        "properties": [
                            "label": ["type": "string"],
                            "identifier": ["type": "string"],
                            "value": ["type": "string"],
                            "traits": ["type": "array", "items": ["type": "string"]],
                            "excludeTraits": ["type": "array", "items": ["type": "string"]],
                        ],
                        "additionalProperties": false,
                    ],
                ],
                "additionalProperties": false,
            ],
        ]),
    ]

    // MARK: - Getting Started
    //
    // Button Heist navigates iOS apps through the real accessibility interface — the same
    // labels, values, traits, hints, and actions that VoiceOver users rely on.
    //
    // Core workflow:
    //   1. connect         — establish a session with the iOS app
    //   2. get_interface   — read the screen once (elements with heistId, label, traits)
    //   3. Act and read deltas — every action returns what changed. Don't call
    //      get_interface after every action — the delta is your feedback loop.
    //   4. run_batch       — for mechanical sequences where every step is predictable
    //      from what you already know (e.g. filling a form, toggling a series of switches).
    //      Don't batch exploratory actions or anything that depends on reading the result.
    //
    // Finding elements:
    //   Every element has a heistId (stable on the current screen) plus label, value,
    //   traits, actions, hints. Use heistId for known elements, label/traits for discovery.
    //   All matcher fields are AND. Start with just label, add traits if ambiguous.
    //
    // Batching:
    //   Most actions should be individual calls — read the delta, decide the next step.
    //   Use run_batch only for mechanical sequences where you already know every step
    //   and none depend on intermediate results (filling form fields, toggling a known
    //   list of switches, navigating a fixed path). Attach 'expect' to each step so the
    //   batch is self-verifying. Don't batch just because you have multiple steps planned —
    //   batch because the steps are truly independent of each other's results.

    static let all: [Tool] = [
        getInterface, activate, typeText, swipe, getScreen,
        waitForChange, waitFor, startRecording, stopRecording, listDevices,
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
            Read the full UI element hierarchy. Call once when you arrive on a new screen, \
            then use deltas from subsequent actions to track changes — don't call again unless \
            you need elements the delta didn't cover. \
            \
            Every action (activate, type_text, scroll, etc.) returns a delta: \
            + heistId "label" [traits] = appeared, - heistId = disappeared, \
            ~ heistId: property "old" → "new" = changed, screen changed = new screen \
            (full interface included, previous heistIds invalidated). \
            The delta is your primary feedback loop — it tells you what happened without \
            an extra round trip. \
            \
            By default explores the entire screen including off-screen content in scroll views. \
            Pass full=false for only visible elements (faster). Use detail=full for geometry. \
            Filter with matcher fields (label, traits, excludeTraits) or a heistId list. \
            \
            Targeting: heistId is stable on the current screen — copy from a previous response, \
            use in the next action. After a screen change, all heistIds reset — use matchers \
            (label, value, traits) or read from the delta's new interface. Never construct or \
            predict a heistId. Matcher strings are case-insensitive substrings; traits match exactly. \
            Zero matches returns suggestions, never a fuzzy guess.
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
                        Full exploration is on by default — set to false to return only \
                        visible elements (faster, but misses off-screen content in scroll views).
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
            Activate a UI element — tap buttons, follow links, toggle controls. Returns a delta \
            showing what changed, so you don't need to call get_interface after every action. \
            Works like a VoiceOver double-tap: accessibility activation first, synthetic tap fallback. \
            Only elements with "activate" in their actions array can be activated. \
            Target by heistId (from get_interface) or by label, value, traits. \
            If a label matches multiple elements, add traits to disambiguate (e.g. label="Add", traits=["button"]). \
            If multiple elements still match, the error shows the valid ordinal range — pass ordinal to select \
            by position (0 = first, 1 = second, etc.). \
            Pass 'action' to invoke a custom action: "increment", "decrement", "Delete", or any action from the element's actions array.
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
                "startX": ["type": "number", "description": "Start X screen coordinate (alternative to unit-point start)"],
                "startY": ["type": "number", "description": "Start Y screen coordinate"],
                "endX": ["type": "number", "description": "End X screen coordinate (alternative to unit-point end)"],
                "endY": ["type": "number", "description": "End Y screen coordinate"],
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

    static let waitForChange = Tool(
        name: "wait_for_change",
        description: """
            Wait for the UI to change in a way that matches an expectation. Uses the same \
            expect vocabulary as action commands — "screen_changed", "elements_changed", \
            elementAppeared, elementDisappeared, elementUpdated. \
            \
            With no expectation, returns on any tree change. With expect, rides through \
            intermediate states until the expectation is met: spinner appears → keep waiting → \
            receipt screen loads → return. The server re-evaluates on every settle cycle. \
            \
            When to use: after an action whose delta shows a transient state (loading indicator \
            appeared, interactive elements vanished) and your expectation wasn't met. Pass the \
            same expectation you used on the action — the server picks up where the action left off. \
            \
            Example flow: activate pay_now_button expect="screen_changed" → delta shows spinner, \
            expectation not met → wait_for_change expect="screen_changed" timeout=10 → receipt \
            screen arrives, expectation met.
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
            Scroll a scroll view by one page in a direction. Requires an element target — scrolls \
            the nearest scrollable ancestor of that element. \
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
            long_press: duration (seconds, default 0.5). \
            pinch: scale required (>1 zoom in, <1 zoom out), optional centerX/centerY (default element center or x/y), spread. \
            rotate: angle required (radians), optional centerX/centerY, radius. \
            two_finger_tap: optional centerX/centerY, spread. \
            draw_path: points array of {x, y} objects, optional velocity (points/sec). \
            draw_bezier: startX, startY required; segments array of {cp1X, cp1Y, cp2X, cp2Y, endX, endY}; \
            optional samplesPerSegment, velocity.
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
                "duration": ["type": "number", "description": "Duration in seconds (long_press default 0.5, draw_path, draw_bezier)"],
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
            Execute multiple commands in a single call — but only for mechanical sequences \
            where every step is predictable from what you already know. Good uses: filling \
            form fields, toggling a known list of switches, navigating a fixed menu path. \
            Bad uses: exploring unfamiliar UI, acting on elements you haven't verified exist, \
            or sequences where step N depends on step N-1's result. When in doubt, use \
            individual calls and read the delta between each. \
            \
            Each step is a JSON object with 'command' plus that command's parameters. Returns \
            per-step results and a merged net delta. Use stop_on_error (default) for dependent \
            sequences, continue_on_error for independent steps. \
            \
            Attach 'expect' to each step for inline verification. Without expectations, \
            a silent failure at step 2 goes unnoticed until the agent re-reads the interface \
            turns later. With expectations, the batch stops at the exact step that diverged. \
            Match the expectation to the action: "screen_changed" for navigation, \
            "elements_changed" for insertions/deletions, {"elementUpdated": {...}} for state \
            changes like toggles, pickers, and text input. \
            \
            Valid commands: activate, increment, decrement, perform_custom_action, type_text, \
            scroll, scroll_to_visible, scroll_to_edge, swipe, one_finger_tap, long_press, drag, \
            pinch, rotate, two_finger_tap, draw_path, draw_bezier, edit_action, set_pasteboard, \
            get_pasteboard, dismiss_keyboard, get_interface, get_screen.
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
            Start recording a heist. All subsequent successful commands are captured as \
            steps in a .heist file. Failed actions are silently skipped. \
            \
            Before recording: call get_interface to populate the element cache. The recorder \
            converts heistIds to portable matchers (label, traits, identifier) automatically, \
            but can only build good matchers when it has cached element data. Without a primed \
            cache, steps degrade to coordinate-only evidence that breaks across devices. \
            \
            During recording: attach 'expect' to actions — expectations are recorded with each \
            step and validated on every replay. Use specific expectations over generic ones: \
            {"elementUpdated": {"heistId": "toggle", "newValue": "1"}} tells you exactly what \
            broke on replay; "elements_changed" only tells you something didn't move. \
            \
            Read-only commands (get_interface, get_screen, status) and meta-commands \
            (run_batch, start/stop_recording) are not recorded.
            """,
        inputSchema: [
            "type": "object",
            "properties": [
                "app": [
                    "type": "string",
                    "description": "Bundle ID of the app being recorded (default: com.buttonheist.testapp)",
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
            Stop recording and save the heist to a .heist file. Returns the file path \
            and number of steps recorded. At least one step must have been recorded. \
            The output file is a self-contained JSON playback script with matcher-based \
            element targeting — no heistIds, no coordinates, portable across sessions.
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
            Play back a .heist file. Steps execute sequentially against the connected app. \
            Playback stops on the first failed step (action error or unsuccessful result). \
            Returns completed step count, failed step index (if any), and total timing in ms. \
            If the heist was recorded against a different app, a warning is logged but \
            playback proceeds — the matchers may still resolve correctly.
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
