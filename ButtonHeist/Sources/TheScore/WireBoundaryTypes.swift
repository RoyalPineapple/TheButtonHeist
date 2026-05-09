import Foundation

// MARK: - Wire-Boundary Enums
//
// These typed enums replace raw-string dispatch at CLI/MCP boundaries.
// Parse the incoming string once at the boundary, then pass the typed value
// through the rest of the stack (per CLAUDE.md "Type Safety: Enums Over Raw
// Strings").
//
// Each enum's rawValue is the canonical wire string the boundary accepts —
// the same string MCP tool schemas advertise to clients and the CLI accepts
// on argv.

/// MCP `scroll` tool's `mode` argument. Selects which underlying TheFence
/// scroll command the boundary dispatches to.
public enum ScrollMode: String, CaseIterable, Sendable {
    case page
    case toVisible = "to_visible"
    case search
    case toEdge = "to_edge"

    /// Canonical TheFence command name this mode dispatches to.
    public var canonicalCommand: String {
        switch self {
        case .page: return "scroll"
        case .toVisible: return "scroll_to_visible"
        case .search: return "element_search"
        case .toEdge: return "scroll_to_edge"
        }
    }
}

/// MCP `gesture` tool's `type` argument. Selects which underlying TheFence
/// gesture command the boundary dispatches to. The rawValues match TheFence
/// command names directly.
public enum GestureType: String, CaseIterable, Sendable {
    case oneFingerTap = "one_finger_tap"
    case longPress = "long_press"
    case swipe
    case drag
    case pinch
    case rotate
    case twoFingerTap = "two_finger_tap"
    case drawPath = "draw_path"
    case drawBezier = "draw_bezier"
}
