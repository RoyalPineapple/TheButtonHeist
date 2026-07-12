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
        node.observationScope
    }
}

private extension AccessibilityPredicateNode {
    var observationScope: SemanticObservationScope {
        switch self {
        case .exists(let target), .missing(let target), .appeared(let target), .disappeared(let target):
            return target.observationScope
        case .updated(let target, _):
            return target.observationScope
        case .changed(let child):
            return child.observationScope
        case .screen(let assertions), .elements(let assertions):
            return assertions.map(\.observationScope).max() ?? .visible
        case .noChange, .announcement:
            return .visible
        }
    }
}

private extension AccessibilityTarget {
    var observationScope: SemanticObservationScope {
        switch self {
        case .predicate, .ref:
            return .visible
        case .container, .within:
            return .discovery
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
