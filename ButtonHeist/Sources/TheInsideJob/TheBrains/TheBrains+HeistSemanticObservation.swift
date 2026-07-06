#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

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
        case .changePredicate(let change):
            return change.observationScope
        case .noChangePredicate, .announcement:
            return .visible
        }
    }
}

private extension AccessibilityPredicate.State {
    var observationScope: SemanticObservationScope {
        switch self {
        case .exists, .missing, .existsTarget, .missingTarget:
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
        case .any:
            return .visible
        case .screenScope(let states):
            return states.map(\.observationScope).max() ?? .visible
        case .elementsScope:
            return .visible
        case .allScopes(let changes):
            return changes.map(\.observationScope).max() ?? .visible
        }
    }
}

private extension AccessibilityPredicate.ChangeScope {
    var observationScope: SemanticObservationScope {
        switch self {
        case .screen(let states):
            return states.map(\.observationScope).max() ?? .visible
        case .elements:
            return .visible
        case .all(let changes):
            return changes.map(\.observationScope).max() ?? .visible
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
