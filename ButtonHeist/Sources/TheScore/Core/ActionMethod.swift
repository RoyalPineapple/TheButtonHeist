import ThePlans
/// Identifies the command behavior represented by an `ActionResult`.
///
/// Activation-point dispatch that completes an `activate` command still reports
/// `.activate`; `.oneFingerTap` is reserved for explicit mechanical
/// `one_finger_tap` requests.
public enum ActionMethod: String, Codable, Sendable {
    case activate
    case increment
    case decrement
    case dismiss
    case magicTap
    case oneFingerTap
    case longPress
    case swipe
    case drag
    case typeText
    case customAction
    case editAction
    case dismissKeyboard
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
