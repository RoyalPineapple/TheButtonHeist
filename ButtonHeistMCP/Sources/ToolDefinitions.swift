import ButtonHeist
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

    static func inputSchema(
        for command: TheFence.Command,
        overriding overrides: [String: Value] = [:]
    ) -> Value {
        inputSchema(
            properties: schemaProperties(from: command.parameters, overriding: overrides),
            required: command.parameters.filter(\.required).map(\.key)
        )
    }

    static func inputSchema(
        for commands: [TheFence.Command],
        required: [String] = [],
        overriding overrides: [String: Value] = [:]
    ) -> Value {
        inputSchema(
            properties: schemaProperties(from: commands.flatMap(\.parameters), overriding: overrides),
            required: required
        )
    }

    static func schemaProperties(
        from specs: [FenceParameterSpec],
        overriding overrides: [String: Value] = [:]
    ) -> [String: Value] {
        var properties: [String: Value] = [:]
        for spec in specs where properties[spec.key] == nil {
            properties[spec.key] = schemaProperty(for: spec)
        }
        for (key, override) in overrides {
            properties[key] = override
        }
        return properties
    }

    static func inputSchema(properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": "object",
            "properties": .object(properties),
            "additionalProperties": false,
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    static func schemaProperty(for spec: FenceParameterSpec) -> Value {
        var schema: [String: Value] = ["type": .string(schemaType(for: spec.type))]
        if let description = spec.description { schema["description"] = .string(description) }
        if let enumValues = spec.enumValues { schema["enum"] = .array(enumValues.map { .string($0) }) }
        if let minimum = spec.minimum { schema["minimum"] = schemaNumberValue(minimum) }
        if let maximum = spec.maximum { schema["maximum"] = schemaNumberValue(maximum) }
        if let minLength = spec.minLength { schema["minLength"] = .int(minLength) }

        switch spec.type {
        case .stringArray:
            schema["type"] = "array"
            schema["items"] = ["type": "string"]

        case .object where !spec.objectProperties.isEmpty:
            schema["properties"] = .object(schemaProperties(from: spec.objectProperties))
            let required = spec.objectProperties.filter(\.required).map(\.key)
            if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
            schema["additionalProperties"] = .bool(spec.objectAdditionalProperties)

        case .array:
            if let itemType = spec.arrayItemType {
                var items: [String: Value] = ["type": .string(schemaType(for: itemType))]
                if itemType == .object {
                    items["properties"] = .object(schemaProperties(from: spec.arrayItemProperties))
                    let required = spec.arrayItemProperties.filter(\.required).map(\.key)
                    if !required.isEmpty { items["required"] = .array(required.map { .string($0) }) }
                    items["additionalProperties"] = .bool(spec.arrayItemAdditionalProperties)
                }
                schema["items"] = .object(items)
            }

        default:
            break
        }

        return .object(schema)
    }

    static func schemaType(for type: FenceParameterSpec.ParamType) -> String {
        switch type {
        case .string:
            return "string"
        case .integer:
            return "integer"
        case .number:
            return "number"
        case .boolean:
            return "boolean"
        case .stringArray, .array:
            return "array"
        case .object:
            return "object"
        }
    }

    static func schemaNumberValue(_ value: Double) -> Value {
        if value.rounded(.towardZero) == value {
            return .int(Int(value))
        }
        return .double(value)
    }

    static func groupedCommands(under toolName: String) -> [TheFence.Command] {
        TheFence.Command.allCases.filter {
            if case .groupedUnder(let groupedToolName) = $0.mcpExposure {
                return groupedToolName == toolName
            }
            return false
        }
    }

    static func stringEnumValues<E>(
        _ type: E.Type,
        appending extraValues: [String] = []
    ) -> Value where E: CaseIterable & RawRepresentable, E.RawValue == String {
        .array((E.allCases.map(\.rawValue) + extraValues).map { .string($0) })
    }

    static let all: [Tool] = [
        getInterface, activate, rotor, typeText, getScreen,
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
            Filter with matcher fields or heistId handle list; scope defaults to full.
            """,
        inputSchema: inputSchema(for: .getInterface),
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let activate = Tool(
        name: "activate",
        description: """
            Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle \
            controls. Pass 'action' to invoke a named action like "increment", "decrement", or \
            any entry from the element's actions array.
            """,
        inputSchema: inputSchema(for: .activate)
    )

    static let rotor = Tool(
        name: "rotor",
        description: """
            Move through a rotor exposed by an element. Defaults to next. Use rotors listed by \
            get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous \
            object result to continue like a VoiceOver user. For text-range results, also pass \
            the returned start and end offsets.
            """,
        inputSchema: inputSchema(for: .rotor)
    )

    static let typeText = Tool(
        name: "type_text",
        description: """
            Type text and/or delete characters via keyboard injection. Optionally target an \
            element to focus it first and read back the resulting value.
            """,
        inputSchema: inputSchema(for: .typeText)
    )

    static let waitFor = Tool(
        name: "wait_for",
        description: """
            Wait for an element matching a predicate to appear, or to disappear with absent=true. \
            Polls on UI settle events. Returns the matched element or diagnostic info on timeout.
            """,
        inputSchema: inputSchema(for: .waitFor)
    )

    static let getScreen = Tool(
        name: "get_screen",
        description: "Capture a PNG screenshot from the connected device. Returns inline base64 PNG image data. Use 'output' to save to a file path instead.",
        inputSchema: inputSchema(for: .getScreen),
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let waitForChange = Tool(
        name: "wait_for_change",
        description: """
            Wait for the UI to change. With no expect, returns on any tree change. With expect, \
            rides through intermediate states (spinners, loading) until the expectation is met. \
            Use after an action whose delta showed a transient state and the expectation wasn't met yet.
            """,
        inputSchema: inputSchema(for: .waitForChange),
        annotations: .init(readOnlyHint: true)
    )

    static let startRecording = Tool(
        name: "start_recording",
        description: "Start an H.264/MP4 screen recording. Recording auto-stops on inactivity or max duration.",
        inputSchema: inputSchema(for: .startRecording)
    )

    static let stopRecording = Tool(
        name: "stop_recording",
        description: """
            Stop an in-progress screen recording. Returns metadata only by default (raw video \
            is too large for MCP context); pass 'output' to save the MP4 to a file path.
            """,
        inputSchema: inputSchema(for: .stopRecording)
    )

    static let listDevices = Tool(
        name: "list_devices",
        description: """
            List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. \
            Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.
            """,
        inputSchema: inputSchema(for: .listDevices),
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    // MARK: - Scroll Tool

    static let scroll = Tool(
        name: "scroll",
        description: """
            Scroll within scroll views. mode=page scrolls one page in 'direction'; \
            mode=to_visible brings a known element into view; mode=search scrolls until a \
            matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge.
            """,
        inputSchema: inputSchema(
            for: [.scroll] + groupedCommands(under: "scroll"),
            overriding: [
                "mode": [
                    "type": "string",
                    "enum": stringEnumValues(ScrollMode.self),
                    "description": "Scroll mode (default: page)",
                ],
            ]
        )
    )

    // MARK: - Grouped Tools

    static let gesture = Tool(
        name: "gesture",
        description: """
            Perform a touch gesture. Prefer 'activate' for element interactions — gestures are for \
            swipes, drags, pinches, rotates, and free-form path drawing. Set 'type' to one of: \
            swipe, one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier.
            """,
        inputSchema: inputSchema(
            for: groupedCommands(under: "gesture"),
            required: ["type"],
            overriding: [
                "type": [
                    "type": "string",
                    "enum": stringEnumValues(GestureType.self),
                    "description": "Gesture type",
                ],
            ]
        )
    )

    static let editAction = Tool(
        name: "edit_action",
        description: """
            Perform an edit or keyboard action on the current first responder. \
            Actions: copy, paste, cut, select, selectAll, dismiss (dismiss the keyboard).
            """,
        inputSchema: inputSchema(
            for: .editAction,
            overriding: [
                "action": [
                    "type": "string",
                    "enum": stringEnumValues(EditAction.self, appending: ["dismiss"]),
                    "description": "Action to perform",
                ],
            ]
        )
    )

    static let setPasteboard = Tool(
        name: "set_pasteboard",
        description: """
            Write text to the general pasteboard from within the app. Content written by the app \
            itself does not trigger the iOS "Allow Paste" dialog when subsequently read.
            """,
        inputSchema: inputSchema(for: .setPasteboard)
    )

    static let getPasteboard = Tool(
        name: "get_pasteboard",
        description: """
            Read text from the general pasteboard. iOS may show "Allow Paste" if the content \
            was written by another app.
            """,
        inputSchema: inputSchema(for: .getPasteboard),
        annotations: .init(readOnlyHint: true)
    )

    static let runBatch = Tool(
        name: "run_batch",
        description: """
            Execute multiple commands in one call. Each step is a JSON object with 'command' set \
            to an MCP tool name or raw Button Heist command plus that command's parameters; attach \
            'expect' per step to verify inline. Returns per-step results and a merged net delta. \
            policy=stop_on_error (default) or continue_on_error.
            """,
        inputSchema: inputSchema(for: .runBatch)
    )

    static let getSessionState = Tool(
        name: "get_session_state",
        description: """
            Inspect the current Button Heist session: connection status, device/app identity, \
            recording state, client timeouts, and a lightweight summary of the last action.
            """,
        inputSchema: inputSchema(for: .getSessionState),
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let connect = Tool(
        name: "connect",
        description: """
            Establish or switch the active connection to an iOS app with Button Heist enabled. \
            Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or \
            BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. \
            Returns session state; call get_interface explicitly to observe UI hierarchy.
            """,
        inputSchema: inputSchema(for: .connect)
    )

    static let listTargets = Tool(
        name: "list_targets",
        description: """
            List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), \
            including each target's address and which one is the default.
            """,
        inputSchema: inputSchema(for: .listTargets),
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let getSessionLog = Tool(
        name: "get_session_log",
        description: "Return the current session manifest: commands executed and artifacts produced.",
        inputSchema: inputSchema(for: .getSessionLog),
        annotations: .init(readOnlyHint: true, idempotentHint: true)
    )

    static let archiveSession = Tool(
        name: "archive_session",
        description: "Close and compress the current session into a .tar.gz archive; returns the path.",
        inputSchema: inputSchema(for: .archiveSession)
    )

    static let startHeist = Tool(
        name: "start_heist",
        description: """
            Start recording a heist. Successful commands become steps in a .heist file; \
            use matcher fields (label, identifier, traits) for durable element targeting, not heistId. \
            Attach 'expect' to validate outcomes during playback.
            """,
        inputSchema: inputSchema(
            for: .startHeist,
            overriding: [
                "app": [
                    "type": "string",
                    "description": "Bundle ID of the app being recorded (default: \(Defaults.demoAppBundleID))",
                ],
            ]
        )
    )

    static let stopHeist = Tool(
        name: "stop_heist",
        description: """
            Stop recording and save the heist as a self-contained JSON playback script. \
            Returns the file path and step count. At least one step must have been recorded.
            """,
        inputSchema: inputSchema(for: .stopHeist)
    )

    static let playHeist = Tool(
        name: "play_heist",
        description: """
            Play back a .heist file. Steps execute sequentially; playback stops on the first \
            failed step. On failure, returns full diagnostics: command, target, error, action \
            result, expectation result, and a complete interface snapshot at the failure point.
            """,
        inputSchema: inputSchema(for: .playHeist)
    )
}
