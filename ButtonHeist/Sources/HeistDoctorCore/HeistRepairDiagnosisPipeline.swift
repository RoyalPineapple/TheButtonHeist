import ButtonHeistSupport
import ThePlans
import TheScore

private let minimumRepairSuggestionScore = 55

enum RepairDiagnosisPipeline {
    static func run(_ request: HeistRepairRequest) -> HeistRepairDiagnosis {
        var driver = StateDriver(initial: RepairDiagnosisPipelineState.ready, machine: RepairDiagnosisPipelineMachine())
        let analysis = HeistRepairAnalysis.analyze(request)
        guard case .eligible(let eligibleAnalysis) = analysis else {
            send(.refuse, to: &driver)
            return refusedDiagnosis(
                for: request,
                reason: ineligibilityReason(from: analysis),
                message: HeistRepairSuggestionRenderer.noSuggestionReason(for: analysis),
                stage: .evidenceEligibility
            )
        }

        send(.analysisAccepted, to: &driver)
        send(.rankCandidates, to: &driver)

        guard let bestScore = eligibleAnalysis.rankedCandidates.first?.score,
              bestScore >= minimumRepairSuggestionScore else {
            send(.refuse, to: &driver)
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
        send(.validateCandidates, to: &driver)

        let candidates = candidateDiagnoses(for: eligibleAnalysis, evaluations: evaluations)
        let suggestions = tiedBest.prefix(3).compactMap { candidate -> HeistRepairSuggestion? in
            guard case .suggested(let suggestion) = evaluations[candidate.element.id] else { return nil }
            return suggestion
        }
        guard !suggestions.isEmpty else {
            send(.refuse, to: &driver)
            return refusedDiagnosis(
                for: request,
                analysis: eligibleAnalysis,
                candidates: candidates,
                reason: .noCandidateValidated,
                message: HeistRepairSuggestionRenderer.noSuggestionReason(for: analysis),
                stage: .candidateValidation
            )
        }

        send(.finish, to: &driver)
        return HeistRepairDiagnosis(
            status: .suggested,
            stepPath: request.currentFailure.stepPath,
            failureKind: eligibleAnalysis.failureKind,
            oldTarget: request.lastSuccess.target,
            oldResolvedElement: eligibleAnalysis.oldResolved.summary,
            currentMatchCount: eligibleAnalysis.currentResolution.matchCount,
            candidates: candidates,
            suggestions: suggestions,
            refusal: nil
        )
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
                resolvedElement: candidate.element.summary,
                score: candidate.score,
                reasons: candidate.reasons,
                caveats: candidate.caveats,
                validationStatus: validationStatus(for: evaluation),
                suggestedTarget: suggestedTarget(from: evaluation),
                confidence: confidence(from: evaluation),
                rejectionReason: rejectionReason(from: evaluation)
            )
        }
    }

    private static func validationStatus(
        for evaluation: RepairSuggestionValidation?
    ) -> RepairCandidateValidationStatus {
        switch evaluation {
        case .suggested:
            return .suggested
        case .rejected:
            return .rejected
        case nil:
            return .notEvaluated
        }
    }

    private static func suggestedTarget(from evaluation: RepairSuggestionValidation?) -> ElementTarget? {
        guard case .suggested(let suggestion) = evaluation else { return nil }
        return suggestion.newTarget
    }

    private static func confidence(from evaluation: RepairSuggestionValidation?) -> RepairConfidence? {
        guard case .suggested(let suggestion) = evaluation else { return nil }
        return suggestion.confidence
    }

    private static func rejectionReason(from evaluation: RepairSuggestionValidation?) -> RepairCandidateRejectionReason? {
        guard case .rejected(let reason) = evaluation else { return nil }
        return reason
    }

    private static func refusedDiagnosis(
        for request: HeistRepairRequest,
        reason: HeistRepairRefusalReason,
        message: String,
        stage: HeistRepairPipelineStage
    ) -> HeistRepairDiagnosis {
        HeistRepairDiagnosis(
            status: .refused,
            stepPath: request.currentFailure.stepPath,
            failureKind: nil,
            oldTarget: request.lastSuccess.target,
            refusal: HeistRepairRefusal(stage: stage, reason: reason, message: message)
        )
    }

    private static func refusedDiagnosis(
        for request: HeistRepairRequest,
        analysis: HeistEligibleRepairAnalysis,
        candidates: [HeistRepairCandidateDiagnosis],
        reason: HeistRepairRefusalReason,
        message: String,
        stage: HeistRepairPipelineStage
    ) -> HeistRepairDiagnosis {
        HeistRepairDiagnosis(
            status: .refused,
            stepPath: request.currentFailure.stepPath,
            failureKind: analysis.failureKind,
            oldTarget: request.lastSuccess.target,
            oldResolvedElement: analysis.oldResolved.summary,
            currentMatchCount: analysis.currentResolution.matchCount,
            candidates: candidates,
            refusal: HeistRepairRefusal(stage: stage, reason: reason, message: message)
        )
    }

    private static func ineligibilityReason(from analysis: HeistRepairAnalysis) -> HeistRepairRefusalReason {
        guard case .ineligible(let reason) = analysis else {
            return .noCandidateValidated
        }
        switch reason {
        case .differentStepPaths:
            return .differentStepPaths
        case .incompatibleHeistFingerprints:
            return .incompatibleHeistFingerprints
        case .oldTargetDidNotResolveExactlyOnce:
            return .oldTargetDidNotResolveExactlyOnce
        case .oldTargetStillResolvesAndSupportsRequestedAction:
            return .oldTargetStillResolvesAndSupportsRequestedAction
        }
    }

    private static func send(
        _ event: RepairDiagnosisPipelineEvent,
        to driver: inout StateDriver<RepairDiagnosisPipelineMachine>
    ) {
        let change = driver.send(event)
        guard case .rejected(let rejection, let state) = change else { return }
        preconditionFailure("Invalid repair diagnosis transition \(event) from \(state): \(rejection)")
    }
}

private enum RepairDiagnosisPipelineState: Equatable, Sendable {
    case ready
    case analyzed
    case ranked
    case validated
    case finished
}

private enum RepairDiagnosisPipelineEvent: Equatable, Sendable {
    case analysisAccepted
    case rankCandidates
    case validateCandidates
    case refuse
    case finish
}

private enum RepairDiagnosisPipelineEffect: Equatable, Sendable {
    case acceptedAnalysis
    case rankedCandidates
    case validatedCandidates
    case finished
}

private enum RepairDiagnosisPipelineRejection: Equatable, Sendable {
    case invalidTransition
}

private struct RepairDiagnosisPipelineMachine: SimpleStateMachine {
    func advance(
        _ state: RepairDiagnosisPipelineState,
        with event: RepairDiagnosisPipelineEvent
    ) -> StateChange<RepairDiagnosisPipelineState, RepairDiagnosisPipelineEffect, RepairDiagnosisPipelineRejection> {
        switch (state, event) {
        case (.ready, .analysisAccepted):
            return .changed(to: .analyzed, effects: [.acceptedAnalysis])
        case (.analyzed, .rankCandidates):
            return .changed(to: .ranked, effects: [.rankedCandidates])
        case (.ranked, .validateCandidates):
            return .changed(to: .validated, effects: [.validatedCandidates])
        case (.ready, .refuse),
             (.ranked, .refuse),
             (.validated, .refuse):
            return .changed(to: .finished, effects: [.finished])
        case (.validated, .finish):
            return .changed(to: .finished, effects: [.finished])
        default:
            return .rejected(.invalidTransition, stayingIn: state)
        }
    }
}

private extension RepairTargetResolution {
    var matchCount: Int {
        switch self {
        case .resolved(_, let matchCount),
             .notFound(let matchCount),
             .ambiguous(_, let matchCount):
            return matchCount
        }
    }
}
