#if canImport(UIKit)
import UIKit

import TheScore
import ThePlans

extension TheStash {
    func minimumUniqueTarget(for treeElement: InterfaceTree.Element) -> AccessibilityTarget? {
        minimumUniqueTarget(for: treeElement.heistId, in: interfaceTree)
    }

    func minimumUniqueTarget(for heistId: HeistId, in tree: InterfaceTree) -> AccessibilityTarget? {
        let elements = tree.orderedElements.map {
            PredicateSelectionSubjectElement(id: $0.heistId.predicateSelectionElementId, element: $0.element)
        }
        return MinimumPredicateSelector.minimumUniquePredicate(
            for: heistId.predicateSelectionElementId,
            in: elements
        )?.target
    }
}

#endif // canImport(UIKit)
