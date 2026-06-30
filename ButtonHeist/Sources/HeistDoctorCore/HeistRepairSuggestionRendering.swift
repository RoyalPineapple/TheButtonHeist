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
            reasons: unique(reasons).map(\.prose),
            caveats: unique(caveats).map(\.prose)
        )
    }

    private static func baseReasons(
        failureKind: HeistRepairFailureKind,
        currentResolution: RepairTargetResolution,
        selection: MinimumPredicateSelection,
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
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
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
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
        case .lastReceiptStepDidNotPass:
            return "last receipt step did not pass"
        case .currentReceiptStepDidNotFail:
            return "current receipt step did not fail"
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
