import ThePlans
import TheScore

enum RepairCandidateGenerator {
    static func rankedSuccessorCandidates(
        oldResolved: RepairScreen.Element,
        currentScreen: RepairScreen,
        preferredCandidates: Set<PredicateSelectionElementId>,
        failureKind: HeistRepairFailureKind,
        actionRequirement: RepairActionRequirement,
        lastSuccess: HeistRepairEvidence,
        currentFailure: HeistRepairEvidence
    ) -> [ScoredCandidate] {
        let old = oldResolved.element
        let context = CandidateScoringContext(
            old: old,
            oldStableTraits: stableTraits(old),
            oldSiblingText: normalizedSet(oldResolved.siblingText),
            oldHeaderText: normalizedSet(oldResolved.headerText),
            afterEvidence: RepairSemanticEvidence(lastSuccess.semanticEvidence)
                .union(RepairSemanticEvidence(currentFailure.semanticEvidence)),
            expectationEvidence: expectationEvidenceText(lastSuccess.expectation)
                .union(expectationEvidenceText(currentFailure.expectation)),
            compatibleCandidateCount: currentScreen.elements
                .filter { !actionRequirement.isKnown || actionRequirement.isSupported(by: $0.element) }
                .count,
            currentElementCount: currentScreen.elements.count,
            preferredCandidates: preferredCandidates,
            failureKind: failureKind,
            actionRequirement: actionRequirement
        )

        return currentScreen.elements.compactMap { RepairCandidateScorer.scoredCandidate($0, context: context) }
            .sorted { $0.rank < $1.rank }
    }
}

private func expectationEvidenceText(_ expectation: ExpectationResult?) -> RepairSemanticEvidence {
    RepairSemanticEvidence([expectation?.actual].compactMap { $0 })
}
