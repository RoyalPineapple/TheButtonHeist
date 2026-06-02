/// Identifies which action handler produced an ActionResult.
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
    case rotor
    case heistPlan
    case scroll
    case scrollToVisible
    case scrollToEdge
    case wait
}
