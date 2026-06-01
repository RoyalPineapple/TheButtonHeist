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
    case batchExecutionPlan
    case scroll
    case scrollToVisible
    case elementSearch
    case scrollToEdge
    case wait
}
