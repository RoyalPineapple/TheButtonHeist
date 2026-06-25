import ThePlans
import TheScore

enum RepairCandidateGenerator {
    static func rankedSuccessorCandidates(
        oldResolved: RepairScreen.Element,
        currentScreen: RepairScreen,
        preferredCandidates: Set<String>,
        failureKind: HeistRepairFailureKind,
        actionFamily: RepairActionFamily,
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
    ) -> [ScoredCandidate] {
        let old = oldResolved.element
        let context = CandidateScoringContext(
            old: old,
            oldStableTraits: stableTraits(old),
            oldSiblingText: normalizedSet(oldResolved.siblingText),
            oldHeaderText: normalizedSet(oldResolved.headerText),
            afterEvidence: deltaEvidenceStrings(lastSuccess.afterDelta)
                .union(deltaEvidenceStrings(currentFailure.afterDelta)),
            expectationEvidence: expectationEvidenceStrings(lastSuccess.result.expectation)
                .union(expectationEvidenceStrings(currentFailure.result.expectation)),
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

private func deltaEvidenceStrings(_ delta: AccessibilityTrace.Delta?) -> Set<String> {
    guard let delta else { return [] }
    switch delta {
    case .noChange(let payload):
        return normalizedSet(payload.transient.flatMap(identityStrings))
    case .screenChanged(let payload):
        return normalizedSet(payload.newInterface.projectedElements.flatMap(identityStrings))
            .union(normalizedSet(payload.transient.flatMap(identityStrings)))
    case .elementsChanged(let payload):
        var strings = payload.edits.added.flatMap(identityStrings)
        strings.append(contentsOf: payload.edits.removed.flatMap(identityStrings))
        strings.append(contentsOf: payload.edits.updated.flatMap { update in
            identityStrings(update.element) + update.changes.flatMap { [$0.old, $0.new].compactMap { $0 } }
        })
        strings.append(contentsOf: payload.transient.flatMap(identityStrings))
        return normalizedSet(strings)
    }
}

private func expectationEvidenceStrings(_ expectation: ExpectationResult?) -> Set<String> {
    normalizedSet([expectation?.actual].compactMap { $0 })
}

private func identityStrings(_ element: HeistElement) -> [String] {
    [stableIdentifier(element.identifier), element.label, element.value, element.hint, element.description]
        .compactMap { $0 }
}
