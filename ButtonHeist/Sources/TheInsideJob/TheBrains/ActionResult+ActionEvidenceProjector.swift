#if canImport(UIKit)
#if DEBUG
import ThePlans
import TheScore

// MARK: - Action Evidence Projection

extension ActionResult {
    @MainActor init(
        dispatchResult: TheSafecracker.ActionDispatchResult,
        afterStateValue: ((ActionPayloadEvidence) -> String?)?,
        settledObservation: ActionEvidenceProjector.Result,
        timing initialTiming: ActionTiming
    ) {
        var timing = initialTiming
        let assemblyStart = RuntimeElapsed.now
        let resultOutcome = settledObservation.resultOutcome(for: dispatchResult)
        let message = settledObservation.message(explicit: dispatchResult.message)
        let payload = settledObservation.payload(
            for: dispatchResult,
            afterStateValue: afterStateValue
        )
        let duration = RuntimeElapsed.admit(milliseconds: settledObservation.settleTimeMs)
        let settlement: ActionSettlementEvidence = settledObservation.settled
            ? .settled(
                duration: duration,
                path: settledObservation.settleEvidence?.actionSettlementPath
            )
            : .timedOut(duration: duration)
        let observation = ActionResultObservationEvidence.settledTrace(
            settledObservation.traceEvidence,
            settlement
        )
        timing.record(.resultAssembly, since: assemblyStart)
        self = ActionResult(
            outcome: resultOutcome,
            payload: payload,
            message: message,
            observation: observation,
            subjectEvidence: dispatchResult.subjectEvidence,
            activationTrace: dispatchResult.activationTrace,
            screenActionHandler: dispatchResult.screenActionHandler,
            timing: timing.freeze()
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

    var settleEvidence: SettleEvidence? {
        settleResult.evidence
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

private extension SettleEvidence {
    var actionSettlementPath: ActionSettlementPath {
        switch self {
        case .semanticStability:
            return .semanticStability
        case .uikitIdle:
            return .uikitIdle
        case .accessibilityQuietWindow:
            return .accessibilityQuietWindow
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
