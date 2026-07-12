#if canImport(UIKit)
import UIKit

import TheScore
import ThePlans

extension TheStash {
    func minimumUniqueTarget(for treeElement: InterfaceTree.Element) -> AccessibilityTarget? {
        let elements = orderedInterfaceElements.map {
            PredicateSelectionSubjectElement(id: $0.heistId.predicateSelectionElementId, element: $0.element)
        }
        return MinimumPredicateSelector.minimumUniquePredicate(
            for: treeElement.heistId.predicateSelectionElementId,
            in: elements
        )?.target
    }
}

#endif // canImport(UIKit)
