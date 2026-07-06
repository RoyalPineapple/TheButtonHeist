import Foundation
import ThePlans

/// Resolved, internal action dispatch used by the heist runtime and by direct
/// transient client commands.
///
/// This type is intentionally not `Codable`: durable mutation crosses the
/// client/server boundary as `ClientMessage.heistPlan`, while transient direct
/// commands cross as `HeistActionCommand` and lower to this type inside the app
/// runtime.
package enum RuntimeActionMessage: Sendable, Equatable {
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

    /// Perform the screen-level accessibility escape action.
    case dismiss

    /// Perform the screen-level accessibility magic tap action.
    case magicTap

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

    /// Capture the current screen as heist receipt evidence.
    case takeScreenshot

    /// Wait until an accessibility predicate is satisfied.
    case wait(WaitTarget)
}

package enum RuntimeActionType: String, Sendable, Equatable, CaseIterable {
    case activate, increment, decrement, performCustomAction, rotor
    case dismiss, magicTap
    case oneFingerTap, longPress, swipe, drag
    case typeText, editAction, setPasteboard
    case takeScreenshot
    case scroll, scrollToVisible, scrollToEdge, resignFirstResponder
    case wait
}

package extension RuntimeActionMessage {
    var runtimeType: RuntimeActionType {
        switch self {
        case .activate: return .activate
        case .increment: return .increment
        case .decrement: return .decrement
        case .performCustomAction: return .performCustomAction
        case .rotor: return .rotor
        case .dismiss: return .dismiss
        case .magicTap: return .magicTap
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
        case .takeScreenshot: return .takeScreenshot
        case .wait: return .wait
        }
    }
}
