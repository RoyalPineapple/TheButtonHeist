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

    static func validateSuggestion(
        for candidate: ScoredCandidate,
        analysis: HeistEligibleRepairAnalysis,
        request: HeistRepairRequest,
        tiedBestCount: Int
    ) -> RepairSuggestionValidation {
        let currentScreen = analysis.currentScreen
        let selectionContext = currentScreen.selectionContext()
        guard let selection = MinimumPredicateSelector.minimumUniquePredicate(
            for: candidate.element.id,
            in: selectionContext
        ),
              case .resolved(let validation, _) = currentScreen.resolve(selection.target),
              validation.id == candidate.element.id
        else {
            return .rejected(.noUniqueDurableMatcher)
        }

        if analysis.actionFamily.isKnown, !analysis.actionFamily.isSupported(by: candidate.element.element) {
            return .rejected(.unsupportedActionFamily)
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
        return .suggested(HeistRepairSuggestion(
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
        ))
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
        case .unsupportedTarget:
            break
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
        var reasons = changeFactReasons(source: .lastSuccess, facts: lastSuccess.changeFacts)
        reasons.append(contentsOf: changeFactReasons(source: .currentFailure, facts: currentFailure.changeFacts))
        if let expectation = lastSuccess.result.expectation, expectation.met {
            reasons.append(.lastSuccessfulExpectationMet)
        }
        if let expectation = currentFailure.result.expectation, !expectation.met {
            reasons.append(.currentFailureExpectationUnmet)
        }
        return reasons
    }

    private static func changeFactReasons(
        source: RepairEvidenceSource,
        facts: [AccessibilityTrace.ChangeFact]
    ) -> [RepairSuggestionReason] {
        guard !facts.isEmpty else {
            return [.changeFact(source, .noSemanticChange)]
        }
        return facts.flatMap { fact in
            changeFactObservations(fact).map { .changeFact(source, $0) }
        }
    }

    private static func changeFactObservations(
        _ fact: AccessibilityTrace.ChangeFact
    ) -> [RepairChangeFactObservation] {
        switch fact {
        case .screenChanged:
            return [.screenChange]
        case .elementsChanged(let elements):
            let valueChanges = elements.updated.flatMap(\.changes)
                .filter { $0.property == .value }
                .map { RepairChangeFactObservation.valueChange(
                    old: $0.oldDisplayText,
                    new: $0.newDisplayText
                ) }
            var observations: [RepairChangeFactObservation] = []
            if !elements.disappeared.isEmpty {
                observations.append(.semanticElementsRemoved)
            }
            if !elements.appeared.isEmpty {
                observations.append(.semanticElementsAdded)
            }
            observations.append(contentsOf: valueChanges)
            if observations.isEmpty {
                observations.append(.elementChanges)
            }
            return observations
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

enum RepairSuggestionValidation: Sendable, Equatable {
    case suggested(HeistRepairSuggestion)
    case rejected(RepairCandidateRejectionReason)
}

extension HeistRepairRefusalReason {
    var noSuggestionReason: String {
        switch self {
        case .differentStepPaths:
            return "receipts refer to different step paths"
        case .incompatibleHeistFingerprints:
            return "heist fingerprints are incompatible"
        case .oldTargetDidNotResolveExactlyOnce:
            return "old target did not resolve exactly once in the last successful before snapshot"
        case .containerTargetUnsupported:
            return "container-only targets are not repairable as accessibility elements"
        case .targetReferenceUnsupported:
            return "unresolved target references are not repairable without their execution environment"
        case .scopedTargetUnsupported:
            return "container-scoped targets are not repairable without container-aware repair resolution"
        case .unresolvedTargetExpression:
            return "target expressions are not repairable without all referenced values"
        case .oldTargetStillResolvesAndSupportsRequestedAction:
            return "old target still resolves and supports the requested action; no target repair needed"
        case .noCandidateMetScoreThreshold:
            return "no candidate met the repair score threshold"
        case .noCandidateValidated:
            return "no candidate passed repair validation"
        }
    }
}
