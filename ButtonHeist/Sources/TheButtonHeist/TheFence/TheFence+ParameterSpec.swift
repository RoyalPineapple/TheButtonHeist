import Foundation
import TheScore

// MARK: - Parameter Specification

/// Describes one parameter key that TheFence extracts from the `[String: Any]` request dictionary.
/// Used to generate MCP tool schemas and verify CLI/MCP sync.
///
/// Declared at module scope (not nested in TheFence) to avoid inheriting @ButtonHeistActor isolation.
public struct FenceParameterSpec: Sendable, Equatable {

    // MARK: - Nested Types

    /// JSON-level type of a parameter value.
    public enum ParamType: String, Sendable, Equatable {
        case string
        case integer
        case number       // double
        case boolean
        case stringArray
        case object
        case array        // generic array (points, segments, steps)
    }

    /// Why a non-required parameter belongs in the public command contract.
    public enum OptionalRole: String, Sendable, Equatable {
        case matcher
        case payload
        case behaviorSwitch
        case compatibility
    }

    // MARK: - Properties

    public let key: String
    public let type: ParamType
    public let required: Bool
    public let optionalRole: OptionalRole?
    public let description: String?
    public let enumValues: [String]?
    public let minimum: Double?
    public let maximum: Double?
    public let minLength: Int?
    public let objectProperties: [FenceParameterSpec]
    public let objectAdditionalProperties: Bool
    public let arrayItemType: ParamType?
    public let arrayItemProperties: [FenceParameterSpec]
    public let arrayItemAdditionalProperties: Bool

    // MARK: - Init

    public init(
        key: String,
        type: ParamType,
        required: Bool = false,
        optionalRole: OptionalRole? = nil,
        description: String? = nil,
        enumValues: [String]? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        objectProperties: [FenceParameterSpec] = [],
        objectAdditionalProperties: Bool = false,
        arrayItemType: ParamType? = nil,
        arrayItemProperties: [FenceParameterSpec] = [],
        arrayItemAdditionalProperties: Bool = false
    ) {
        self.key = key
        self.type = type
        self.required = required
        self.optionalRole = optionalRole
        self.description = description
        self.enumValues = enumValues
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.objectProperties = objectProperties
        self.objectAdditionalProperties = objectAdditionalProperties
        self.arrayItemType = arrayItemType
        self.arrayItemProperties = arrayItemProperties
        self.arrayItemAdditionalProperties = arrayItemAdditionalProperties
    }
}

/// Canonical external request keys owned by The Fence.
public enum FenceParameterKey: String, CaseIterable, Sendable {
    case absent
    case action
    case angle
    case app
    case centerX
    case centerY
    case command
    case count
    case cp1X
    case cp1Y
    case cp2X
    case cp2Y
    case currentHeistId
    case currentTextEndOffset
    case currentTextStartOffset
    case deleteSource = "delete_source"
    case detail
    case device
    case direction
    case duration
    case edge
    case elements
    case end
    case endX
    case endY
    case excludeTraits
    case expect
    case expectations
    case fps
    case heistId
    case identifier
    case inactivityTimeout = "inactivity_timeout"
    case input
    case label
    case matcher
    case maxDuration = "max_duration"
    case mode
    case newValue
    case oldValue
    case ordinal
    case output
    case points
    case policy
    case property
    case radius
    case rotor
    case rotorIndex
    case samplesPerSegment
    case scale
    case scope
    case segments
    case spread
    case start
    case startX
    case startY
    case steps
    case target
    case text
    case timeout
    case token
    case traits
    case type
    case value
    case velocity
    case x
    case y
}

public extension FenceParameterSpec {
    init(
        key: FenceParameterKey,
        type: ParamType,
        required: Bool = false,
        description: String? = nil,
        enumValues: [String]? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        objectProperties: [FenceParameterSpec] = [],
        objectAdditionalProperties: Bool = false,
        arrayItemType: ParamType? = nil,
        arrayItemProperties: [FenceParameterSpec] = [],
        arrayItemAdditionalProperties: Bool = false
    ) {
        self.init(
            key: key.rawValue,
            type: type,
            required: required,
            description: description,
            enumValues: enumValues,
            minimum: minimum,
            maximum: maximum,
            minLength: minLength,
            objectProperties: objectProperties,
            objectAdditionalProperties: objectAdditionalProperties,
            arrayItemType: arrayItemType,
            arrayItemProperties: arrayItemProperties,
            arrayItemAdditionalProperties: arrayItemAdditionalProperties
        )
    }
}

private func fenceEnumValues<E>(_ type: E.Type) -> [String] where E: CaseIterable & RawRepresentable, E.RawValue == String {
    type.allCases.map(\.rawValue)
}

// MARK: - MCP Exposure

/// How a command is surfaced in the MCP tool list.
///
/// Declared at module scope to avoid inheriting @ButtonHeistActor isolation.
public enum MCPExposure: Sendable, Equatable {
    /// Tool name equals command rawValue (1:1 mapping).
    case directTool
    /// Command is routed through a grouped tool (e.g. gestures via the "gesture" tool).
    case groupedUnder(String)
    /// Not exposed via MCP (REPL-only or subsumed by another command).
    case notExposed
}

/// Selector metadata for an MCP tool that routes to more than one Fence command.
///
/// This is part of the command contract because it defines the external tool
/// parameter that selects the canonical Fence command. The MCP adapter renders
/// it; runtime routing also consumes it.
public struct MCPToolSelector: Sendable, Equatable {
    public let parameter: FenceParameterSpec
    public let defaultValue: String?
    public let commandByValue: [String: TheFence.Command]
    public let consumedValues: Set<String>

    public init(
        parameter: FenceParameterSpec,
        defaultValue: String? = nil,
        commandByValue: [String: TheFence.Command],
        consumedValues: Set<String>? = nil
    ) {
        self.parameter = parameter
        self.defaultValue = defaultValue
        self.commandByValue = commandByValue
        self.consumedValues = consumedValues ?? Set(commandByValue.keys)
    }

    public func command(for value: String?) -> TheFence.Command? {
        guard let value else {
            guard let defaultValue else { return nil }
            return commandByValue[defaultValue]
        }
        return commandByValue[value]
    }

    public func selectorValue(for command: TheFence.Command) -> String? {
        let values = commandByValue.compactMap { $0.value == command ? $0.key : nil }
        return values.count == 1 ? values[0] : nil
    }

    public func consumesValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return consumedValues.contains(value)
    }
}

/// MCP annotation metadata owned by the canonical tool contract.
///
/// The MCP adapter translates this neutral spec into SDK-specific annotation
/// values without owning the command-name lists that receive those annotations.
public struct MCPToolAnnotationSpec: Sendable, Equatable {
    public let readOnlyHint: Bool?
    public let idempotentHint: Bool?

    public init(
        readOnlyHint: Bool? = nil,
        idempotentHint: Bool? = nil
    ) {
        self.readOnlyHint = readOnlyHint
        self.idempotentHint = idempotentHint
    }
}

/// Canonical MCP-facing tool contract derived from the Fence command catalog.
///
/// MCP adapters render tool metadata and schemas from this contract instead of
/// hand-maintaining command-name or parameter-name mirrors.
public struct MCPToolContract: Sendable, Equatable {
    public let name: String
    public let commands: [TheFence.Command]
    public let selector: MCPToolSelector?
    public let description: String
    public let annotations: MCPToolAnnotationSpec?

    public init(
        name: String,
        commands: [TheFence.Command],
        selector: MCPToolSelector? = nil,
        description: String,
        annotations: MCPToolAnnotationSpec? = nil
    ) {
        self.name = name
        self.commands = commands
        self.selector = selector
        self.description = description
        self.annotations = annotations
    }

    public var parameters: [FenceParameterSpec] {
        var merged: [FenceParameterSpec] = []
        for spec in commands.flatMap(\.parameters) {
            append(spec, to: &merged, replacingExisting: false)
        }
        if let selector {
            append(selector.parameter, to: &merged, replacingExisting: true)
        }
        return merged
    }

    public var requiredParameterKeys: [String] {
        if let selector {
            // Selector tools flatten several command shapes into one Claude-compatible
            // schema. Requiring command-specific keys here would overconstrain other
            // selector values without JSON Schema composition.
            return selector.parameter.required ? [selector.parameter.key] : []
        }
        return parameters.filter(\.required).map(\.key)
    }

    private func append(
        _ spec: FenceParameterSpec,
        to specs: inout [FenceParameterSpec],
        replacingExisting: Bool
    ) {
        guard let existingIndex = specs.firstIndex(where: { $0.key == spec.key }) else {
            specs.append(spec)
            return
        }
        if replacingExisting {
            specs[existingIndex] = spec
        }
    }
}

// MARK: - CLI Exposure

/// How a command is surfaced by the top-level `buttonheist` CLI.
///
/// Declared next to `MCPExposure` so command-surface contracts live with the
/// command catalog instead of being reverse-engineered from docs.
public enum CLIExposure: Sendable, Equatable {
    /// Top-level CLI command name equals the command raw value.
    case directCommand
    /// Command is routed through another top-level command.
    case groupedUnder(String)
    /// Only accepted by the interactive session parser or raw JSON mode.
    case sessionOnly
    /// Not exposed by the CLI.
    case notExposed
}

// MARK: - Shared Parameter Blocks

/// Reusable parameter groups shared across command specs.
/// At module scope so they're not actor-isolated.
enum FenceParameterBlocks: Sendable {

    /// Element targeting: heistId, label, value, traits, excludeTraits, identifier, ordinal.
    /// Used by action/gesture/scroll commands that call `elementTarget(args)`.
    static let elementTarget: [FenceParameterSpec] = [
        .init(
            key: "heistId", type: .string, optionalRole: .matcher,
            description: "Current-hierarchy heistId handle returned by get_interface or an action delta. Use matchers for durable flows."
        ),
        .init(key: "label", type: .string, optionalRole: .matcher, description: "Accessibility label — the text VoiceOver reads (e.g. \"Sign In\")"),
        .init(key: "value", type: .string, optionalRole: .matcher, description: "Accessibility value — current state or placeholder (e.g. \"50%\")"),
        .init(
            key: "traits", type: .stringArray, optionalRole: .matcher,
            description: "Required traits (role qualifiers like button, header, selected). All must match."
        ),
        .init(key: "excludeTraits", type: .stringArray, optionalRole: .matcher, description: "Traits that must NOT be present"),
        .init(key: "identifier", type: .string, optionalRole: .matcher, description: "accessibilityIdentifier (escape hatch — prefer label/value/traits)"),
        .init(
            key: "ordinal", type: .integer, optionalRole: .matcher,
            description: """
                0-based index to disambiguate when multiple elements match. \
                0 = first match, 1 = second, etc. in the returned hierarchy order. \
                Omit to require a unique match — ambiguity errors show the valid range.
                """
        ),
    ]

    /// Element filtering: label, value, traits, excludeTraits, identifier (no heistId/ordinal).
    /// Used by get_interface when filtering returned interface elements.
    static let elementFilter: [FenceParameterSpec] = [
        .init(key: "label", type: .string, optionalRole: .matcher, description: "Accessibility label — the text VoiceOver reads (e.g. \"Sign In\")"),
        .init(key: "value", type: .string, optionalRole: .matcher, description: "Accessibility value — current state or placeholder (e.g. \"50%\")"),
        .init(
            key: "traits", type: .stringArray, optionalRole: .matcher,
            description: "Required traits (role qualifiers like button, header, selected). All must match."
        ),
        .init(key: "excludeTraits", type: .stringArray, optionalRole: .matcher, description: "Traits that must NOT be present"),
        .init(key: "identifier", type: .string, optionalRole: .matcher, description: "accessibilityIdentifier (escape hatch — prefer label/value/traits)"),
    ]

    /// Inline expectation for action commands.
    static let expect: FenceParameterSpec = .init(
        key: "expect", type: .object, optionalRole: .behaviorSwitch,
        description: """
            Inline verification for this action. Use {"type": "screen_changed"} or \
            {"type": "elements_changed"} for simple expectations, or object forms like \
            {"type": "element_updated"|"element_appeared"|"element_disappeared"|"compound", ...}. \
            See docs/MCP-AGENT-GUIDE.md for the full expectation vocabulary and recipes.
            """,
        objectProperties: [
            .init(
                key: "type", type: .string, required: true,
                description: "Object-form discriminator, such as screen_changed or element_updated.",
                enumValues: ActionExpectation.wireTypeValues
            ),
            .init(key: "heistId", type: .string, optionalRole: .matcher, description: "element_updated: match a specific element"),
            .init(
                key: "property", type: .string, optionalRole: .payload,
                description: "element_updated: match a specific property",
                enumValues: fenceEnumValues(ElementProperty.self)
            ),
            .init(key: "oldValue", type: .string, optionalRole: .payload, description: "element_updated: expected previous value"),
            .init(key: "newValue", type: .string, optionalRole: .payload, description: "element_updated: expected new value"),
            .init(
                key: "matcher", type: .object, optionalRole: .matcher,
                description: "element_appeared / element_disappeared: predicate identifying the element",
                objectProperties: [
                    .init(key: "label", type: .string, optionalRole: .matcher),
                    .init(key: "identifier", type: .string, optionalRole: .matcher),
                    .init(key: "value", type: .string, optionalRole: .matcher),
                    .init(key: "traits", type: .stringArray, optionalRole: .matcher),
                    .init(key: "excludeTraits", type: .stringArray, optionalRole: .matcher),
                ]
            ),
            .init(
                key: "expectations", type: .array, optionalRole: .payload,
                description: "compound: array of sub-expectation objects",
                arrayItemType: .object,
                arrayItemProperties: [
                    .init(
                        key: "type", type: .string, required: true,
                        enumValues: ActionExpectation.wireTypeValues
                    ),
                ],
                arrayItemAdditionalProperties: true
            ),
        ]
    )

    static let expectationTimeout: FenceParameterSpec = .init(
        key: "timeout", type: .number, optionalRole: .behaviorSwitch,
        description: "Max seconds to wait for the expectation when expect is provided (default: 10, max: 30)",
        maximum: 30
    )

    static let expectation: [FenceParameterSpec] = [expect, expectationTimeout]

    static let unitPoint: [FenceParameterSpec] = [
        .init(key: "x", type: .number, required: true, description: "X position (0-1)"),
        .init(key: "y", type: .number, required: true, description: "Y position (0-1)"),
    ]
}

// MARK: - Per-Command Specs

extension TheFence.Command {

    public static let gestureMCPToolName = "gesture"

    public var cliExposure: CLIExposure {
        switch self {
        case .help, .quit, .exit, .status:
            return .sessionOnly

        case .increment, .decrement, .performCustomAction:
            return .groupedUnder(Self.activate.rawValue)

        default:
            return .directCommand
        }
    }

    public var mcpExposure: MCPExposure {
        switch self {
        // REPL-only
        case .help, .quit, .exit, .status:
            return .notExposed

        // Subsumed: increment/decrement/performCustomAction are handled by activate's "action" param
        case .increment, .decrement, .performCustomAction:
            return .notExposed

        // Subsumed: dismiss_keyboard is handled by edit_action's "dismiss" action
        case .dismissKeyboard:
            return .groupedUnder(Self.editAction.rawValue)

        // Grouped under "gesture" (including swipe)
        case .swipe, .oneFingerTap, .longPress, .drag, .pinch, .rotate, .twoFingerTap,
             .drawPath, .drawBezier:
            return .groupedUnder(Self.gestureMCPToolName)

        // Grouped under "scroll"
        case .scrollToVisible, .elementSearch, .scrollToEdge:
            return .groupedUnder(Self.scroll.rawValue)

        // Everything else is a direct 1:1 tool
        default:
            return .directTool
        }
    }

    public static var mcpToolContracts: [MCPToolContract] {
        var toolNames: [String] = []
        var commandsByToolName: [String: [Self]] = [:]

        func append(_ command: Self, to toolName: String) {
            if commandsByToolName[toolName] == nil {
                toolNames.append(toolName)
                commandsByToolName[toolName] = []
            }
            commandsByToolName[toolName]?.append(command)
        }

        for command in allCases {
            switch command.mcpExposure {
            case .directTool:
                append(command, to: command.rawValue)
            case .groupedUnder(let toolName):
                append(command, to: toolName)
            case .notExposed:
                break
            }
        }

        return toolNames.compactMap { toolName in
            guard let commands = commandsByToolName[toolName] else { return nil }
            return MCPToolContract(
                name: toolName,
                commands: commands,
                selector: mcpSelector(for: toolName),
                description: mcpDescription(for: toolName),
                annotations: mcpAnnotations(for: toolName)
            )
        }
    }

    public static func mcpToolContract(named name: String) -> MCPToolContract? {
        mcpToolContracts.first { $0.name == name }
    }

    private static func mcpSelector(for toolName: String) -> MCPToolSelector? {
        switch toolName {
        case Self.gestureMCPToolName:
            return MCPToolSelector(
                parameter: .init(
                    key: "type", type: .string, required: true,
                    description: "Gesture type",
                    enumValues: fenceEnumValues(GestureType.self)
                ),
                commandByValue: Dictionary(uniqueKeysWithValues: GestureType.allCases.compactMap { gestureType in
                    Self(rawValue: gestureType.rawValue).map { (gestureType.rawValue, $0) }
                })
            )

        case Self.scroll.rawValue:
            return MCPToolSelector(
                parameter: .init(
                    key: "mode", type: .string, optionalRole: .behaviorSwitch,
                    description: "Scroll mode (default: page)",
                    enumValues: fenceEnumValues(ScrollMode.self)
                ),
                defaultValue: ScrollMode.page.rawValue,
                commandByValue: Dictionary(uniqueKeysWithValues: ScrollMode.allCases.compactMap { mode in
                    Self(rawValue: mode.canonicalCommand).map { (mode.rawValue, $0) }
                })
            )

        case Self.editAction.rawValue:
            let dismissValue = "dismiss"
            return MCPToolSelector(
                parameter: .init(
                    key: "action", type: .string, required: true,
                    description: "Action to perform",
                    enumValues: fenceEnumValues(EditAction.self) + [dismissValue]
                ),
                commandByValue: Dictionary(uniqueKeysWithValues:
                    EditAction.allCases.map { ($0.rawValue, Self.editAction) } +
                        [(dismissValue, Self.dismissKeyboard)]
                ),
                consumedValues: [dismissValue]
            )

        default:
            return nil
        }
    }

    private static func mcpAnnotations(for toolName: String) -> MCPToolAnnotationSpec? {
        switch toolName {
        case Self.getInterface.rawValue,
             Self.getScreen.rawValue,
             Self.listDevices.rawValue,
             Self.getSessionState.rawValue,
             Self.listTargets.rawValue,
             Self.getSessionLog.rawValue:
            return MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)

        case Self.waitForChange.rawValue,
             Self.getPasteboard.rawValue:
            return MCPToolAnnotationSpec(readOnlyHint: true)

        default:
            return nil
        }
    }

    private static func mcpDescription(for toolName: String) -> String {
        mcpObservationDescription(for: toolName) ??
            mcpInteractionDescription(for: toolName) ??
            mcpSessionDescription(for: toolName) ??
            "Execute the \(toolName) Button Heist tool."
    }

    private static func mcpObservationDescription(for toolName: String) -> String? {
        switch toolName {
        case Self.getInterface.rawValue:
            return """
                Read the app accessibility hierarchy. Omitted scope is the normal product state; \
                call once on a new screen, then track changes via \
                action deltas — re-fetch only when you need elements the delta didn't cover. \
                Filter with matcher fields or heistId handle list. Omit scope for the normal \
                app accessibility state; use scope=visible only for fresh on-screen geometry diagnostics.
                """

        case Self.getScreen.rawValue:
            return "Capture a PNG screenshot from the connected device. Returns inline base64 PNG image data. Use 'output' to save to a file path instead."

        case Self.waitForChange.rawValue:
            return """
                Wait for the UI to change. With no expect, returns on any tree change. With expect, \
                rides through intermediate states (spinners, loading) until the expectation is met. \
                Use after an action whose delta showed a transient state and the expectation wasn't met yet.
                """

        case Self.waitFor.rawValue:
            return """
                Wait for an element matching a predicate to appear, or to disappear with absent=true. \
                Polls on UI settle events. Returns the matched element or diagnostic info on timeout.
                """

        default:
            return nil
        }
    }

    private static func mcpInteractionDescription(for toolName: String) -> String? {
        switch toolName {
        case Self.activate.rawValue:
            return """
                Activate a UI element (VoiceOver-style double-tap): tap buttons, follow links, toggle \
                controls. Pass 'action' to invoke a named action like "increment", "decrement", or \
                any entry from the element's actions array.
                """

        case Self.rotor.rawValue:
            return """
                Move through a rotor exposed by an element. Defaults to next. Use rotors listed by \
                get_interface to pick rotor or rotorIndex; pass currentHeistId from the previous \
                object result to continue like a VoiceOver user. For text-range results, also pass \
                the returned start and end offsets.
                """

        case Self.typeText.rawValue:
            return """
                Type non-empty text via keyboard injection. Optionally target an \
                element to focus it first and read back the resulting value.
                """

        case Self.scroll.rawValue:
            return """
                Scroll within scroll views. mode=page scrolls one page in 'direction'; \
                mode=to_visible brings a known element into view; mode=search scrolls until a \
                matching element is found; mode=to_edge scrolls to a top/bottom/left/right edge.
                """

        case Self.gestureMCPToolName:
            return """
                Perform a touch gesture. Prefer 'activate' for element interactions — gestures are for \
                swipes, drags, pinches, rotates, and free-form path drawing. Set 'type' to one of: \
                swipe, one_finger_tap, drag, long_press, pinch, rotate, two_finger_tap, draw_path, draw_bezier.
                """

        case Self.editAction.rawValue:
            return """
                Perform an edit or keyboard action on the current first responder. \
                Actions: copy, paste, cut, select, selectAll, delete, dismiss (dismiss the keyboard).
                """

        case Self.setPasteboard.rawValue:
            return """
                Write text to the general pasteboard from within the app. Content written by the app \
                itself does not trigger the iOS "Allow Paste" dialog when subsequently read.
                """

        case Self.getPasteboard.rawValue:
            return """
                Read text from the general pasteboard. iOS may show "Allow Paste" if the content \
                was written by another app.
                """

        default:
            return nil
        }
    }

    private static func mcpSessionDescription(for toolName: String) -> String? {
        switch toolName {
        case Self.startRecording.rawValue:
            return "Start an H.264/MP4 screen recording. Recording runs until max duration unless inactivity_timeout is explicitly supplied."

        case Self.stopRecording.rawValue:
            return """
                Stop an in-progress screen recording. Returns metadata only by default (raw video \
                is too large for MCP context); pass 'output' to save the MP4 to a file path.
                """

        case Self.listDevices.rawValue:
            return """
                List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. \
                Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.
                """

        case Self.getSessionState.rawValue:
            return """
                Inspect the current Button Heist session: connection status, device/app identity, \
                recording state, client timeouts, and a lightweight summary of the last action.
                """

        case Self.connect.rawValue:
            return """
                Establish or switch the active connection to an iOS app with Button Heist enabled. \
                Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or \
                BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. \
                Returns session state; call get_interface explicitly to observe UI hierarchy.
                """

        case Self.listTargets.rawValue:
            return """
                List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), \
                including each target's address and which one is the default.
                """

        case Self.runBatch.rawValue:
            return """
                Execute multiple commands in one call. Each step is a JSON object with 'command' set \
                to a canonical TheFence.Command name plus that command's parameters; grouped MCP tool \
                names and selector shapes are not accepted inside batches. Attach 'expect' per step to verify \
                inline. Returns ordered per-step results. \
                policy=stop_on_error (default) or continue_on_error.
                """

        case Self.getSessionLog.rawValue:
            return "Return the current session manifest: commands executed and artifacts produced."

        case Self.archiveSession.rawValue:
            return "Close and compress the current session into a .tar.gz archive; returns the path."

        case Self.startHeist.rawValue:
            return """
                Start recording a heist. Successful commands become steps in a .heist file; \
                use matcher fields (label, identifier, traits) for durable element targeting, not heistId. \
                Attach 'expect' to validate outcomes during playback.
                """

        case Self.stopHeist.rawValue:
            return """
                Stop recording and save the heist as a self-contained JSON playback script. \
                Returns the file path and step count. At least one step must have been recorded.
                """

        case Self.playHeist.rawValue:
            return """
                Play back a .heist file. Steps execute sequentially; playback stops on the first \
                failed step. On failure, returns full diagnostics: command, target, error, action \
                result, expectation result, and a complete interface snapshot at the failure point.
                """

        default:
            return nil
        }
    }

    /// All parameter keys this command extracts from the request dictionary.
    /// Does not include the "command" key itself or internal keys like "_requestId".
    public var parameters: [FenceParameterSpec] {
        let target = FenceParameterBlocks.elementTarget
        let filter = FenceParameterBlocks.elementFilter
        let expect = FenceParameterBlocks.expect
        let expectation = FenceParameterBlocks.expectation

        switch self {

        // MARK: No parameters (meta / read-only)
        case .help, .quit, .exit, .status, .listDevices, .getSessionState,
             .listTargets, .getSessionLog:
            return []

        // These take no targeting parameters but accept expect
        case .dismissKeyboard:
            return expectation

        // MARK: Interface / observation
        case .getInterface:
            return filter + [
                .init(
                    key: "scope", type: .string, optionalRole: .behaviorSwitch,
                    description: """
                        Optional diagnostic scope. Omit for the app accessibility state. \
                        Use visible only when you need fresh on-screen geometry diagnostics.
                        """,
                    enumValues: [GetInterfaceScope.visible.rawValue]
                ),
                .init(
                    key: "detail", type: .string, optionalRole: .behaviorSwitch,
                    description: """
                        Level of detail. summary (default): identity fields, traits, and actions only \
                        — no hint, customContent, frames, or activation points. full: adds VoiceOver \
                        hint, customContent, frame, and activation point.
                        """,
                    enumValues: fenceEnumValues(InterfaceDetail.self)
                ),
                .init(
                    key: "elements", type: .stringArray, optionalRole: .matcher,
                    description: "Optional list of heistId handles to filter. Returns only matching elements. Omit for the app accessibility hierarchy."
                ),
            ]

        case .getScreen:
            return [
                .init(key: "output", type: .string, optionalRole: .payload, description: "File path to save PNG (omit for inline base64)"),
            ]

        case .waitForChange:
            return [
                expect,
                .init(
                    key: "timeout", type: .number, optionalRole: .behaviorSwitch,
                    description: "Maximum wait time in seconds (default: 30, max: 30)",
                    maximum: 30
                ),
            ]

        // MARK: Gestures
        case .oneFingerTap:
            return target + [
                .init(key: "x", type: .number, optionalRole: .payload, description: "X coordinate"),
                .init(key: "y", type: .number, optionalRole: .payload, description: "Y coordinate"),
            ] + expectation

        case .longPress:
            return target + [
                .init(key: "x", type: .number, optionalRole: .payload, description: "X coordinate"),
                .init(key: "y", type: .number, optionalRole: .payload, description: "Y coordinate"),
                .init(key: "duration", type: .number, optionalRole: .payload, description: "Duration in seconds (default 0.5)"),
            ] + expectation

        case .swipe:
            return target + [
                .init(
                    key: "direction", type: .string, optionalRole: .payload,
                    description: "Swipe direction: up, down, left, right",
                    enumValues: fenceEnumValues(SwipeDirection.self)
                ),
                .init(
                    key: "start", type: .object, optionalRole: .payload,
                    description: "Swipe start unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    objectProperties: FenceParameterBlocks.unitPoint
                ),
                .init(
                    key: "end", type: .object, optionalRole: .payload,
                    description: "Swipe end unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    objectProperties: FenceParameterBlocks.unitPoint
                ),
                .init(key: "startX", type: .number, optionalRole: .payload, description: "Start X coordinate (swipe, draw_bezier)"),
                .init(key: "startY", type: .number, optionalRole: .payload, description: "Start Y coordinate (swipe, draw_bezier)"),
                .init(key: "endX", type: .number, optionalRole: .payload, description: "End X coordinate (swipe, drag)"),
                .init(key: "endY", type: .number, optionalRole: .payload, description: "End Y coordinate (swipe, drag)"),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (swipe, long_press default 0.5, draw_path, draw_bezier)"
                ),
            ] + expectation

        case .drag:
            return target + [
                .init(key: "endX", type: .number, required: true, description: "End X coordinate (swipe, drag)"),
                .init(key: "endY", type: .number, required: true, description: "End Y coordinate (swipe, drag)"),
                .init(key: "startX", type: .number, optionalRole: .payload, description: "Start X coordinate (swipe, draw_bezier)"),
                .init(key: "startY", type: .number, optionalRole: .payload, description: "Start Y coordinate (swipe, draw_bezier)"),
                .init(key: "duration", type: .number, optionalRole: .payload, description: "Duration in seconds"),
            ] + expectation

        case .pinch:
            return target + [
                .init(key: "scale", type: .number, required: true, description: "Pinch scale factor (>1 zoom in, <1 zoom out)"),
                .init(
                    key: "centerX", type: .number, optionalRole: .payload,
                    description: "Center X (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(
                    key: "centerY", type: .number, optionalRole: .payload,
                    description: "Center Y (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(key: "spread", type: .number, optionalRole: .payload, description: "Finger spread distance (pinch, two_finger_tap)"),
                .init(key: "duration", type: .number, optionalRole: .payload, description: "Duration in seconds"),
            ] + expectation

        case .rotate:
            return target + [
                .init(key: "angle", type: .number, required: true, description: "Rotation angle in radians"),
                .init(
                    key: "centerX", type: .number, optionalRole: .payload,
                    description: "Center X (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(
                    key: "centerY", type: .number, optionalRole: .payload,
                    description: "Center Y (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(key: "radius", type: .number, optionalRole: .payload, description: "Rotation radius (rotate)"),
                .init(key: "duration", type: .number, optionalRole: .payload, description: "Duration in seconds"),
            ] + expectation

        case .twoFingerTap:
            return target + [
                .init(
                    key: "centerX", type: .number, optionalRole: .payload,
                    description: "Center X (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(
                    key: "centerY", type: .number, optionalRole: .payload,
                    description: "Center Y (pinch, rotate, two_finger_tap; defaults to element center)"
                ),
                .init(key: "spread", type: .number, optionalRole: .payload, description: "Finger spread distance (pinch, two_finger_tap)"),
            ] + expectation

        case .drawPath:
            return [
                .init(
                    key: "points", type: .array, required: true,
                    description: "Array of {x, y} waypoints (draw_path)",
                    arrayItemType: .object,
                    arrayItemProperties: [
                        .init(key: "x", type: .number, required: true, description: "X coordinate"),
                        .init(key: "y", type: .number, required: true, description: "Y coordinate"),
                    ]
                ),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (swipe, long_press default 0.5, draw_path, draw_bezier)"
                ),
                .init(key: "velocity", type: .number, optionalRole: .payload, description: "Drawing velocity in points/sec (draw_path, draw_bezier)"),
            ] + expectation

        case .drawBezier:
            return [
                .init(key: "startX", type: .number, required: true, description: "Start X coordinate (swipe, draw_bezier)"),
                .init(key: "startY", type: .number, required: true, description: "Start Y coordinate (swipe, draw_bezier)"),
                .init(
                    key: "segments", type: .array, required: true,
                    description: "Array of bezier segments: {cp1X, cp1Y, cp2X, cp2Y, endX, endY} (draw_bezier)",
                    arrayItemType: .object,
                    arrayItemProperties: [
                        .init(key: "cp1X", type: .number, required: true, description: "First control point X coordinate"),
                        .init(key: "cp1Y", type: .number, required: true, description: "First control point Y coordinate"),
                        .init(key: "cp2X", type: .number, required: true, description: "Second control point X coordinate"),
                        .init(key: "cp2Y", type: .number, required: true, description: "Second control point Y coordinate"),
                        .init(key: "endX", type: .number, required: true, description: "Segment end X coordinate"),
                        .init(key: "endY", type: .number, required: true, description: "Segment end Y coordinate"),
                    ]
                ),
                .init(key: "samplesPerSegment", type: .integer, optionalRole: .payload, description: "Bezier curve sampling resolution (draw_bezier)"),
                .init(
                    key: "duration", type: .number, optionalRole: .payload,
                    description: "Duration in seconds (swipe, long_press default 0.5, draw_path, draw_bezier)"
                ),
                .init(key: "velocity", type: .number, optionalRole: .payload, description: "Drawing velocity in points/sec (draw_path, draw_bezier)"),
            ] + expectation

        // MARK: Scroll
        case .scroll:
            return target + [
                .init(
                    key: "direction", type: .string, required: true,
                    description: """
                        Scroll direction. next/previous are page-only directions for mode=page; \
                        mode=search accepts only up, down, left, right and is validated server-side.
                        """,
                    enumValues: fenceEnumValues(ScrollDirection.self)
                ),
            ] + expectation

        case .scrollToVisible:
            return target + expectation

        case .elementSearch:
            return target + [
                .init(
                    key: "direction", type: .string, optionalRole: .payload,
                    description: "Scroll search direction: down, up, left, right",
                    enumValues: fenceEnumValues(ScrollSearchDirection.self)
                ),
            ] + expectation

        case .scrollToEdge:
            return target + [
                .init(
                    key: "edge", type: .string, required: true,
                    description: "Edge to scroll to (required for mode to_edge)",
                    enumValues: fenceEnumValues(ScrollEdge.self)
                ),
            ] + expectation

        // MARK: Accessibility actions
        case .activate:
            return target + [
                .init(
                    key: "action", type: .string, optionalRole: .payload,
                    description: "Named action (e.g. \"increment\", \"decrement\", or a custom action name)"
                ),
                .init(
                    key: "count", type: .integer, optionalRole: .behaviorSwitch,
                    description: "Repeat increment/decrement this many times. Omit for 1.",
                    minimum: 1,
                    maximum: 100
                ),
            ] + expectation

        case .increment, .decrement:
            return target + [
                .init(
                    key: "count", type: .integer, optionalRole: .behaviorSwitch,
                    description: "Repeat increment/decrement this many times. Omit for 1.",
                    minimum: 1,
                    maximum: 100
                ),
            ] + expectation

        case .performCustomAction:
            return target + [
                .init(key: "action", type: .string, required: true, description: "Custom accessibility action name"),
            ] + expectation

        case .rotor:
            return target + [
                .init(key: "rotor", type: .string, optionalRole: .payload, description: "Rotor name from the element's rotors list"),
                .init(
                    key: "rotorIndex", type: .integer, optionalRole: .payload,
                    description: "Zero-based rotor index when names are omitted or ambiguous",
                    minimum: 0
                ),
                .init(
                    key: "direction", type: .string, optionalRole: .payload,
                    description: "Rotor movement direction. Defaults to next.",
                    enumValues: fenceEnumValues(RotorDirection.self)
                ),
                .init(
                    key: "currentHeistId", type: .string, optionalRole: .payload,
                    description: "Optional current item heistId; pass the previous result to continue through a rotor"
                ),
                .init(
                    key: "currentTextStartOffset", type: .integer, optionalRole: .payload,
                    description: "Current text-range start offset for continuing through text-range rotor results",
                    minimum: 0
                ),
                .init(
                    key: "currentTextEndOffset", type: .integer, optionalRole: .payload,
                    description: "Current text-range end offset for continuing through text-range rotor results",
                    minimum: 0
                ),
            ] + expectation

        // MARK: Text / keyboard
        case .typeText:
            return target + [
                .init(key: "text", type: .string, required: true, description: "Text to type character-by-character", minLength: 1),
            ] + expectation

        case .editAction:
            return [
                .init(
                    key: "action", type: .string, required: true,
                    description: "Action to perform",
                    enumValues: fenceEnumValues(EditAction.self)
                ),
            ] + expectation

        // MARK: Pasteboard
        case .setPasteboard:
            return [
                .init(key: "text", type: .string, required: true, description: "Text to write to the pasteboard"),
            ] + expectation

        case .getPasteboard:
            return expectation

        // MARK: Wait
        case .waitFor:
            return target + [
                .init(key: "absent", type: .boolean, optionalRole: .behaviorSwitch, description: "Wait for element to NOT exist (default: false)"),
                .init(
                    key: "timeout", type: .number, optionalRole: .behaviorSwitch,
                    description: "Max seconds to wait (default: 10, max: 30)",
                    maximum: 30
                ),
                expect,
            ]

        // MARK: Recording
        case .startRecording:
            return [
                .init(key: "fps", type: .integer, optionalRole: .payload, description: "Frames per second (default: 8, range: 1-15)", minimum: 1, maximum: 15),
                .init(
                    key: "scale", type: .number, optionalRole: .payload,
                    description: "Resolution scale factor (default: 1.0, range: 0.25-1.0)",
                    minimum: 0.25,
                    maximum: 1.0
                ),
                .init(key: "max_duration", type: .number, optionalRole: .payload, description: "Maximum recording duration in seconds (default: 60)"),
                .init(
                    key: "inactivity_timeout", type: .number, optionalRole: .behaviorSwitch,
                    description: "Optional early-stop after N seconds of no interactions; omitted disables inactivity auto-stop"
                ),
            ]

        case .stopRecording:
            return [
                .init(key: "output", type: .string, optionalRole: .payload, description: "File path to save MP4 (metadata-only response if omitted)"),
            ]

        // MARK: Batch
        case .runBatch:
            return [
                .init(
                    key: "steps", type: .array, required: true,
                    description: "Ordered list of batch-executable canonical Fence command requests to execute",
                    arrayItemType: .object,
                    arrayItemProperties: [
                        .init(
                            key: "command", type: .string, required: true,
                            description: "Canonical TheFence.Command name (e.g. activate, swipe, element_search, dismiss_keyboard). " +
                                "Grouped MCP tool names and selector shapes are not accepted inside batches.",
                            enumValues: Self.batchExecutableCases.map(\.rawValue)
                        ),
                        expect,
                    ],
                    arrayItemAdditionalProperties: true
                ),
                .init(
                    key: "policy", type: .string, optionalRole: .behaviorSwitch,
                    description: "Batch policy: stop_on_error (default) or continue_on_error",
                    enumValues: fenceEnumValues(TheFence.BatchPolicy.self)
                ),
            ]

        // MARK: Connection
        case .connect:
            return [
                .init(key: "target", type: .string, optionalRole: .matcher, description: "Named target from .buttonheist.json config file"),
                .init(key: "device", type: .string, optionalRole: .matcher, description: "Direct host:port address (e.g. 127.0.0.1:1455)"),
                .init(key: "token", type: .string, optionalRole: .payload, description: "Auth token (overrides config file token if both provided)"),
            ]

        // MARK: Session management
        case .archiveSession:
            return [
                .init(
                    key: "delete_source", type: .boolean, optionalRole: .behaviorSwitch,
                    description: "Delete the session directory after archiving (default: false)"
                ),
            ]

        case .startHeist:
            return [
                .init(
                    key: "app", type: .string, optionalRole: .payload,
                    description: "Bundle ID of the app being recorded (default: \(Defaults.demoAppBundleID))"
                ),
                .init(
                    key: "identifier", type: .string, optionalRole: .payload,
                    description: "Session name for the recording (default: heist). Used as directory name if a new session is created."
                ),
            ]

        case .stopHeist:
            return [
                .init(key: "output", type: .string, required: true, description: "File path to write the .heist file"),
            ]

        case .playHeist:
            return [
                .init(key: "input", type: .string, required: true, description: "Path to the .heist file to play back"),
            ]
        }
    }
}
