import Foundation

/// Resolved, internal action dispatch used by the heist runtime.
///
/// This type is intentionally not `Codable`: public mutation crosses the
/// client/server boundary only as `ClientMessage.heistPlan`, then action steps
/// lower to this type inside the app runtime.
public enum RuntimeActionMessage: Sendable, Equatable {
    /// Activate an element.
    case activate(ElementTarget)

    /// Increment an adjustable element.
    case increment(ElementTarget)

    /// Decrement an adjustable element.
    case decrement(ElementTarget)

    /// Perform a custom action on an element.
    case performCustomAction(CustomActionTarget)

    /// Move through a custom accessibility rotor.
    case rotor(RotorTarget)

    /// Tap at a point or element.
    case oneFingerTap(TapTarget)

    /// Long press at a point or element.
    case longPress(LongPressTarget)

    /// Swipe from one point to another.
    case swipe(SwipeTarget)

    /// Drag from one point to another.
    case drag(DragTarget)

    /// Type text character-by-character by tapping keyboard keys.
    case typeText(TypeTextTarget)

    /// Perform a standard edit action on the first responder.
    case editAction(EditActionTarget)

    /// Scroll via accessibility scroll action.
    case scroll(ScrollTarget)

    /// One-shot scroll to a known element position.
    case scrollToVisible(ScrollToVisibleTarget)

    /// Scroll the nearest scroll view ancestor to an edge.
    case scrollToEdge(ScrollToEdgeTarget)

    /// Resign first responder.
    case resignFirstResponder

    /// Write text to the general pasteboard from inside the app.
    case setPasteboard(SetPasteboardTarget)

    /// Wait until an accessibility predicate is satisfied.
    case wait(WaitTarget)
}

public extension RuntimeActionMessage {
    var runtimeType: ClientWireMessageType {
        switch self {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .performCustomAction: return .performCustomAction
        case .rotor: return .rotor
        case .oneFingerTap: return .oneFingerTap
        case .longPress: return .longPress
        case .swipe: return .swipe
        case .drag: return .drag
        case .typeText: return .typeText
        case .editAction: return .editAction
        case .scroll: return .scroll
        case .scrollToVisible: return .scrollToVisible
        case .scrollToEdge: return .scrollToEdge
        case .resignFirstResponder: return .resignFirstResponder
        case .setPasteboard: return .setPasteboard
        case .wait: return .wait
        }
    }
}
