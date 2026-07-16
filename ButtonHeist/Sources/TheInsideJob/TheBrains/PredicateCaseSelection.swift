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
            return HeistCaseSelectionResult(
                cases: [],
                outcome: .noMatch,
                elapsedMs: 0,
                timeout: timeout,
                lastObservedSummary: nil
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
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
    let selectedCaseIndex: Int?
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
            selectedCaseIndex: nil,
            observationSummary: nil
        )
    }

    init(cases: [ResolvedPredicateCaseRuntimeInput], timeout: Double) {
        inputs = cases
        self.timeout = timeout
    }

    func evaluate(
        _ observation: HeistSemanticObservation
    ) -> PredicateWaitLifecycleEvaluation<PredicateCaseSelectionEvidence> {
        let evaluatedCases = inputs.map { PredicateEvaluation.caseMatch($0, in: observation) }
        let selectedCaseIndex = evaluatedCases.firstIndex(where: \.met)
        let selection = PredicateCaseSelectionEvidence(
            cases: evaluatedCases,
            selectedCaseIndex: selectedCaseIndex,
            observationSummary: observation.summary
        )
        return PredicateWaitLifecycleEvaluation(
            evidence: selection,
            matched: selectedCaseIndex != nil
        )
    }

    func result(
        _ executionOutcome: PredicateWaitLifecycleOutcome,
        deadline: SemanticObservationDeadline,
        evidence: PredicateCaseSelectionEvidence
    ) -> HeistCaseSelectionResult {
        let outcome: HeistCaseSelectionOutcome
        if let selectedCaseIndex = evidence.selectedCaseIndex {
            outcome = .matchedCase(index: selectedCaseIndex)
        } else {
            precondition(executionOutcome != .matched, "matched case wait requires a selected case")
            outcome = timeout > 0 ? .timedOut : .noMatch
        }
        return HeistCaseSelectionResult(
            cases: evidence.cases,
            outcome: outcome,
            elapsedMs: deadline.elapsedMilliseconds(),
            timeout: timeout,
            lastObservedSummary: evidence.observationSummary
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
