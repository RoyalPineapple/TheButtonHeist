import ThePlans
import TheScore

enum RepairCandidateGenerator {
    static func rankedSuccessorCandidates(
        oldResolved: RepairScreen.Element,
        currentScreen: RepairScreen,
        preferredCandidates: Set<PredicateSelectionElementId>,
        failureKind: HeistRepairFailureKind,
        actionFamily: RepairActionFamily,
        lastSuccess: HeistPassedStepRepairEvidence,
        currentFailure: HeistFailedStepRepairEvidence
    ) -> [ScoredCandidate] {
        let old = oldResolved.element
        let context = CandidateScoringContext(
            old: old,
            oldStableTraits: stableTraits(old),
            oldSiblingText: normalizedSet(oldResolved.siblingText),
            oldHeaderText: normalizedSet(oldResolved.headerText),
            afterEvidence: deltaEvidenceText(lastSuccess.afterDelta)
                .union(deltaEvidenceText(currentFailure.afterDelta)),
            expectationEvidence: expectationEvidenceText(lastSuccess.result.expectation)
                .union(expectationEvidenceText(currentFailure.result.expectation)),
            compatibleCandidateCount: currentScreen.elements
                .filter { !actionFamily.isKnown || actionFamily.isSupported(by: $0.element) }
                .count,
            currentElementCount: currentScreen.elements.count,
            preferredCandidates: preferredCandidates,
            failureKind: failureKind,
            actionFamily: actionFamily
        )

        return currentScreen.elements.compactMap { RepairCandidateScorer.scoredCandidate($0, context: context) }
            .sorted { $0.rank < $1.rank }
    }
}

private func deltaEvidenceText(_ delta: AccessibilityTrace.Delta?) -> RepairSemanticEvidence {
    guard let delta else { return RepairSemanticEvidence([]) }
    switch delta {
    case .noChange(let payload):
        return RepairSemanticEvidence(payload.transient.flatMap(identityStrings))
    case .screenChanged(let payload):
        return RepairSemanticEvidence(
            payload.newInterface.projectedElements.flatMap(identityStrings) +
                payload.transient.flatMap(identityStrings)
        )
    case .elementsChanged(let payload):
        var strings = payload.edits.added.flatMap(identityStrings)
        strings.append(contentsOf: payload.edits.removed.flatMap(identityStrings))
        strings.append(contentsOf: payload.edits.updated.flatMap { update in
            identityStrings(update.before) + identityStrings(update.after) +
                update.changes.flatMap { [$0.oldDisplayText, $0.newDisplayText].compactMap { $0 } }
        })
        strings.append(contentsOf: payload.transient.flatMap(identityStrings))
        return RepairSemanticEvidence(strings)
    }
}

private func expectationEvidenceText(_ expectation: ExpectationResult?) -> RepairSemanticEvidence {
    RepairSemanticEvidence([expectation?.actual].compactMap { $0 })
}

private func identityStrings(_ element: HeistElement) -> [String] {
    [stableIdentifier(element.identifier), element.label, element.value, element.hint, element.description]
        .compactMap { $0 }
}
