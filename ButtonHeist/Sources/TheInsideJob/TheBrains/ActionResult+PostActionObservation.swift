#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

extension ActionResult {
    @MainActor init(
        outcome: TheSafecracker.ActionDispatchOutcome,
        afterStatePayload: ((PostActionPayloadContext) -> ActionResultPayload?)?,
        settledObservation: PostActionObservation.SettlementResult
    ) {
        let resultOutcome = settledObservation.resultOutcome(for: outcome)
        let message = settledObservation.message(explicit: outcome.message)
        let payload = settledObservation.payload(for: outcome, afterStatePayload: afterStatePayload)
        let methodAndPayload = payload.map(ActionResult.MethodAndPayload.payload)
            ?? .methodOnly(outcome.method)
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
        self = ActionResult(
            outcome: resultOutcome,
            methodAndPayload: methodAndPayload,
            message: message,
            observation: observation,
            subjectEvidence: outcome.subjectEvidence,
            activationTrace: outcome.activationTrace
        )
    }
}

extension PostActionObservation.SettlementResult {
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
        guard case .committed(_, let finalBaseline, _) = self else { return nil }
        return afterStatePayload(PostActionPayloadContext(
            baseline: finalBaseline,
            resolvedElementId: resolvedElementId
        ))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
