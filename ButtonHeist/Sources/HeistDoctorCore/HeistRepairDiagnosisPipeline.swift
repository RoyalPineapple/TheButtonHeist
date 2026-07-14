import ThePlans
import TheScore

private let minimumRepairSuggestionScore = 55

enum RepairDiagnosisPipeline {
    static func run(_ request: HeistRepairRequest) -> HeistRepairDiagnosis {
        let analysis = HeistRepairAnalysis.analyze(request)
        let eligibleAnalysis: HeistEligibleRepairAnalysis
        switch analysis {
        case .ineligible(let reason):
            return refusedDiagnosis(
                for: request,
                reason: reason,
                message: HeistRepairSuggestionRenderer.noSuggestionReason(for: analysis),
                stage: .evidenceEligibility
            )
        case .eligible(let analysis):
            eligibleAnalysis = analysis
        }

        guard let bestScore = eligibleAnalysis.rankedCandidates.first?.score,
              bestScore >= minimumRepairSuggestionScore else {
            return refusedDiagnosis(
                for: request,
                analysis: eligibleAnalysis,
                candidates: candidateDiagnoses(for: eligibleAnalysis, evaluations: [:]),
                reason: .noCandidateMetScoreThreshold,
                message: HeistRepairSuggestionRenderer.noSuggestionReason(for: analysis),
                stage: .candidateRanking
            )
        }

        let tiedBest = Array(eligibleAnalysis.rankedCandidates.prefix { $0.score == bestScore })
        let evaluations = Dictionary(uniqueKeysWithValues: tiedBest.prefix(3).map { candidate in
            let validation = HeistRepairSuggestionRenderer.validateSuggestion(
                for: candidate,
                analysis: eligibleAnalysis,
                request: request,
                tiedBestCount: tiedBest.count
            )
            return (candidate.element.id, validation)
        })

        let candidates = candidateDiagnoses(for: eligibleAnalysis, evaluations: evaluations)
        let suggestions = tiedBest.prefix(3).compactMap { candidate -> HeistRepairSuggestion? in
            guard case .suggested(let suggestion) = evaluations[candidate.element.id] else { return nil }
            return suggestion
        }
        guard !suggestions.isEmpty else {
            return refusedDiagnosis(
                for: request,
                analysis: eligibleAnalysis,
                candidates: candidates,
                reason: .noCandidateValidated,
                message: HeistRepairSuggestionRenderer.noSuggestionReason(for: analysis),
                stage: .candidateValidation
            )
        }

        return .suggested(HeistRepairSuggestedDiagnosis(
            stepPath: request.currentFailure.stepPath,
            failureKind: eligibleAnalysis.failureKind,
            oldTarget: request.lastSuccess.target,
            oldResolvedElement: eligibleAnalysis.oldResolved.repairContext,
            currentMatchCount: eligibleAnalysis.currentResolution.matchCount,
            candidates: candidates,
            suggestions: suggestions
        ))
    }

    private static func candidateDiagnoses(
        for analysis: HeistEligibleRepairAnalysis,
        evaluations: [PredicateSelectionElementId: RepairSuggestionValidation]
    ) -> [HeistRepairCandidateDiagnosis] {
        analysis.rankedCandidates.map { candidate in
            let evaluation = evaluations[candidate.element.id]
            return HeistRepairCandidateDiagnosis(
                source: analysis.preferredCandidates.contains(candidate.element.id)
                    ? .currentAmbiguousMatch
                    : .semanticContinuityScan,
                resolvedElement: candidate.element.repairContext,
                score: candidate.score,
                reasons: candidate.reasons,
                caveats: candidate.caveats,
                validation: validation(for: evaluation)
            )
        }
    }

    private static func validation(
        for evaluation: RepairSuggestionValidation?
    ) -> RepairCandidateValidation {
        switch evaluation {
        case .suggested(let suggestion):
            return .suggested(target: suggestion.newTarget, confidence: suggestion.confidence)
        case .rejected(let reason):
            return .rejected(reason: reason)
        case nil:
            return .notEvaluated
        }
    }

    private static func refusedDiagnosis(
        for request: HeistRepairRequest,
        reason: HeistRepairRefusalReason,
        message: String,
        stage: HeistRepairPipelineStage
    ) -> HeistRepairDiagnosis {
        .refused(HeistRepairRefusedDiagnosis(
            stepPath: request.currentFailure.stepPath,
            oldTarget: request.lastSuccess.target,
            context: .evidenceEligibility,
            refusal: HeistRepairRefusal(stage: stage, reason: reason, message: message)
        ))
    }

    private static func refusedDiagnosis(
        for request: HeistRepairRequest,
        analysis: HeistEligibleRepairAnalysis,
        candidates: [HeistRepairCandidateDiagnosis],
        reason: HeistRepairRefusalReason,
        message: String,
        stage: HeistRepairPipelineStage
    ) -> HeistRepairDiagnosis {
        .refused(HeistRepairRefusedDiagnosis(
            stepPath: request.currentFailure.stepPath,
            oldTarget: request.lastSuccess.target,
            context: .eligible(HeistRepairEligibleRefusalContext(
                failureKind: analysis.failureKind,
                oldResolvedElement: analysis.oldResolved.repairContext,
                currentMatchCount: analysis.currentResolution.matchCount,
                candidates: candidates
            )),
            refusal: HeistRepairRefusal(stage: stage, reason: reason, message: message)
        ))
    }

}

private extension RepairTargetResolution {
    var matchCount: Int {
        switch self {
        case .resolved(_, let matchCount),
             .notFound(let matchCount),
             .ambiguous(_, let matchCount):
            return matchCount
        case .unsupportedTarget:
            return 0
        }
    }
}
