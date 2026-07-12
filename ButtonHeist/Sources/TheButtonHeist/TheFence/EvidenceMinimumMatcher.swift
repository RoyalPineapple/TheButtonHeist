import ThePlans
import TheScore

enum EvidenceMinimumMatcher {
    static func normalizedTarget(
        _ target: AccessibilityTarget,
        actionResult: ActionResult
    ) -> AccessibilityTarget {
        minimumTarget(actionResult: actionResult) ?? target
    }

    static func activationTarget(actionResult: ActionResult) -> AccessibilityTarget? {
        guard let evidence = actionResult.subjectEvidence,
              isActivatable(evidence.element)
        else { return nil }
        return minimumTarget(actionResult: actionResult)
    }

    static func isActivatable(_ element: HeistElement) -> Bool {
        element.actions.contains(.activate)
            || element.traits.contains { AccessibilityPolicy.interactiveTraits.contains($0) }
    }

    static func minimumTarget(actionResult: ActionResult) -> AccessibilityTarget? {
        guard actionResult.settled != false,
              let evidence = actionResult.subjectEvidence,
              let trace = actionResult.accessibilityTrace,
              let before = trace.captures.first
        else { return nil }

        let elements = before.interface.projectedElements
        guard let index = contextIndex(for: evidence, in: elements) else { return nil }
        let context = PredicateSelectionContext(
            elements: elements.enumerated().map { offset, element in
                PredicateSelectionContext.Element(id: contextElementId(forOffset: offset), element: element)
            },
            screenId: before.context.screenId,
            semanticHash: before.hash,
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
        in elements: [HeistElement]
    ) -> Int? {
        if let targetIndex = index(of: evidence.target, in: elements) {
            return targetIndex
        }
        let equalIndices = elements.indices.filter { elements[$0] == evidence.element }
        return equalIndices.count == 1 ? equalIndices[0] : nil
    }

    static func index(of target: AccessibilityTarget, in elements: [HeistElement]) -> Int? {
        switch target {
        case .predicate(let template, let ordinal):
            guard let predicate = try? template.resolve(in: .empty) else { return nil }
            let matches = ElementMatchGraph(elements: elements).resolve(predicate).matches
            if let ordinal {
                guard matches.indices.contains(ordinal) else { return nil }
                return matches[ordinal].traversalOrder
            }
            return matches.count == 1 ? matches[0].traversalOrder : nil
        case .container, .ref, .within:
            return nil
        }
    }
}
