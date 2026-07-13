#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

extension ActionResult {
    @MainActor init(
        postActionMethod method: ActionMethod,
        outcome: PostActionObservation.ActionOutcome,
        message: String?,
        settledObservation: PostActionObservation.SettledObservationResult
    ) {
        let resultOutcome = settledObservation.resultOutcome(for: outcome)
        let message = settledObservation.message(explicit: message)
        let payload = settledObservation.payload(for: outcome)
        let settlement: ActionSettlementEvidence = settledObservation.settled
            ? .settled(durationMs: settledObservation.settleTimeMs)
            : .timedOut(durationMs: settledObservation.settleTimeMs)
        let observation = ActionResultObservationEvidence.settledTrace(
            settledObservation.traceEvidence,
            settlement
        )
        switch resultOutcome {
        case .success:
            let evidence = ActionResultSuccessEvidence(
                observation: observation,
                subjectEvidence: outcome.subjectEvidence,
                activationTrace: outcome.activationTrace,
                warning: Self.warning(method: method, subjectEvidence: outcome.subjectEvidence)
            )
            self = payload.map { ActionResult.success(payload: $0, message: message, evidence: evidence) }
                ?? ActionResult.success(method: method, message: message, evidence: evidence)
        case .failure(let errorKind):
            let evidence = ActionResultFailureEvidence(
                observation: observation,
                subjectEvidence: outcome.subjectEvidence,
                activationTrace: outcome.activationTrace
            )
            self = payload.map {
                ActionResult.failure(payload: $0, errorKind: errorKind, message: message, evidence: evidence)
            } ?? ActionResult.failure(method: method, errorKind: errorKind, message: message, evidence: evidence)
        }
    }

    private static func warning(
        method: ActionMethod,
        subjectEvidence: ActionSubjectEvidence?
    ) -> HeistActionWarning? {
        guard let element = subjectEvidence?.element else { return nil }
        let evidence = ElementDiagnosticSummary(
            label: element.label,
            identifier: element.identifier,
            traits: AccessibilityPolicy.orderedMatcherTraits(element.traits),
            actions: element.actions.sorted { $0.description < $1.description }
        ).rendered(using: .activationAffordanceEvidence)

        switch method {
        case .activate where !AccessibilityPolicy.advertisesActivationAffordance(element.traits):
            return .activationWeakAffordance(evidence: evidence)
        case .typeText where !AccessibilityPolicy.supportsTextEntry(element.traits):
            return .textEntryWeakAffordance(evidence: evidence)
        default:
            return nil
        }
    }
}

extension PostActionObservation.SettledObservationResult {
    var traceEvidence: AccessibilityTraceEvidence {
        guard let evidence = AccessibilityTraceEvidence(
            trace: accessibilityTrace,
            completeness: .incomplete
        ) else {
            preconditionFailure("post-action observation requires a current accessibility capture")
        }
        return evidence
    }

    var accessibilityTrace: AccessibilityTrace {
        switch self {
        case .committed(_, _, let trace), .diagnostic(_, let trace):
            return trace
        case .unavailable(_, let trace, _):
            return trace
        }
    }

    var settled: Bool {
        if case .committed = self { return true }
        return false
    }

    var settleTimeMs: Int {
        settle.outcome.timeMs
    }

    private var settle: SettleSession.Outcome {
        switch self {
        case .committed(let settle, _, _),
             .diagnostic(let settle, _),
             .unavailable(let settle, _, _):
            return settle
        }
    }

    func message(explicit message: String?) -> String? {
        switch self {
        case .committed, .diagnostic:
            return message
        case .unavailable(_, _, let failureMessage):
            return failureMessage
        }
    }

    func resultOutcome(
        for outcome: PostActionObservation.ActionOutcome
    ) -> ActionResultOutcome {
        switch self {
        case .committed, .diagnostic:
            return outcome.resultOutcome
        case .unavailable:
            return .failure(.actionFailed)
        }
    }

    func payload(
        for outcome: PostActionObservation.ActionOutcome
    ) -> ActionResultPayload? {
        switch self {
        case .committed(_, let finalState, _):
            return outcome.resolvedPayload(after: finalState)
        case .diagnostic, .unavailable:
            return outcome.immediatePayload
        }
    }
}

extension PostActionObservation.ResolvedActionOutcomePayload {
    var payload: ActionResultPayload? {
        switch self {
        case .none:
            return nil
        case .payload(let payload):
            return payload
        }
    }
}

private extension PostActionObservation.ActionOutcomePayload {
    var immediatePayload: ActionResultPayload? {
        switch self {
        case .none, .afterState:
            return nil
        case .immediate(let payload):
            return payload
        }
    }

    func resolvedPayload(after state: PostActionObservation.BeforeState) -> ActionResultPayload? {
        switch self {
        case .none:
            return nil
        case .immediate(let payload):
            return payload
        case .afterState(let resolve):
            return resolve(state).payload
        }
    }
}

private extension PostActionObservation.ActionOutcome {
    var resultOutcome: ActionResultOutcome {
        switch self {
        case .success:
            return .success
        case .failure(let failure):
            return .failure(failure.errorKind)
        }
    }

    var immediatePayload: ActionResultPayload? {
        switch self {
        case .success(let success):
            return success.payload.immediatePayload
        case .failure(let failure):
            return failure.payload.immediatePayload
        }
    }

    var subjectEvidence: ActionSubjectEvidence? {
        switch self {
        case .success(let success):
            return success.subjectEvidence
        case .failure(let failure):
            return failure.subjectEvidence
        }
    }

    var activationTrace: ActivationTrace? {
        switch self {
        case .success(let success):
            return success.activationTrace
        case .failure(let failure):
            return failure.activationTrace
        }
    }

    func resolvedPayload(after state: PostActionObservation.BeforeState) -> ActionResultPayload? {
        switch self {
        case .success(let success):
            return success.payload.resolvedPayload(after: state)
        case .failure(let failure):
            return failure.payload.immediatePayload
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
