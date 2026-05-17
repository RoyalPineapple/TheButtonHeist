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

    // MARK: - Properties

    public let key: String
    public let type: ParamType
    public let required: Bool
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
            key: "heistId", type: .string,
            description: "Current-hierarchy heistId handle returned by get_interface or an action delta. Use matchers for durable flows."
        ),
        .init(key: "label", type: .string, description: "Accessibility label — the text VoiceOver reads (e.g. \"Sign In\")"),
        .init(key: "value", type: .string, description: "Accessibility value — current state or placeholder (e.g. \"50%\")"),
        .init(
            key: "traits", type: .stringArray,
            description: "Required traits (role qualifiers like button, header, selected). All must match."
        ),
        .init(key: "excludeTraits", type: .stringArray, description: "Traits that must NOT be present"),
        .init(key: "identifier", type: .string, description: "accessibilityIdentifier (escape hatch — prefer label/value/traits)"),
        .init(
            key: "ordinal", type: .integer,
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
        .init(key: "label", type: .string, description: "Accessibility label — the text VoiceOver reads (e.g. \"Sign In\")"),
        .init(key: "value", type: .string, description: "Accessibility value — current state or placeholder (e.g. \"50%\")"),
        .init(
            key: "traits", type: .stringArray,
            description: "Required traits (role qualifiers like button, header, selected). All must match."
        ),
        .init(key: "excludeTraits", type: .stringArray, description: "Traits that must NOT be present"),
        .init(key: "identifier", type: .string, description: "accessibilityIdentifier (escape hatch — prefer label/value/traits)"),
    ]

    /// Inline expectation for action commands.
    static let expect: FenceParameterSpec = .init(
        key: "expect", type: .object,
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
            .init(key: "heistId", type: .string, description: "element_updated: match a specific element"),
            .init(
                key: "property", type: .string,
                description: "element_updated: match a specific property",
                enumValues: fenceEnumValues(ElementProperty.self)
            ),
            .init(key: "oldValue", type: .string, description: "element_updated: expected previous value"),
            .init(key: "newValue", type: .string, description: "element_updated: expected new value"),
            .init(
                key: "matcher", type: .object,
                description: "element_appeared / element_disappeared: predicate identifying the element",
                objectProperties: [
                    .init(key: "label", type: .string),
                    .init(key: "identifier", type: .string),
                    .init(key: "value", type: .string),
                    .init(key: "traits", type: .stringArray),
                    .init(key: "excludeTraits", type: .stringArray),
                ]
            ),
            .init(
                key: "expectations", type: .array,
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

    static let unitPoint: [FenceParameterSpec] = [
        .init(key: "x", type: .number, required: true, description: "X position (0-1)"),
        .init(key: "y", type: .number, required: true, description: "Y position (0-1)"),
    ]
}

// MARK: - Per-Command Specs

extension TheFence.Command {

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
            return .groupedUnder("gesture")

        // Grouped under "scroll"
        case .scrollToVisible, .elementSearch, .scrollToEdge:
            return .groupedUnder(Self.scroll.rawValue)

        // Everything else is a direct 1:1 tool
        default:
            return .directTool
        }
    }

    /// All parameter keys this command extracts from the request dictionary.
    /// Does not include the "command" key itself or internal keys like "_requestId".
    public var parameters: [FenceParameterSpec] {
        let target = FenceParameterBlocks.elementTarget
        let filter = FenceParameterBlocks.elementFilter
        let expect = FenceParameterBlocks.expect

        switch self {

        // MARK: No parameters (meta / read-only)
        case .help, .quit, .exit, .status, .listDevices, .getSessionState,
             .listTargets, .getSessionLog:
            return []

        // These take no targeting parameters but accept expect
        case .dismissKeyboard:
            return [expect]

        // MARK: Interface / observation
        case .getInterface:
            return filter + [
                .init(
                    key: "scope", type: .string,
                    description: """
                        Optional diagnostic scope. Omit for the app accessibility state. \
                        Use visible only when you need a fresh on-screen parse for diagnostics \
                        or geometry checks.
                        """,
                    enumValues: [GetInterfaceScope.visible.rawValue]
                ),
                .init(
                    key: "detail", type: .string,
                    description: """
                        Level of detail. summary (default): identity fields, traits, and actions only \
                        — no hint, customContent, frames, or activation points. full: adds VoiceOver \
                        hint, customContent, frame, and activation point.
                        """,
                    enumValues: fenceEnumValues(InterfaceDetail.self)
                ),
                .init(
                    key: "elements", type: .stringArray,
                    description: "Optional list of heistId handles to filter. Returns only matching elements. Omit for the current interface hierarchy."
                ),
            ]

        case .getScreen:
            return [
                .init(key: "output", type: .string, description: "File path to save PNG (omit for inline base64)"),
            ]

        case .waitForChange:
            return [
                expect,
                .init(
                    key: "timeout", type: .number,
                    description: "Maximum wait time in seconds (default: 10, max: 30)",
                    maximum: 30
                ),
            ]

        // MARK: Gestures
        case .oneFingerTap:
            return target + [
                .init(key: "x", type: .number, description: "X coordinate"),
                .init(key: "y", type: .number, description: "Y coordinate"),
                expect,
            ]

        case .longPress:
            return target + [
                .init(key: "x", type: .number, description: "X coordinate"),
                .init(key: "y", type: .number, description: "Y coordinate"),
                .init(key: "duration", type: .number, description: "Duration in seconds (default 0.5)"),
                expect,
            ]

        case .swipe:
            return target + [
                .init(
                    key: "direction", type: .string,
                    description: "Swipe direction: up, down, left, right",
                    enumValues: fenceEnumValues(SwipeDirection.self)
                ),
                .init(
                    key: "start", type: .object,
                    description: "Swipe start unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    objectProperties: FenceParameterBlocks.unitPoint
                ),
                .init(
                    key: "end", type: .object,
                    description: "Swipe end unit point relative to element frame. (0,0)=top-left, (1,1)=bottom-right",
                    objectProperties: FenceParameterBlocks.unitPoint
                ),
                .init(key: "startX", type: .number, description: "Start X coordinate (swipe, draw_bezier)"),
                .init(key: "startY", type: .number, description: "Start Y coordinate (swipe, draw_bezier)"),
                .init(key: "endX", type: .number, description: "End X coordinate (swipe, drag)"),
                .init(key: "endY", type: .number, description: "End Y coordinate (swipe, drag)"),
                .init(key: "duration", type: .number, description: "Duration in seconds (swipe, long_press default 0.5, draw_path, draw_bezier)"),
                expect,
            ]

        case .drag:
            return target + [
                .init(key: "endX", type: .number, required: true, description: "End X coordinate (swipe, drag)"),
                .init(key: "endY", type: .number, required: true, description: "End Y coordinate (swipe, drag)"),
                .init(key: "startX", type: .number, description: "Start X coordinate (swipe, draw_bezier)"),
                .init(key: "startY", type: .number, description: "Start Y coordinate (swipe, draw_bezier)"),
                .init(key: "x", type: .number, description: "X coordinate"),
                .init(key: "y", type: .number, description: "Y coordinate"),
                .init(key: "duration", type: .number, description: "Duration in seconds"),
                expect,
            ]

        case .pinch:
            return target + [
                .init(key: "scale", type: .number, required: true, description: "Pinch scale factor (>1 zoom in, <1 zoom out)"),
                .init(key: "centerX", type: .number, description: "Center X (pinch, rotate, two_finger_tap — defaults to element center or x)"),
                .init(key: "centerY", type: .number, description: "Center Y (pinch, rotate, two_finger_tap — defaults to element center or y)"),
                .init(key: "x", type: .number, description: "X coordinate"),
                .init(key: "y", type: .number, description: "Y coordinate"),
                .init(key: "spread", type: .number, description: "Finger spread distance (pinch, two_finger_tap)"),
                .init(key: "duration", type: .number, description: "Duration in seconds"),
                expect,
            ]

        case .rotate:
            return target + [
                .init(key: "angle", type: .number, required: true, description: "Rotation angle in radians"),
                .init(key: "centerX", type: .number, description: "Center X (pinch, rotate, two_finger_tap — defaults to element center or x)"),
                .init(key: "centerY", type: .number, description: "Center Y (pinch, rotate, two_finger_tap — defaults to element center or y)"),
                .init(key: "x", type: .number, description: "X coordinate"),
                .init(key: "y", type: .number, description: "Y coordinate"),
                .init(key: "radius", type: .number, description: "Rotation radius (rotate)"),
                .init(key: "duration", type: .number, description: "Duration in seconds"),
                expect,
            ]

        case .twoFingerTap:
            return target + [
                .init(key: "centerX", type: .number, description: "Center X (pinch, rotate, two_finger_tap — defaults to element center or x)"),
                .init(key: "centerY", type: .number, description: "Center Y (pinch, rotate, two_finger_tap — defaults to element center or y)"),
                .init(key: "x", type: .number, description: "X coordinate"),
                .init(key: "y", type: .number, description: "Y coordinate"),
                .init(key: "spread", type: .number, description: "Finger spread distance (pinch, two_finger_tap)"),
                expect,
            ]

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
                .init(key: "duration", type: .number, description: "Duration in seconds (swipe, long_press default 0.5, draw_path, draw_bezier)"),
                .init(key: "velocity", type: .number, description: "Drawing velocity in points/sec (draw_path, draw_bezier)"),
                expect,
            ]

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
                .init(key: "samplesPerSegment", type: .integer, description: "Bezier curve sampling resolution (draw_bezier)"),
                .init(key: "duration", type: .number, description: "Duration in seconds (swipe, long_press default 0.5, draw_path, draw_bezier)"),
                .init(key: "velocity", type: .number, description: "Drawing velocity in points/sec (draw_path, draw_bezier)"),
                expect,
            ]

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
                expect,
            ]

        case .scrollToVisible:
            return target + [expect]

        case .elementSearch:
            return target + [
                .init(
                    key: "direction", type: .string,
                    description: "Scroll search direction: down, up, left, right",
                    enumValues: fenceEnumValues(ScrollSearchDirection.self)
                ),
                expect,
            ]

        case .scrollToEdge:
            return target + [
                .init(
                    key: "edge", type: .string, required: true,
                    description: "Edge to scroll to (required for mode to_edge)",
                    enumValues: fenceEnumValues(ScrollEdge.self)
                ),
                expect,
            ]

        // MARK: Accessibility actions
        case .activate:
            return target + [
                .init(key: "action", type: .string, description: "Named action (e.g. \"increment\", \"decrement\", or a custom action name)"),
                .init(
                    key: "count", type: .integer,
                    description: "Repeat increment/decrement this many times. Omit for 1.",
                    minimum: 1,
                    maximum: 100
                ),
                expect,
            ]

        case .increment, .decrement:
            return target + [
                .init(
                    key: "count", type: .integer,
                    description: "Repeat increment/decrement this many times. Omit for 1.",
                    minimum: 1,
                    maximum: 100
                ),
                expect,
            ]

        case .performCustomAction:
            return target + [
                .init(key: "action", type: .string, required: true, description: "Custom accessibility action name"),
                expect,
            ]

        case .rotor:
            return target + [
                .init(key: "rotor", type: .string, description: "Rotor name from the element's rotors list"),
                .init(key: "rotorIndex", type: .integer, description: "Zero-based rotor index when names are omitted or ambiguous", minimum: 0),
                .init(
                    key: "direction", type: .string,
                    description: "Rotor movement direction. Defaults to next.",
                    enumValues: fenceEnumValues(RotorDirection.self)
                ),
                .init(
                    key: "currentHeistId", type: .string,
                    description: "Optional current item heistId; pass the previous result to continue through a rotor"
                ),
                .init(
                    key: "currentTextStartOffset", type: .integer,
                    description: "Current text-range start offset for continuing through text-range rotor results",
                    minimum: 0
                ),
                .init(
                    key: "currentTextEndOffset", type: .integer,
                    description: "Current text-range end offset for continuing through text-range rotor results",
                    minimum: 0
                ),
                expect,
            ]

        // MARK: Text / keyboard
        case .typeText:
            return target + [
                .init(key: "text", type: .string, description: "Text to type character-by-character", minLength: 1),
                .init(key: "deleteCount", type: .integer, description: "Number of delete key taps before typing", minimum: 1),
                .init(key: "clearFirst", type: .boolean, description: "Clear all existing text before typing (select-all + delete)"),
                expect,
            ]

        case .editAction:
            return [
                .init(
                    key: "action", type: .string, required: true,
                    description: "Action to perform",
                    enumValues: fenceEnumValues(EditAction.self)
                ),
                expect,
            ]

        // MARK: Pasteboard
        case .setPasteboard:
            return [
                .init(key: "text", type: .string, required: true, description: "Text to write to the pasteboard"),
                expect,
            ]

        case .getPasteboard:
            return [expect]

        // MARK: Wait
        case .waitFor:
            return target + [
                .init(key: "absent", type: .boolean, description: "Wait for element to NOT exist (default: false)"),
                .init(
                    key: "timeout", type: .number,
                    description: "Max seconds to wait (default: 10, max: 30)",
                    maximum: 30
                ),
                expect,
            ]

        // MARK: Recording
        case .startRecording:
            return [
                .init(key: "fps", type: .integer, description: "Frames per second (default: 8, range: 1-15)", minimum: 1, maximum: 15),
                .init(key: "scale", type: .number, description: "Resolution scale factor (default: 1.0, range: 0.25-1.0)", minimum: 0.25, maximum: 1.0),
                .init(key: "max_duration", type: .number, description: "Maximum recording duration in seconds (default: 60)"),
                .init(key: "inactivity_timeout", type: .number, description: "Auto-stop after N seconds of no interactions (default: 5)"),
            ]

        case .stopRecording:
            return [
                .init(key: "output", type: .string, description: "File path to save MP4 (metadata-only response if omitted)"),
            ]

        // MARK: Batch
        case .runBatch:
            return [
                .init(
                    key: "steps", type: .array, required: true,
                    description: "Ordered list of raw Fence command requests to execute",
                    arrayItemType: .object,
                    arrayItemProperties: [
                        .init(
                            key: "command", type: .string, required: true,
                            description: "Raw TheFence.Command name (e.g. activate, swipe, element_search, dismiss_keyboard). " +
                                "Grouped MCP tool names and selector shapes are not accepted inside batches.",
                            enumValues: Self.batchExecutableCases.map(\.rawValue)
                        ),
                        expect,
                    ],
                    arrayItemAdditionalProperties: true
                ),
                .init(
                    key: "policy", type: .string,
                    description: "Batch policy: stop_on_error (default) or continue_on_error",
                    enumValues: fenceEnumValues(TheFence.BatchPolicy.self)
                ),
            ]

        // MARK: Connection
        case .connect:
            return [
                .init(key: "target", type: .string, description: "Named target from .buttonheist.json config file"),
                .init(key: "device", type: .string, description: "Direct host:port address (e.g. 127.0.0.1:1455)"),
                .init(key: "token", type: .string, description: "Auth token (overrides config file token if both provided)"),
            ]

        // MARK: Session management
        case .archiveSession:
            return [
                .init(key: "delete_source", type: .boolean, description: "Delete the session directory after archiving (default: false)"),
            ]

        case .startHeist:
            return [
                .init(key: "app", type: .string, description: "Bundle ID of the app being recorded"),
                .init(
                    key: "identifier", type: .string,
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
