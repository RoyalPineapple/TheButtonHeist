import ThePlans
import TheScore

enum HeistRepairSuggestionRenderer {
    static func noSuggestionReason(for analysis: HeistRepairAnalysis) -> String {
        switch analysis {
        case .ineligible(let reason):
            return reason.noSuggestionReason
        case .eligible(let analysis):
            return noSuggestionReason(for: analysis)
        }
    }

    private static func noSuggestionReason(for analysis: HeistEligibleRepairAnalysis) -> String {
        switch analysis.failureKind {
        case .wrongCapability:
            return """
                old target still resolves but does not support the requested action; \
                no safe compatible successor satisfied semantic continuity and unique-matcher requirements
                """

        case .missingTarget:
            return """
                old target is missing in the current before snapshot; \
                no safe successor satisfied semantic continuity and unique-matcher requirements
                """

        case .ambiguousTarget:
            return """
                old target is ambiguous in the current before snapshot; \
                no candidate could be safely disambiguated
                """
        }
    }

    static func suggestion(
        for candidate: ScoredCandidate,
        analysis: HeistEligibleRepairAnalysis,
        request: HeistRepairRequest,
        tiedBestCount: Int
    ) -> HeistRepairSuggestion? {
        let currentScreen = analysis.currentScreen
        let selectionContext = currentScreen.selectionContext()
        guard let selection = minimumUniquePredicate(for: candidate.element.id, in: selectionContext),
              case .resolved(let validation, _) = currentScreen.resolve(selection.target),
              validation.id == candidate.element.id
        else {
            return nil
        }

        if analysis.actionFamily.isKnown, !analysis.actionFamily.isSupported(by: candidate.element.element) {
            return nil
        }

        var reasons = baseReasons(
            failureKind: analysis.failureKind,
            currentResolution: analysis.currentResolution,
            selection: selection,
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        )
        reasons.append(contentsOf: candidate.reasons.map(RepairSuggestionReason.scoring))
        reasons.append(contentsOf: afterEvidenceReasons(
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        ))

        var caveats = candidate.caveats
        if selection.candidate.tier == .ordinalDisambiguation,
           !request.lastSuccess.target.hasOrdinal {
            caveats.append(.ordinalDisambiguation)
        }
        if tiedBestCount > 1 {
            caveats.append(.tiedBestCandidates)
        }
        if request.lastSuccess.afterDelta == nil, request.lastSuccess.afterSnapshot != nil {
            caveats.append(.lastSuccessfulFullAfterSnapshotFallback)
        }
        if request.currentFailure.afterDelta == nil, request.currentFailure.afterSnapshot != nil {
            caveats.append(.currentFailureFullAfterSnapshotFallback)
        }

        return HeistRepairSuggestion(
            stepPath: request.currentFailure.stepPath,
            failureKind: analysis.failureKind,
            oldTarget: request.lastSuccess.target,
            oldResolvedElement: analysis.oldResolved.summary,
            newTarget: selection.target,
            newResolvedElement: candidate.element.summary,
            confidence: confidence(
                score: candidate.score,
                selection: selection,
                oldTargetHadOrdinal: request.lastSuccess.target.hasOrdinal,
                tiedBestCount: tiedBestCount,
                failureKind: analysis.failureKind
            ),
            reasons: reasons,
            caveats: caveats
        )
    }

    private static func baseReasons(
        failureKind: HeistRepairFailureKind,
        currentResolution: RepairTargetResolution,
        selection: MinimumPredicateSelection,
        lastSuccess: HeistPassedStepRepairEvidence,
        currentFailure: HeistFailedStepRepairEvidence
    ) -> [RepairSuggestionReason] {
        var reasons: [RepairSuggestionReason] = [
            .oldTargetResolvedInLastSuccessfulSnapshot,
        ]
        switch currentResolution {
        case .resolved:
            reasons.append(.oldTargetResolvesWithoutRequestedAction)
        case .notFound(let matchCount):
            reasons.append(.oldTargetCurrentMatchCount(matchCount))
        case .ambiguous(_, let matchCount):
            reasons.append(.oldTargetCurrentMatchCount(matchCount))
        }
        reasons.append(.suggestedMatcherResolvesExactlyOneElement)
        if selection.candidate.tier == .ordinalDisambiguation {
            reasons.append(.noSemanticOnlyMatcherUnique)
        }
        if lastSuccess.target != currentFailure.target {
            reasons.append(.currentFailureSuppliedDifferentTarget)
        }
        if failureKind == .missingTarget {
            reasons.append(.missingTargetSuccessorSelected)
        }
        if failureKind == .ambiguousTarget {
            reasons.append(.ambiguousTargetSuccessorSelected)
        }
        return reasons
    }

    private static func afterEvidenceReasons(
        lastSuccess: HeistPassedStepRepairEvidence,
        currentFailure: HeistFailedStepRepairEvidence
    ) -> [RepairSuggestionReason] {
        var reasons: [RepairSuggestionReason] = []
        if let reason = deltaReason(source: .lastSuccess, delta: lastSuccess.afterDelta) {
            reasons.append(reason)
        }
        if let reason = deltaReason(source: .currentFailure, delta: currentFailure.afterDelta) {
            reasons.append(reason)
        }
        if let expectation = lastSuccess.result.expectation, expectation.met {
            reasons.append(.lastSuccessfulExpectationMet)
        }
        if let expectation = currentFailure.result.expectation, !expectation.met {
            reasons.append(.currentFailureExpectationUnmet)
        }
        return reasons
    }

    private static func deltaReason(
        source: RepairEvidenceSource,
        delta: AccessibilityTrace.Delta?
    ) -> RepairSuggestionReason? {
        guard let delta else { return nil }
        switch delta {
        case .noChange:
            return .afterDiff(source, .noSemanticChange)
        case .screenChanged:
            return .afterDiff(source, .screenChange)
        case .elementsChanged(let payload):
            if let valueChange = payload.edits.updated
                .flatMap(\.changes)
                .first(where: { $0.property == .value }) {
                return .afterDiff(
                    source,
                    .valueChange(old: valueChange.oldDisplayText, new: valueChange.newDisplayText)
                )
            }
            if !payload.edits.added.isEmpty {
                return .afterDiff(source, .semanticElementsAdded)
            }
            if !payload.edits.removed.isEmpty {
                return .afterDiff(source, .semanticElementsRemoved)
            }
            return .afterDiff(source, .elementChanges)
        }
    }

    private static func confidence(
        score: Int,
        selection: MinimumPredicateSelection,
        oldTargetHadOrdinal: Bool,
        tiedBestCount: Int,
        failureKind: HeistRepairFailureKind
    ) -> RepairConfidence {
        if selection.candidate.tier == .ordinalDisambiguation, !oldTargetHadOrdinal {
            return .low
        }
        if tiedBestCount > 1 {
            return .low
        }
        if failureKind == .wrongCapability {
            return .low
        }
        if score >= 120 {
            return .high
        }
        if score >= 75 {
            return .medium
        }
        return .low
    }
}

extension HeistRepairIneligibility {
    var noSuggestionReason: String {
        switch self {
        case .differentStepPaths:
            return "receipts refer to different step paths"
        case .incompatibleHeistFingerprints:
            return "heist fingerprints are incompatible"
        case .oldTargetDidNotResolveExactlyOnce:
            return "old target did not resolve exactly once in the last successful before snapshot"
        case .oldTargetStillResolvesAndSupportsRequestedAction:
            return "old target still resolves and supports the requested action; no target repair needed"
        }
    }
}

// Decode-only bridge for the stable public JSON shape, which renders reasons
// and caveats as prose while core suggestions keep typed facts.
extension RepairSuggestionReason {
    init?(prose: String) {
        switch prose {
        case Self.oldTargetResolvedInLastSuccessfulSnapshot.prose:
            self = .oldTargetResolvedInLastSuccessfulSnapshot
        case Self.oldTargetResolvesWithoutRequestedAction.prose:
            self = .oldTargetResolvesWithoutRequestedAction
        case Self.suggestedMatcherResolvesExactlyOneElement.prose:
            self = .suggestedMatcherResolvesExactlyOneElement
        case Self.noSemanticOnlyMatcherUnique.prose:
            self = .noSemanticOnlyMatcherUnique
        case Self.currentFailureSuppliedDifferentTarget.prose:
            self = .currentFailureSuppliedDifferentTarget
        case Self.missingTargetSuccessorSelected.prose:
            self = .missingTargetSuccessorSelected
        case Self.ambiguousTargetSuccessorSelected.prose:
            self = .ambiguousTargetSuccessorSelected
        case Self.lastSuccessfulExpectationMet.prose:
            self = .lastSuccessfulExpectationMet
        case Self.currentFailureExpectationUnmet.prose:
            self = .currentFailureExpectationUnmet
        default:
            if let reason = RepairScoringReason(prose: prose) {
                self = .scoring(reason)
                return
            }
            if let matchCount = prose.matchCountReasonValue {
                self = .oldTargetCurrentMatchCount(matchCount)
                return
            }
            if let afterDiff = prose.afterDiffReasonValue {
                self = afterDiff
                return
            }
            return nil
        }
    }
}

extension RepairScoringReason {
    init?(prose: String) {
        switch prose {
        case Self.oldTargetIsCurrentMatch.prose:
            self = .oldTargetIsCurrentMatch
        case Self.identifierUnchanged.prose:
            self = .identifierUnchanged
        case Self.labelUnchanged.prose:
            self = .labelUnchanged
        case Self.labelSemanticRename.prose:
            self = .labelSemanticRename
        case Self.valueUnchanged.prose:
            self = .valueUnchanged
        case Self.valueSemanticRename.prose:
            self = .valueSemanticRename
        case Self.controlRoleTraitsCompatible.prose:
            self = .controlRoleTraitsCompatible
        case Self.elementActionsCompatible.prose:
            self = .elementActionsCompatible
        case Self.rotorCapabilityCompatible.prose:
            self = .rotorCapabilityCompatible
        case Self.siblingRowContextPreserved.prose:
            self = .siblingRowContextPreserved
        case Self.headerContextPreserved.prose:
            self = .headerContextPreserved
        case Self.afterDiffEvidenceMatchesElement.prose:
            self = .afterDiffEvidenceMatchesElement
        case Self.expectationEvidenceMatchesElement.prose:
            self = .expectationEvidenceMatchesElement
        case Self.onlyCurrentSemanticCandidate.prose:
            self = .onlyCurrentSemanticCandidate
        case Self.elementSupportsSameActionFamily.prose:
            self = .elementSupportsSameActionFamily
        case Self.onlyCurrentElementWithCompatibleActionFamily.prose:
            self = .onlyCurrentElementWithCompatibleActionFamily
        default:
            return nil
        }
    }
}

extension RepairCaveat {
    init?(prose: String) {
        switch prose {
        case Self.candidateDoesNotExposeSameActionFamily.prose:
            self = .candidateDoesNotExposeSameActionFamily
        case Self.ordinalDisambiguation.prose:
            self = .ordinalDisambiguation
        case Self.tiedBestCandidates.prose:
            self = .tiedBestCandidates
        case Self.lastSuccessfulFullAfterSnapshotFallback.prose:
            self = .lastSuccessfulFullAfterSnapshotFallback
        case Self.currentFailureFullAfterSnapshotFallback.prose:
            self = .currentFailureFullAfterSnapshotFallback
        default:
            return nil
        }
    }
}

private extension String {
    var matchCountReasonValue: Int? {
        let prefix = "Old target resolves to "
        let suffix = " elements in the new before snapshot."
        guard hasPrefix(prefix), hasSuffix(suffix) else { return nil }
        let value = dropFirst(prefix.count).dropLast(suffix.count)
        return Int(value)
    }

    var afterDiffReasonValue: RepairSuggestionReason? {
        let sources: [(RepairEvidenceSource, String)] = [
            (.lastSuccess, RepairEvidenceSource.lastSuccess.afterDiffPrefix),
            (.currentFailure, RepairEvidenceSource.currentFailure.afterDiffPrefix),
        ]
        for (source, prefix) in sources {
            guard hasPrefix(prefix + " "), hasSuffix(".") else { continue }
            let observationText = dropFirst(prefix.count + 1).dropLast()
            guard let observation = RepairAfterDiffObservation(prose: String(observationText)) else {
                return nil
            }
            return .afterDiff(source, observation)
        }
        return nil
    }
}

private extension RepairAfterDiffObservation {
    init?(prose: String) {
        switch prose {
        case Self.noSemanticChange.prose:
            self = .noSemanticChange
        case Self.screenChange.prose:
            self = .screenChange
        case Self.semanticElementsAdded.prose:
            self = .semanticElementsAdded
        case Self.semanticElementsRemoved.prose:
            self = .semanticElementsRemoved
        case Self.elementChanges.prose:
            self = .elementChanges
        default:
            let prefix = "observed value change from "
            guard prose.hasPrefix(prefix) else { return nil }
            let valueText = prose.dropFirst(prefix.count)
            guard let separator = valueText.range(of: " to ") else { return nil }
            self = .valueChange(
                old: valueText[..<separator.lowerBound].nilIfRenderedNil,
                new: valueText[separator.upperBound...].nilIfRenderedNil
            )
        }
    }
}

private extension Substring {
    var nilIfRenderedNil: String? {
        self == "nil" ? nil : String(self)
    }
}
