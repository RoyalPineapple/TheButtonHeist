import ThePlans
/// Identifies the command behavior represented by an `ActionResult`.
///
/// Activation-point dispatch that completes an `activate` command still reports
/// `.activate`; `.syntheticTap` is reserved for explicit mechanical
/// `one_finger_tap` requests.
public enum ActionMethod: String, Codable, Sendable {
    case activate
    case increment
    case decrement
    case syntheticTap
    case syntheticLongPress
    case syntheticSwipe
    case syntheticDrag
    case typeText
    case customAction
    case editAction
    case resignFirstResponder
    case setPasteboard
    case getPasteboard
    case takeScreenshot
    case rotor
    case heistPlan
    case scroll
    case scrollToVisible
    case scrollToEdge
    case wait
}
