import Foundation

/// Shared validation for the public element target choice.
///
/// A current-capture `heistId` stands alone; `ordinal` only disambiguates a
/// semantic matcher.
public enum ElementTargetGrammar {
    public static func validatedTarget(
        heistId: HeistId?,
        matcher: ElementMatcher?,
        matcherWasProvided: Bool,
        ordinal: Int?
    ) throws -> ElementTarget {
        if let ordinal, ordinal < 0 {
            throw ElementTargetGrammarError.negativeOrdinal(ordinal)
        }

        if let heistId {
            guard ordinal == nil, !matcherWasProvided else {
                throw ElementTargetGrammarError.mixedHeistIdWithMatcherOrOrdinal
            }
            return .heistId(heistId)
        }

        guard matcherWasProvided else {
            throw ElementTargetGrammarError.missingTarget
        }
        guard let matcher, matcher.hasPredicates else {
            throw ElementTargetGrammarError.emptyMatcher
        }
        return .matcher(matcher, ordinal: ordinal)
    }
}

public enum ElementTargetGrammarError: Error, Equatable, Sendable {
    case missingTarget
    case emptyMatcher
    case mixedHeistIdWithMatcherOrOrdinal
    case negativeOrdinal(Int)

    public var diagnosticDescription: String {
        switch self {
        case .missingTarget:
            return "ElementTarget requires heistId or matcher"
        case .emptyMatcher:
            return "ElementTarget matcher requires label, identifier, value, traits, or excludeTraits"
        case .mixedHeistIdWithMatcherOrOrdinal:
            return "ElementTarget heistId cannot be combined with matcher fields or ordinal"
        case .negativeOrdinal(let ordinal):
            return "ordinal must be non-negative, got \(ordinal)"
        }
    }
}
