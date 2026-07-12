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
            afterEvidence: changeFactEvidenceText(lastSuccess.changeFacts)
                .union(changeFactEvidenceText(currentFailure.changeFacts)),
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

private func changeFactEvidenceText(
    _ facts: [AccessibilityTrace.ChangeFact]
) -> RepairSemanticEvidence {
    RepairSemanticEvidence(facts.flatMap { fact in
        switch fact {
        case .screenChanged(let screen):
            return metadataEvidenceText(screen.metadata)
        case .elementsChanged(let elements):
            let appeared: [String] = elements.appeared.flatMap(identityStrings)
            let disappeared: [String] = elements.disappeared.flatMap(identityStrings)
            let updated: [String] = elements.updated.flatMap { update in
                let changedText = update.changes.flatMap {
                    [$0.oldDisplayText, $0.newDisplayText].compactMap { $0 }
                }
                return identityStrings(update.before) + identityStrings(update.after) + changedText
            }
            return appeared + disappeared + updated + metadataEvidenceText(elements.metadata)
        }
    })
}

private func expectationEvidenceText(_ expectation: ExpectationResult?) -> RepairSemanticEvidence {
    RepairSemanticEvidence([expectation?.actual].compactMap { $0 })
}

private func identityStrings(_ element: HeistElement) -> [String] {
    [stableIdentifier(element.identifier), element.label, element.value, element.hint, element.description]
        .compactMap { $0 }
}

private func identityStrings(_ node: AccessibilityTrace.InterfaceChangeNode) -> [String] {
    switch node.node {
    case .element(let element, _):
        return [
            stableIdentifier(element.identifier),
            element.label,
            element.value,
            element.hint,
            element.description,
        ].compactMap { $0 }
    case .container(let container, _):
        let semanticText: [String?]
        if case .semanticGroup(let label, let value) = container.type {
            semanticText = [label, value]
        } else {
            semanticText = []
        }
        return ([stableIdentifier(container.identifier)] + semanticText).compactMap { $0 }
    }
}

private func metadataEvidenceText(_ metadata: AccessibilityTrace.ChangeFactMetadata) -> [String] {
    metadata.transient.flatMap(identityStrings)
        + metadata.accessibilityNotifications.flatMap { notification in
            notificationEvidenceText(notification.notificationData)
                + notificationEvidenceText(notification.associatedElement)
        }
}

private func notificationEvidenceText(_ payload: AccessibilityNotificationPayload) -> [String] {
    switch payload {
    case .none, .element, .unresolvedElement:
        return []
    case .string(let value):
        return [value]
    case .unresolvedObject(let object):
        return [object.summary].compactMap { $0 }
    }
}
