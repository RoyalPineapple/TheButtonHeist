#if canImport(UIKit)
#if DEBUG
import TheScore

/// Runtime semantic identity for element-targeted execution.
///
/// Current-capture targets may execute by heistId. Durable replay/batch targets
/// are matcher-only and carry any source heistId as diagnostic evidence.
enum SemanticElementTarget: Sendable {
    case currentCapture(ElementTarget)
    case durable(SemanticActionTarget)

    var sourceHeistId: HeistId? {
        guard case .durable(let target) = self else { return nil }
        return target.sourceHeistId
    }

    var executableTarget: ElementTarget? {
        switch self {
        case .currentCapture(let target):
            return target
        case .durable(let target):
            guard let matcher = target.matcher.nonEmpty else { return nil }
            return .matcher(matcher, ordinal: target.ordinal)
        }
    }

    var validationFailureMessage: String? {
        executableTarget == nil ? "semantic target requires matcher predicates" : nil
    }

    func diagnostics(_ message: String) -> String {
        guard let sourceHeistId else { return message }
        guard !message.contains(sourceHeistId) else { return message }
        return "\(message)\nSource heistId: \(sourceHeistId)"
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
