import Foundation

/// Shared validation for the public element target choice.
///
/// A target is a predicate (+ optional `ordinal` disambiguator).
public enum ElementTargetGrammar {
    public static func validatedTarget(
        predicate: ElementPredicate?,
        predicateWasProvided: Bool,
        ordinal: Int?
    ) throws -> ElementTarget {
        if let ordinal, ordinal < 0 {
            throw ElementTargetGrammarError.negativeOrdinal(ordinal)
        }

        guard predicateWasProvided else {
            throw ElementTargetGrammarError.missingTarget
        }
        guard let predicate, predicate.hasPredicates else {
            throw ElementTargetGrammarError.emptyPredicate
        }
        return .predicate(predicate, ordinal: ordinal)
    }
}

public enum ElementTargetGrammarError: Error, Equatable, Sendable {
    case missingTarget
    case emptyPredicate
    case negativeOrdinal(Int)

    public var diagnosticDescription: String {
        switch self {
        case .missingTarget:
            return "ElementTarget requires a predicate"
        case .emptyPredicate:
            return "ElementTarget predicate requires label, identifier, value, hint, traits, actions, customContent, rotors, or checks with exclude"
        case .negativeOrdinal(let ordinal):
            return "ordinal must be non-negative, got \(ordinal)"
        }
    }
}
