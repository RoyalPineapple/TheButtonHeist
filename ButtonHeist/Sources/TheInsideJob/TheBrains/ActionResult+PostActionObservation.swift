#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

extension ActionResult {
    @MainActor init(
        outcome: TheSafecracker.ActionDispatchOutcome,
        afterStatePayload: ((PostActionPayloadContext) -> ActionResultPayload?)?,
        settledObservation: PostActionObservation.SettledObservationResult
    ) {
        let resultOutcome = settledObservation.resultOutcome(for: outcome)
        let message = settledObservation.message(explicit: outcome.message)
        let payload = settledObservation.payload(for: outcome, afterStatePayload: afterStatePayload)
        let duration: ActionSettlementDuration
        do {
            duration = try ActionSettlementDuration(
                validatingMilliseconds: settledObservation.settleTimeMs
            )
        } catch {
            self = ActionResult.failure(
                method: outcome.method,
                errorKind: .actionFailed,
                message: String(describing: error),
                observation: .trace(settledObservation.traceEvidence),
                subjectEvidence: outcome.subjectEvidence
            )
            return
        }
        let settlement: ActionSettlementEvidence = settledObservation.settled
            ? .settled(duration: duration)
            : .timedOut(duration: duration)
        let observation = ActionResultObservationEvidence.settledTrace(
            settledObservation.traceEvidence,
            settlement
        )
        switch resultOutcome {
        case .success:
            if let activationTrace = outcome.activationTrace {
                self = ActionResult.activationSuccess(
                    message: message,
                    observation: observation,
                    subjectEvidence: outcome.subjectEvidence,
                    activationTrace: activationTrace
                )
            } else if let payload {
                self = ActionResult.success(
                    payload: payload,
                    message: message,
                    observation: observation,
                    subjectEvidence: outcome.subjectEvidence
                )
            } else {
                self = ActionResult.success(
                    method: outcome.method,
                    message: message,
                    observation: observation,
                    subjectEvidence: outcome.subjectEvidence
                )
            }
        case .failure(let errorKind):
            if let activationTrace = outcome.activationTrace {
                self = ActionResult.activationFailure(
                    errorKind: errorKind,
                    message: message,
                    observation: observation,
                    subjectEvidence: outcome.subjectEvidence,
                    activationTrace: activationTrace
                )
            } else if let payload {
                self = ActionResult.failure(
                    payload: payload,
                    errorKind: errorKind,
                    message: message,
                    observation: observation,
                    subjectEvidence: outcome.subjectEvidence
                )
            } else {
                self = ActionResult.failure(
                    method: outcome.method,
                    errorKind: errorKind,
                    message: message,
                    observation: observation,
                    subjectEvidence: outcome.subjectEvidence
                )
            }
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
        for outcome: TheSafecracker.ActionDispatchOutcome
    ) -> ActionResultOutcome {
        switch self {
        case .committed, .diagnostic:
            switch outcome.state {
            case .success:
                return .success
            case .failure(let failureKind):
                return .failure(TheBrains.actionErrorKind(for: failureKind))
            }
        case .unavailable:
            return .failure(.actionFailed)
        }
    }

    func payload(
        for outcome: TheSafecracker.ActionDispatchOutcome,
        afterStatePayload: ((PostActionPayloadContext) -> ActionResultPayload?)?
    ) -> ActionResultPayload? {
        guard case .success(let payload, let resolvedElementId) = outcome.state else { return nil }
        if let payload { return payload }
        guard let afterStatePayload else { return nil }
        guard case .committed(_, let finalState, _) = self else { return nil }
        return afterStatePayload(PostActionPayloadContext(
            afterState: finalState,
            resolvedElementId: resolvedElementId
        ))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
