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
                warning: Self.warning(method: outcome.method, subjectEvidence: outcome.subjectEvidence)
            )
            self = payload.map { ActionResult.success(payload: $0, message: message, evidence: evidence) }
                ?? ActionResult.success(method: outcome.method, message: message, evidence: evidence)
        case .failure(let errorKind):
            let evidence = ActionResultFailureEvidence(
                observation: observation,
                subjectEvidence: outcome.subjectEvidence,
                activationTrace: outcome.activationTrace
            )
            self = payload.map {
                ActionResult.failure(payload: $0, errorKind: errorKind, message: message, evidence: evidence)
            } ?? ActionResult.failure(
                method: outcome.method,
                errorKind: errorKind,
                message: message,
                evidence: evidence
            )
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
