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

}

extension TheStash {
    func normalizeTarget(_ target: SemanticElementTarget) -> NormalizedTarget {
        let executableTarget = target.executableTarget
        return NormalizedTarget(
            executableTarget: executableTarget,
            sourceHeistId: target.sourceHeistId,
            validationFailure: target.validationFailureMessage
        )
    }

    func normalizeTarget(_ target: SemanticActionTarget) -> NormalizedTarget {
        normalizeTarget(.durable(target))
    }

    func semanticElementTarget(for target: SemanticElementTarget) -> ElementTarget? {
        target.executableTarget
    }

    func resolveTarget(_ target: SemanticElementTarget) -> TargetResolution {
        guard let executableTarget = target.executableTarget else {
            return .notFound(diagnostics: "semantic target requires matcher predicates")
        }
        return resolveTarget(executableTarget)
    }

    func resolveVisibleTarget(_ target: SemanticElementTarget) -> TargetResolution {
        guard let executableTarget = target.executableTarget else {
            return .notFound(diagnostics: "semantic target requires matcher predicates")
        }
        return resolveVisibleTarget(executableTarget)
    }

    func resolveFirstVisibleMatch(_ target: SemanticElementTarget) -> ResolvedTarget? {
        guard let executableTarget = target.executableTarget else { return nil }
        return resolveFirstVisibleMatch(executableTarget)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
