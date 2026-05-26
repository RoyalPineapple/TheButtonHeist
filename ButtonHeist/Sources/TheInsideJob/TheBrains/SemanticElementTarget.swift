#if canImport(UIKit)
#if DEBUG
import TheScore

/// Semantic identity for element-targeted execution.
///
/// Commands may use a current heistId as executable identity or matcher fields
/// for semantic lookup. Batch steps carry these same command targets; viewport
/// recovery and semantic reveal stay inside the normal action pipeline.
protocol SemanticElementTarget: Sendable {
    var exactHeistId: HeistId? { get }
    var sourceHeistId: HeistId? { get }
    var semanticMatcher: ElementMatcher? { get }
    var semanticOrdinal: Int? { get }
}

extension ElementTarget: SemanticElementTarget {
    var exactHeistId: HeistId? {
        if case .heistId(let heistId) = self {
            return heistId
        }
        return nil
    }

    var sourceHeistId: HeistId? { exactHeistId }

    var semanticMatcher: ElementMatcher? {
        if case .matcher(let matcher, _) = self {
            return matcher
        }
        return nil
    }

    var semanticOrdinal: Int? {
        if case .matcher(_, let ordinal) = self {
            return ordinal
        }
        return nil
    }
}

struct BatchSemanticElementTarget: SemanticElementTarget {
    let sourceHeistId: HeistId?
    let semanticMatcher: ElementMatcher?
    let semanticOrdinal: Int?

    var exactHeistId: HeistId? { nil }

    init(_ target: SemanticActionTarget) {
        self.sourceHeistId = target.sourceHeistId
        self.semanticMatcher = target.matcher
        self.semanticOrdinal = target.ordinal
    }
}

extension SemanticActionTarget {
    var exactHeistId: HeistId? { nil }
    var semanticMatcher: ElementMatcher? { matcher }
    var semanticOrdinal: Int? { ordinal }
}

extension TheStash {
    func normalizeTarget(
        _ target: any SemanticElementTarget,
        in sourceScreen: Screen? = nil
    ) -> NormalizedTarget {
        if let elementTarget = target as? ElementTarget {
            return normalizeTarget(elementTarget, in: sourceScreen)
        }
        let executableTarget = semanticElementTarget(for: target)
        return NormalizedTarget(
            originalTarget: executableTarget,
            executableTarget: executableTarget,
            sourceHeistId: target.sourceHeistId,
            sourceScreen: sourceScreen ?? currentScreen
        )
    }

    func normalizeTarget(
        _ target: SemanticActionTarget,
        in sourceScreen: Screen? = nil
    ) -> NormalizedTarget {
        normalizeTarget(BatchSemanticElementTarget(target), in: sourceScreen)
    }

    func semanticElementTarget(for target: any SemanticElementTarget) -> ElementTarget {
        if let exactHeistId = target.exactHeistId {
            return .heistId(exactHeistId)
        }
        return .matcher(target.semanticMatcher ?? ElementMatcher(), ordinal: target.semanticOrdinal)
    }

    func resolveTarget(_ target: any SemanticElementTarget) -> TargetResolution {
        resolveTarget(semanticElementTarget(for: target))
    }

    func resolveVisibleTarget(_ target: any SemanticElementTarget) -> TargetResolution {
        resolveVisibleTarget(semanticElementTarget(for: target))
    }

    func resolveFirstVisibleMatch(_ target: any SemanticElementTarget) -> ResolvedTarget? {
        resolveFirstVisibleMatch(semanticElementTarget(for: target))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
