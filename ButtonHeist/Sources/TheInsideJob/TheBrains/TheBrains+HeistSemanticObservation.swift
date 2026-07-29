#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

extension ResolvedPresenceCondition {
    var observationScope: SemanticObservationScope {
        rootPredicate.observationScope
    }
}

extension ObservationPredicate {
    var observationScope: SemanticObservationScope {
        switch self {
        case .elementsChanged(let assertions):
            return assertions.map(\.target.observationScope).max() ?? .visible
        case .notification, .noChange, .screenChanged:
            return .visible
        }
    }
}

private extension ResolvedAccessibilityTarget {
    var observationScope: SemanticObservationScope {
        switch self {
        case .predicate:
            return .visible
        case .container, .within:
            return .discovery
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
