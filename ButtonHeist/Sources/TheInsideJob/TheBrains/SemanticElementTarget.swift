#if canImport(UIKit)
#if DEBUG
import TheScore

/// Semantic identity for element-targeted execution.
///
/// Direct commands may use a current heistId as executable identity. Batch
/// commands never do: their source heistId is capture metadata only, while the
/// matcher and ordinal are resolved against the fresh live hierarchy before
/// any interaction acquires geometry.
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

extension SemanticActionTarget: SemanticElementTarget {
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
