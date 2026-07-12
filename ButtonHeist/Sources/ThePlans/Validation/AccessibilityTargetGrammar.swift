import Foundation

public enum AccessibilityTargetGrammarError: Error, Equatable, Sendable {
    case missingTarget
    case emptyPredicate
    case negativeOrdinal(Int)

    public var diagnosticDescription: String {
        switch self {
        case .missingTarget:
            return "AccessibilityTarget requires a predicate"
        case .emptyPredicate:
            return "AccessibilityTarget predicate requires label, identifier, value, hint, traits, actions, customContent, rotors, or checks with exclude"
        case .negativeOrdinal(let ordinal):
            return "ordinal must be non-negative, got \(ordinal)"
        }
    }
}
