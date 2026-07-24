#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

extension Settlement {
    internal enum PredicateEvaluation {}
}

extension Settlement.PredicateEvaluation {
    static func evaluate(
        _ request: Settlement.Predicate.EvaluationRequest
    ) -> PredicateEvaluationResult {
        switch request.evidence {
        case .currentState(let event):
            evaluate(request.predicate, trace: event.trace, completeness: .incomplete)
        case .positiveTransition(let event):
            evaluate(request.predicate, trace: event.trace, completeness: .complete)
        case .announcement(let event):
            evaluateAnnouncement(request.predicate, event: event)
        case .completeHistory(let evidence):
            evaluateCompleteHistory(request.predicate, evidence: evidence)
        }
    }

    static func evaluate(
        _ predicate: Settlement.Predicate,
        in result: Settlement.Result
    ) -> PredicateEvaluationResult {
        guard let event = result.evidence.handoff.event else {
            return PredicateEvaluationResult(
                met: false,
                actual: "settlement did not produce a current observation"
            )
        }
        let completeness: AccessibilityTraceEvidence.Completeness = switch result.evidence.command {
        case .currentState:
            .incomplete
        case .observation, .action:
            .complete
        }
        return evaluate(predicate, trace: event.trace, completeness: completeness)
    }

    static func evaluate(
        _ predicate: ResolvedAccessibilityPredicate,
        expression: AccessibilityPredicate,
        in event: Observation.SnapshotEvent
    ) -> ExpectationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: event.trace,
            completeness: .incomplete
        ) else {
            return ExpectationResult(
                met: false,
                predicate: expression,
                actual: "no observed accessibility trace"
            )
        }
        return predicate.evaluate(in: evidence).expectation(for: expression)
    }

    static func evaluate(
        _ predicate: ResolvedAccessibilityPredicate,
        expression: AccessibilityPredicate,
        in result: Settlement.Result
    ) -> ExpectationResult {
        evaluate(
            Settlement.Predicate(authored: expression, resolved: predicate),
            in: result
        ).expectation(for: expression)
    }

    static func evaluate(
        _ predicate: ResolvedAccessibilityPredicate,
        expression: AccessibilityPredicate,
        in trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> ExpectationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: trace,
            completeness: completeness
        ) else {
            return ExpectationResult(
                met: false,
                predicate: expression,
                actual: "no observed accessibility trace"
            )
        }
        return predicate.evaluate(in: evidence).expectation(for: expression)
    }

    static func caseMatch(
        _ predicateCase: PredicateCase,
        resolved: ResolvedScreenAssertion,
        in event: Observation.SnapshotEvent
    ) -> HeistCaseMatchResult {
        caseMatchResult(
            predicateCase,
            result: evaluate(
                resolved.rootPredicate,
                expression: predicateCase.predicate.rootPredicate,
                in: event
            )
        )
    }

    static func caseMatch(
        _ predicateCase: PredicateCase,
        resolved: ResolvedScreenAssertion,
        in result: Settlement.Result
    ) -> HeistCaseMatchResult {
        caseMatchResult(
            predicateCase,
            result: evaluate(
                resolved.rootPredicate,
                expression: predicateCase.predicate.rootPredicate,
                in: result
            )
        )
    }

    private static func caseMatchResult(
        _ predicateCase: PredicateCase,
        result: ExpectationResult
    ) -> HeistCaseMatchResult {
        HeistCaseMatchResult(
            predicate: predicateCase.predicate.rootPredicate,
            met: result.met,
            actual: result.actual
        )
    }

    private static func evaluate(
        _ predicate: Settlement.Predicate,
        trace: AccessibilityTrace,
        completeness: AccessibilityTraceEvidence.Completeness
    ) -> PredicateEvaluationResult {
        guard let evidence = AccessibilityTraceEvidence(
            trace: trace,
            completeness: completeness
        ) else {
            return PredicateEvaluationResult(
                met: false,
                actual: "no observed accessibility trace"
            )
        }
        return predicate.resolved.evaluate(in: evidence)
    }

    private static func evaluateAnnouncement(
        _ predicate: Settlement.Predicate,
        event: Observation.AnnouncementEvent
    ) -> PredicateEvaluationResult {
        guard case .announcement(let announcement) = predicate.resolved else {
            preconditionFailure("Announcement evidence requires an announcement predicate")
        }
        return PredicateEvaluationResult(
            met: announcement.matches(event.announcement.text),
            actual: event.announcement.text
        )
    }

    private static func evaluateCompleteHistory(
        _ predicate: Settlement.Predicate,
        evidence: Settlement.Predicate.CompleteHistoryEvidence
    ) -> PredicateEvaluationResult {
        guard case .events(let events) = evidence.history else {
            return PredicateEvaluationResult(
                met: false,
                actual: "observation history unavailable"
            )
        }
        let captures = events.compactMap { event -> AccessibilityTrace.Capture? in
            guard case .snapshot(let snapshot) = event else { return nil }
            return snapshot.trace.captures.last
        }
        let trace = captures.isEmpty
            ? evidence.handoff.trace
            : AccessibilityTrace(captures: captures)
        return evaluate(predicate, trace: trace, completeness: .complete)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
