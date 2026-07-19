#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

extension ActionResult {
    @MainActor init(
        dispatchResult: TheSafecracker.ActionDispatchResult,
        afterStatePayload: ((ActionPayloadEvidence) -> ActionResultPayload?)?,
        settledObservation: ActionEvidenceProjector.Result
    ) {
        let resultOutcome = settledObservation.resultOutcome(for: dispatchResult)
        let message = settledObservation.message(explicit: dispatchResult.message)
        let payload = settledObservation.payload(
            for: dispatchResult,
            afterStatePayload: afterStatePayload
        )
        let methodAndPayload = payload.map(ActionResult.MethodAndPayload.payload)
            ?? .methodOnly(dispatchResult.method)
        let duration: ActionSettlementDuration
        do {
            duration = try ActionSettlementDuration(
                validatingMilliseconds: settledObservation.settleTimeMs
            )
        } catch {
            self = ActionResult.failure(
                method: dispatchResult.method,
                failureKind: .actionFailed,
                message: String(describing: error),
                observation: .trace(settledObservation.traceEvidence),
                subjectEvidence: dispatchResult.subjectEvidence
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
            subjectEvidence: dispatchResult.subjectEvidence,
            activationTrace: dispatchResult.activationTrace
        )
    }
}

extension ActionEvidenceProjector.Result {
    var traceEvidence: AccessibilityTraceEvidence {
        guard let evidence = AccessibilityTraceEvidence(
            trace: accessibilityTrace,
            completeness: .incomplete
        ) else {
            preconditionFailure("action evidence requires a current accessibility capture")
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
        settleResult.outcome.timeMs
    }

    private var settleResult: SettleSession.Result {
        switch self {
        case .committed(let settleResult, _, _),
             .diagnostic(let settleResult, _),
             .unavailable(let settleResult, _, _):
            return settleResult
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
        for dispatchResult: TheSafecracker.ActionDispatchResult
    ) -> ActionResultOutcome {
        switch self {
        case .committed, .diagnostic:
            switch dispatchResult.outcome {
            case .success:
                return .success
            case .failure(let failureKind):
                return .failure(TheBrains.actionFailureKind(for: failureKind))
            }
        case .unavailable:
            return .failure(.actionFailed)
        }
    }

    func payload(
        for dispatchResult: TheSafecracker.ActionDispatchResult,
        afterStatePayload: ((ActionPayloadEvidence) -> ActionResultPayload?)?
    ) -> ActionResultPayload? {
        guard case .success(let payload, let resolvedElementId) = dispatchResult.outcome else { return nil }
        if let payload { return payload }
        guard let afterStatePayload else { return nil }
        guard case .committed(_, let finalBaseline, _) = self else { return nil }
        return afterStatePayload(ActionPayloadEvidence(
            committedBaseline: finalBaseline,
            resolvedElementId: resolvedElementId
        ))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
