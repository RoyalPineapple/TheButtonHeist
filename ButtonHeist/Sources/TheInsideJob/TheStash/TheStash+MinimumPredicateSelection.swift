#if canImport(UIKit)
import UIKit

import TheScore
import ThePlans

extension TheStash {
    func minimumUniqueTarget(for screenElement: ScreenElement) -> ElementTarget? {
        let elements = orderedSemanticElements.map {
            PredicateSelectionSubjectElement(id: $0.heistId.predicateSelectionElementId, element: $0.element)
        }
        return minimumUniquePredicate(
            for: screenElement.heistId.predicateSelectionElementId,
            in: elements
        )?.target
    }
}

#endif // canImport(UIKit)
