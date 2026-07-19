#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

extension ActionResult {
    @MainActor init(
        dispatchResult: TheSafecracker.ActionDispatchResult,
        afterStateValue: ((ActionPayloadEvidence) -> String?)?,
        settledObservation: ActionEvidenceProjector.Result
    ) {
        let resultOutcome = settledObservation.resultOutcome(for: dispatchResult)
        let message = settledObservation.message(explicit: dispatchResult.message)
        let payload = settledObservation.payload(
            for: dispatchResult,
            afterStateValue: afterStateValue
        )
        let duration: ActionSettlementDuration
        do {
            duration = try ActionSettlementDuration(
                validatingMilliseconds: settledObservation.settleTimeMs
            )
        } catch {
            self = ActionResult.failure(
                payload: dispatchResult.payload,
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
            payload: payload,
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
        afterStateValue: ((ActionPayloadEvidence) -> String?)?
    ) -> ActionResult.Payload {
        guard case .success(let resolvedElementId) = dispatchResult.outcome,
              case .typeText = dispatchResult.payload,
              let afterStateValue,
              case .committed(_, let finalBaseline, _) = self else {
            return dispatchResult.payload
        }
        return .typeText(afterStateValue(ActionPayloadEvidence(
            committedBaseline: finalBaseline,
            resolvedElementId: resolvedElementId
        )))
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
