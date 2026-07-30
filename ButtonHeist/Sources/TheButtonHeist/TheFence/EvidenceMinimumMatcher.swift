import ThePlans
import TheScore

enum EvidenceMinimumMatcher {
    static func minimumTarget(actionResult: ActionResult) -> AccessibilityTarget? {
        guard let observation = actionResult.observationEvidence,
              observation.coverage == .complete,
              let evidence = actionResult.subjectEvidence,
              let before = observation.baseline
        else { return nil }

        let elements = before.interface.projectedElements
        guard let index = contextIndex(for: evidence, in: before.interface) else { return nil }
        let context = PredicateSelectionContext(
            elements: elements.enumerated().map { offset, element in
                PredicateSelectionContext.Element(id: contextElementId(forOffset: offset), element: element)
            },
            screenId: before.context.screenId ?? InterfaceSummary.screenId(for: before.interface),
            scope: .visible
        )
        return MinimumPredicateSelector.minimumUniquePredicate(
            for: contextElementId(forOffset: index),
            in: context
        )?.target
    }

    private static func contextElementId(forOffset offset: Int) -> PredicateSelectionElementId {
        PredicateSelectionElementId(rawValue: String(offset))
    }

    private static func contextIndex(
        for evidence: ActionSubjectEvidence,
        in interface: Interface
    ) -> Int? {
        let elements = interface.projectedElements
        if let targetIndex = index(of: evidence.target, in: interface) {
            return targetIndex
        }
        let equalIndices = elements.indices.filter { elements[$0] == evidence.element }
        return equalIndices.count == 1 ? equalIndices[0] : nil
    }

    static func index(of target: ResolvedAccessibilityTarget, in interface: Interface) -> Int? {
        let matches = AccessibilityTargetMatchGraph(interface: interface).resolve(target).elements.matches
        return matches.count == 1 ? matches[0].traversalOrder : nil
    }
}
