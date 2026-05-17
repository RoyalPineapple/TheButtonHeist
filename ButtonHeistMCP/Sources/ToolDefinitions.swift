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

    static var all: [Tool] {
        TheFence.Command.mcpToolContracts.map(tool(for:))
    }

    static func inputSchema(for contract: MCPToolContract) -> Value {
        inputSchema(
            properties: schemaProperties(from: contract.parameters),
            required: contract.requiredParameterKeys
        )
    }

    static func schemaProperties(from specs: [FenceParameterSpec]) -> [String: Value] {
        var properties: [String: Value] = [:]
        for spec in specs where properties[spec.key] == nil {
            properties[spec.key] = schemaProperty(for: spec)
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

    private static func tool(for contract: MCPToolContract) -> Tool {
        let schema = inputSchema(for: contract)
        let description = description(for: contract.name)
        switch contract.name {
        case TheFence.Command.getInterface.rawValue,
             TheFence.Command.getScreen.rawValue,
             TheFence.Command.listDevices.rawValue,
             TheFence.Command.getSessionState.rawValue,
             TheFence.Command.listTargets.rawValue,
             TheFence.Command.getSessionLog.rawValue:
            return Tool(
                name: contract.name,
                description: description,
                inputSchema: schema,
                annotations: .init(readOnlyHint: true, idempotentHint: true)
            )

        case TheFence.Command.waitForChange.rawValue,
             TheFence.Command.getPasteboard.rawValue:
            return Tool(
                name: contract.name,
                description: description,
                inputSchema: schema,
                annotations: .init(readOnlyHint: true)
            )

        default:
            return Tool(
                name: contract.name,
                description: description,
                inputSchema: schema
            )
        }
    }

    private static func description(for toolName: String) -> String {
        descriptionsByToolName[toolName] ?? "Execute the \(toolName) Button Heist tool."
    }

    private static let descriptionsByToolName: [String: String] = [
        TheFence.Command.getInterface.rawValue:
            """
            Read the app accessibility hierarchy. Call once on a new screen, then track changes via \
            action deltas — re-fetch only when you need elements the delta didn't cover. \
            Filter with matcher fields or heistId handle list. Omit scope for the normal \
            app accessibility state; use scope=visible only for diagnostic on-screen reads.
            """,

        TheFence.Command.activate.rawValue:
            """
            Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle \
            controls. Pass 'action' to invoke a named action like "increment", "decrement", or \
            any entry from the element's actions array.
            """,

        TheFence.Command.rotor.rawValue:
            """
            Move through a rotor exposed by an element. Defaults to next. Use rotors listed by \
            get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous \
            object result to continue like a VoiceOver user. For text-range results, also pass \
            the returned start and end offsets.
            """,

        TheFence.Command.typeText.rawValue:
            """
            Type text and/or delete characters via keyboard injection. Optionally target an \
            element to focus it first and read back the resulting value.
            """,

        TheFence.Command.waitFor.rawValue:
            """
            Wait for an element matching a predicate to appear, or to disappear with absent=true. \
            Polls on UI settle events. Returns the matched element or diagnostic info on timeout.
            """,

        TheFence.Command.getScreen.rawValue:
            "Capture a PNG screenshot from the connected device. Returns inline base64 PNG image data. Use 'output' to save to a file path instead.",

        TheFence.Command.waitForChange.rawValue:
            """
            Wait for the UI to change. With no expect, returns on any tree change. With expect, \
            rides through intermediate states (spinners, loading) until the expectation is met. \
            Use after an action whose delta showed a transient state and the expectation wasn't met yet.
            """,

        TheFence.Command.startRecording.rawValue:
            "Start an H.264/MP4 screen recording. Recording auto-stops on inactivity or max duration.",

        TheFence.Command.stopRecording.rawValue:
            """
            Stop an in-progress screen recording. Returns metadata only by default (raw video \
            is too large for MCP context); pass 'output' to save the MP4 to a file path.
            """,

        TheFence.Command.listDevices.rawValue:
            """
            List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. \
            Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.
            """,

        TheFence.Command.scroll.rawValue:
            """
            Scroll within scroll views. mode=page scrolls one page in 'direction'; \
            mode=to_visible brings a known element into view; mode=search scrolls until a \
            matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge.
            """,

        "gesture":
            """
            Perform a touch gesture. Prefer 'activate' for element interactions — gestures are for \
            swipes, drags, pinches, rotates, and free-form path drawing. Set 'type' to one of: \
            swipe, one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier.
            """,

        TheFence.Command.editAction.rawValue:
            """
            Perform an edit or keyboard action on the current first responder. \
            Actions: copy, paste, cut, select, selectAll, dismiss (dismiss the keyboard).
            """,

        TheFence.Command.setPasteboard.rawValue:
            """
            Write text to the general pasteboard from within the app. Content written by the app \
            itself does not trigger the iOS "Allow Paste" dialog when subsequently read.
            """,

        TheFence.Command.getPasteboard.rawValue:
            """
            Read text from the general pasteboard. iOS may show "Allow Paste" if the content \
            was written by another app.
            """,

        TheFence.Command.runBatch.rawValue:
            """
            Execute multiple commands in one call. Each step is a JSON object with 'command' set \
            to a canonical TheFence.Command name plus that command's parameters; grouped MCP tool \
            names and selector shapes are not accepted inside batches. Attach 'expect' per step to verify \
            inline. Returns ordered per-step results. \
            policy=stop_on_error (default) or continue_on_error.
            """,

        TheFence.Command.getSessionState.rawValue:
            """
            Inspect the current Button Heist session: connection status, device/app identity, \
            recording state, client timeouts, and a lightweight summary of the last action.
            """,

        TheFence.Command.connect.rawValue:
            """
            Establish or switch the active connection to an iOS app with Button Heist enabled. \
            Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or \
            BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. \
            Returns session state; call get_interface explicitly to observe UI hierarchy.
            """,

        TheFence.Command.listTargets.rawValue:
            """
            List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), \
            including each target's address and which one is the default.
            """,

        TheFence.Command.getSessionLog.rawValue:
            "Return the current session manifest: commands executed and artifacts produced.",

        TheFence.Command.archiveSession.rawValue:
            "Close and compress the current session into a .tar.gz archive; returns the path.",

        TheFence.Command.startHeist.rawValue:
            """
            Start recording a heist. Successful commands become steps in a .heist file; \
            use matcher fields (label, identifier, traits) for durable element targeting, not heistId. \
            Attach 'expect' to validate outcomes during playback.
            """,

        TheFence.Command.stopHeist.rawValue:
            """
            Stop recording and save the heist as a self-contained JSON playback script. \
            Returns the file path and step count. At least one step must have been recorded.
            """,

        TheFence.Command.playHeist.rawValue:
            """
            Play back a .heist file. Steps execute sequentially; playback stops on the first \
            failed step. On failure, returns full diagnostics: command, target, error, action \
            result, expectation result, and a complete interface snapshot at the failure point.
            """,
    ]
}
