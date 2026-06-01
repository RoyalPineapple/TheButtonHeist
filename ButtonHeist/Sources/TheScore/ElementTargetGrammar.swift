import Foundation

/// Shared validation for the public element target choice.
///
/// A current-capture `heistId` stands alone; `ordinal` only disambiguates a
/// semantic predicate.
public enum ElementTargetGrammar {
    public static func validatedTarget(
        heistId: HeistId?,
        predicate: ElementPredicate?,
        predicateWasProvided: Bool,
        ordinal: Int?
    ) throws -> ElementTarget {
        if let ordinal, ordinal < 0 {
            throw ElementTargetGrammarError.negativeOrdinal(ordinal)
        }

        if let heistId {
            guard ordinal == nil, !predicateWasProvided else {
                throw ElementTargetGrammarError.mixedHeistIdWithPredicateOrOrdinal
            }
            return .heistId(heistId)
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
    case mixedHeistIdWithPredicateOrOrdinal
    case negativeOrdinal(Int)

    public var diagnosticDescription: String {
        switch self {
        case .missingTarget:
            return "ElementTarget requires heistId or predicate"
        case .emptyPredicate:
            return "ElementTarget predicate requires label, identifier, value, traits, or excludeTraits"
        case .mixedHeistIdWithPredicateOrOrdinal:
            return "ElementTarget heistId cannot be combined with predicate fields or ordinal"
        case .negativeOrdinal(let ordinal):
            return "ordinal must be non-negative, got \(ordinal)"
        }
    }
}
