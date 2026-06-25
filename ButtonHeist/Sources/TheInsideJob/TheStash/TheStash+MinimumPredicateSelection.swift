#if canImport(UIKit)
import UIKit

import TheScore
import ThePlans

extension TheStash {
    func predicateSelectionContext(scope: SemanticObservationScope = .visible) -> PredicateSelectionContext {
        PredicateSelectionContext(
            elements: orderedSemanticElements.map {
                PredicateSelectionContext.Element(
                    id: $0.heistId.predicateSelectionElementId,
                    element: WireConversion.convert($0.element)
                )
            },
            screenId: lastScreenId,
            semanticHash: semanticHash,
            scope: scope.predicateSelectionScope
        )
    }

    func minimumUniqueTarget(
        for screenElement: ScreenElement,
        scope: SemanticObservationScope = .visible
    ) -> ElementTarget? {
        minimumUniquePredicate(
            for: screenElement.heistId.predicateSelectionElementId,
            in: predicateSelectionContext(scope: scope)
        )?.target
    }
}

private extension SemanticObservationScope {
    var predicateSelectionScope: PredicateSelectionContext.Scope {
        switch self {
        case .visible:
            return .visible
        case .discovery:
            return .discovery
        }
    }
}

#endif // canImport(UIKit)
