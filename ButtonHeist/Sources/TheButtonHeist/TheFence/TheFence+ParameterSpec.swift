import Foundation

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

    // MARK: - Init

    public init(key: String, type: ParamType, required: Bool = false) {
        self.key = key
        self.type = type
        self.required = required
    }
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
public enum FenceParameterBlocks: Sendable {

    /// Element targeting: heistId, label, value, traits, excludeTraits, identifier, ordinal.
    /// Used by action/gesture/scroll commands that call `elementTarget(args)`.
    public static let elementTarget: [FenceParameterSpec] = [
        .init(key: "heistId", type: .string),
        .init(key: "label", type: .string),
        .init(key: "value", type: .string),
        .init(key: "traits", type: .stringArray),
        .init(key: "excludeTraits", type: .stringArray),
        .init(key: "identifier", type: .string),
        .init(key: "ordinal", type: .integer),
    ]

    /// Element filtering: label, value, traits, excludeTraits, identifier (no heistId/ordinal).
    /// Used by get_interface when filtering visible elements.
    public static let elementFilter: [FenceParameterSpec] = [
        .init(key: "label", type: .string),
        .init(key: "value", type: .string),
        .init(key: "traits", type: .stringArray),
        .init(key: "excludeTraits", type: .stringArray),
        .init(key: "identifier", type: .string),
    ]

    /// Inline expectation for action commands.
    public static let expect: FenceParameterSpec = .init(key: "expect", type: .object)
}

// MARK: - Per-Command Specs

extension TheFence.Command {

    public var cliExposure: CLIExposure {
        switch self {
        case .help, .quit, .exit, .status, .connect:
            return .sessionOnly

        case .increment, .decrement, .performCustomAction:
            return .groupedUnder("activate")

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
            return .groupedUnder("edit_action")

        // Grouped under "gesture" (including swipe)
        case .swipe, .oneFingerTap, .longPress, .drag, .pinch, .rotate, .twoFingerTap,
             .drawPath, .drawBezier:
            return .groupedUnder("gesture")

        // Grouped under "scroll"
        case .scrollToVisible, .elementSearch, .scrollToEdge:
            return .groupedUnder("scroll")

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
                .init(key: "full", type: .boolean),
                .init(key: "detail", type: .string),
                .init(key: "elements", type: .stringArray),
            ]

        case .getScreen:
            return [
                .init(key: "output", type: .string),
            ]

        case .waitForChange:
            return [
                expect,
                .init(key: "timeout", type: .number),
            ]

        // MARK: Gestures
        case .oneFingerTap:
            return target + [
                .init(key: "x", type: .number),
                .init(key: "y", type: .number),
                expect,
            ]

        case .longPress:
            return target + [
                .init(key: "x", type: .number),
                .init(key: "y", type: .number),
                .init(key: "duration", type: .number),
                expect,
            ]

        case .swipe:
            return target + [
                .init(key: "direction", type: .string),
                .init(key: "start", type: .object),
                .init(key: "end", type: .object),
                .init(key: "startX", type: .number),
                .init(key: "startY", type: .number),
                .init(key: "endX", type: .number),
                .init(key: "endY", type: .number),
                .init(key: "duration", type: .number),
                expect,
            ]

        case .drag:
            return target + [
                .init(key: "endX", type: .number, required: true),
                .init(key: "endY", type: .number, required: true),
                .init(key: "startX", type: .number),
                .init(key: "startY", type: .number),
                .init(key: "x", type: .number),
                .init(key: "y", type: .number),
                .init(key: "duration", type: .number),
                expect,
            ]

        case .pinch:
            return target + [
                .init(key: "scale", type: .number, required: true),
                .init(key: "centerX", type: .number),
                .init(key: "centerY", type: .number),
                .init(key: "x", type: .number),
                .init(key: "y", type: .number),
                .init(key: "spread", type: .number),
                .init(key: "duration", type: .number),
                expect,
            ]

        case .rotate:
            return target + [
                .init(key: "angle", type: .number, required: true),
                .init(key: "centerX", type: .number),
                .init(key: "centerY", type: .number),
                .init(key: "x", type: .number),
                .init(key: "y", type: .number),
                .init(key: "radius", type: .number),
                .init(key: "duration", type: .number),
                expect,
            ]

        case .twoFingerTap:
            return target + [
                .init(key: "centerX", type: .number),
                .init(key: "centerY", type: .number),
                .init(key: "x", type: .number),
                .init(key: "y", type: .number),
                .init(key: "spread", type: .number),
                expect,
            ]

        case .drawPath:
            return [
                .init(key: "points", type: .array, required: true),
                .init(key: "duration", type: .number),
                .init(key: "velocity", type: .number),
                expect,
            ]

        case .drawBezier:
            return [
                .init(key: "startX", type: .number, required: true),
                .init(key: "startY", type: .number, required: true),
                .init(key: "segments", type: .array, required: true),
                .init(key: "samplesPerSegment", type: .integer),
                .init(key: "duration", type: .number),
                .init(key: "velocity", type: .number),
                expect,
            ]

        // MARK: Scroll
        case .scroll:
            return target + [
                .init(key: "direction", type: .string, required: true),
                expect,
            ]

        case .scrollToVisible:
            return target + [expect]

        case .elementSearch:
            return target + [
                .init(key: "direction", type: .string),
                expect,
            ]

        case .scrollToEdge:
            return target + [
                .init(key: "edge", type: .string, required: true),
                expect,
            ]

        // MARK: Accessibility actions
        case .activate:
            return target + [
                .init(key: "action", type: .string),
                expect,
            ]

        case .increment, .decrement:
            return target + [expect]

        case .performCustomAction:
            return target + [
                .init(key: "action", type: .string, required: true),
                expect,
            ]

        // MARK: Text / keyboard
        case .typeText:
            return target + [
                .init(key: "text", type: .string),
                .init(key: "deleteCount", type: .integer),
                .init(key: "clearFirst", type: .boolean),
                expect,
            ]

        case .editAction:
            return [
                .init(key: "action", type: .string, required: true),
                expect,
            ]

        // MARK: Pasteboard
        case .setPasteboard:
            return [
                .init(key: "text", type: .string, required: true),
                expect,
            ]

        case .getPasteboard:
            return [expect]

        // MARK: Wait
        case .waitFor:
            return target + [
                .init(key: "absent", type: .boolean),
                .init(key: "timeout", type: .number),
                expect,
            ]

        // MARK: Recording
        case .startRecording:
            return [
                .init(key: "fps", type: .integer),
                .init(key: "scale", type: .number),
                .init(key: "max_duration", type: .number),
                .init(key: "inactivity_timeout", type: .number),
            ]

        case .stopRecording:
            return [
                .init(key: "output", type: .string),
            ]

        // MARK: Batch
        case .runBatch:
            return [
                .init(key: "steps", type: .array, required: true),
                .init(key: "policy", type: .string),
            ]

        // MARK: Connection
        case .connect:
            return [
                .init(key: "target", type: .string),
                .init(key: "device", type: .string),
                .init(key: "token", type: .string),
            ]

        // MARK: Session management
        case .archiveSession:
            return [
                .init(key: "delete_source", type: .boolean),
            ]

        case .startHeist:
            return [
                .init(key: "app", type: .string),
                .init(key: "identifier", type: .string),
            ]

        case .stopHeist:
            return [
                .init(key: "output", type: .string, required: true),
            ]

        case .playHeist:
            return [
                .init(key: "input", type: .string, required: true),
            ]
        }
    }
}
