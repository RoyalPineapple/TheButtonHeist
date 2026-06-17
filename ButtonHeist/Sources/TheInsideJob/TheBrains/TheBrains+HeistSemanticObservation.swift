#if canImport(UIKit)
#if DEBUG
import TheScore

extension ConditionalStep {
    var observationScope: SemanticObservationScope {
        cases
            .compactMap { try? $0.predicate.resolve(in: .empty).observationScope }
            .max() ?? .visible
    }
}

extension AccessibilityPredicate {
    var observationScope: SemanticObservationScope {
        switch self {
        case .state(let state):
            return state.observationScope
        case .changed(let change):
            return change.observationScope
        }
    }
}

private extension AccessibilityPredicate.State {
    var observationScope: SemanticObservationScope {
        switch self {
        case .present, .absent, .presentTarget, .absentTarget:
            return .visible
        case .all(let states):
            return states
                .map(\.observationScope)
                .max() ?? .visible
        }
    }
}

private extension AccessibilityPredicate.Change {
    var observationScope: SemanticObservationScope {
        switch self {
        case .screen(let state):
            return state?.observationScope ?? .visible
        case .elements, .updated:
            return .visible
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
