#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

extension PredicateWait {
    func selectPredicateCase(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        timeout: Double
    ) async -> HeistCaseSelectionResult {
        guard !cases.isEmpty else {
            return .selectingFirstMatch(
                cases: [],
                ifNone: .noMatch,
                elapsedMs: 0,
                timeout: timeout,
                lastObservedSummary: nil
            )
        }

        let start = RuntimeElapsed.now
        let projection = PredicateCaseSelectionProjection(cases: cases, timeout: timeout)
        return await execute(
            start: start,
            timeout: timeout,
            projection: ExecutionProjection(
                target: nil,
                continuesAfterInitialMiss: timeout > 0,
                initialEvidence: projection.initialEvidence,
                evaluate: { observation, _, _ in projection.evaluate(observation) },
                result: { outcome, deadline, evidence in
                    projection.result(outcome, deadline: deadline, evidence: evidence)
                }
            )
        )
    }
}

private struct PredicateCaseSelectionEvidence: Sendable, Equatable {
    let cases: [HeistCaseMatchResult]
    let observationSummary: String?
}

@MainActor
private final class PredicateCaseSelectionProjection {
    private let inputs: [ResolvedPredicateCaseRuntimeInput]
    private let timeout: Double

    var initialEvidence: PredicateCaseSelectionEvidence {
        PredicateCaseSelectionEvidence(
            cases: inputs.map {
                HeistCaseMatchResult(
                    predicate: $0.predicateExpression.rootPredicate,
                    met: false,
                    actual: "no settled accessibility state observed"
                )
            },
            observationSummary: nil
        )
    }

    init(cases: [ResolvedPredicateCaseRuntimeInput], timeout: Double) {
        inputs = cases
        self.timeout = timeout
    }

    func evaluate(
        _ observation: SettledObservationEvidence
    ) -> PredicateWaitEvaluation<PredicateCaseSelectionEvidence> {
        let evaluatedCases = inputs.map { PredicateEvaluation.caseMatch($0, in: observation) }
        let selection = PredicateCaseSelectionEvidence(
            cases: evaluatedCases,
            observationSummary: observation.summary
        )
        return PredicateWaitEvaluation(
            evidence: selection,
            matched: evaluatedCases.contains(where: \.met)
        )
    }

    func result(
        _ executionOutcome: PredicateWaitOutcome,
        deadline: SemanticObservationDeadline,
        evidence: PredicateCaseSelectionEvidence
    ) -> HeistCaseSelectionResult {
        if !evidence.cases.contains(where: \.met) {
            precondition(executionOutcome != .matched, "matched case wait requires a selected case")
        }
        return .selectingFirstMatch(
            cases: evidence.cases,
            ifNone: timeout > 0 ? .timedOut : .noMatch,
            elapsedMs: RuntimeElapsed.admit(milliseconds: deadline.elapsedMilliseconds()),
            timeout: timeout,
            lastObservedSummary: evidence.observationSummary
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
