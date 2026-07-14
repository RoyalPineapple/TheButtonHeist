#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

extension ResolvedScreenAssertion {
    var observationScope: SemanticObservationScope {
        core.observationScope
    }
}

extension ResolvedAccessibilityPredicate {
    var observationScope: SemanticObservationScope {
        core.observationScope
    }
}

private extension AccessibilityPredicateCore where Phase == ResolvedAccessibilityPredicatePhase {
    var observationScope: SemanticObservationScope {
        switch self {
        case .presence(let presence):
            return presence.observationScope
        case .changed(.screen(let assertions)):
            return assertions.map(\.observationScope).max() ?? .visible
        case .changed(.elements(let assertions)):
            return assertions.map(\.observationScope).max() ?? .visible
        case .noChange, .announcement:
            return .visible
        }
    }
}

private extension ScreenAssertionCore where Phase == ResolvedAccessibilityPredicatePhase {
    var observationScope: SemanticObservationScope {
        switch self {
        case .presence(let presence):
            return presence.observationScope
        }
    }
}

private extension ElementAssertionCore where Phase == ResolvedAccessibilityPredicatePhase {
    var observationScope: SemanticObservationScope {
        switch self {
        case .presence(let presence):
            return presence.observationScope
        case .appeared(let target), .disappeared(let target), .updated(let target, _):
            return target.observationScope
        }
    }
}

private extension PresencePredicateCore where Phase == ResolvedAccessibilityPredicatePhase {
    var observationScope: SemanticObservationScope {
        switch self {
        case .exists(let target), .missing(let target):
            return target.observationScope
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
