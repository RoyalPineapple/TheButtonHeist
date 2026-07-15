#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore
import ThePlans

struct PredicateCaseSelection {
    typealias ObservationSource = @MainActor (
        SemanticObservationScope,
        SettledObservationSequence?,
        Double?
    ) async -> HeistSemanticObservation?

    private struct ObservedSelection {
        let observation: HeistSemanticObservation
        let selection: PredicateCaseSelection
    }

    let cases: [HeistCaseMatchResult]
    let selectedCaseIndex: Int?

    static func unevaluated(_ cases: [ResolvedPredicateCaseRuntimeInput]) -> PredicateCaseSelection {
        PredicateCaseSelection(
            cases: cases.map {
                let predicate = $0.predicateExpression.rootPredicate
                return HeistCaseMatchResult(
                    predicate: predicate,
                    met: false,
                    actual: "no settled accessibility state observed"
                )
            },
            selectedCaseIndex: nil
        )
    }

    static func evaluate(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        observation: HeistSemanticObservation
    ) -> PredicateCaseSelection {
        let evaluatedCases = cases.map {
            PredicateEvaluation.caseMatch(
                $0,
                in: observation
            )
        }
        return PredicateCaseSelection(
            cases: evaluatedCases,
            selectedCaseIndex: evaluatedCases.firstIndex(where: \.met)
        )
    }

    @MainActor static func waitFor(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        timeout rawTimeout: Double,
        observeSemanticState: @escaping ObservationSource
    ) async -> HeistCaseSelectionResult {
        let start = CFAbsoluteTimeGetCurrent()
        guard !cases.isEmpty else {
            return emptyResult(timeout: rawTimeout)
        }

        let timeout = PredicateWait.clampedWaitTimeout(rawTimeout)
        let deadline = SemanticObservationDeadline(start: start, timeoutSeconds: timeout)
        var last = await initialSelection(
            cases,
            observeSemanticState: observeSemanticState
        )
        if last?.selection.selectedCaseIndex != nil {
            return result(cases, last: last, miss: .noMatch, deadline: deadline, timeout: rawTimeout)
        }

        // Case selection is an immediate state query unless its caller supplies a wait budget.
        guard timeout > 0 else {
            return result(cases, last: last, miss: .noMatch, deadline: deadline, timeout: rawTimeout)
        }

        if last == nil {
            last = await observedSelection(
                cases,
                scope: .visible,
                after: nil,
                timeout: min(deadline.remainingSeconds(), SemanticObservationTiming.defaultTimeout),
                observeSemanticState: observeSemanticState
            )
            if last?.selection.selectedCaseIndex != nil {
                return result(cases, last: last, miss: .timedOut, deadline: deadline, timeout: rawTimeout)
            }
        }

        var observedSequence = last?.observation.event.sequence
        var lifecycle = StateDriver(
            initial: PredicateWaitLifecycleState.initialVisible,
            machine: PredicateWaitLifecycleMachine()
        )
        var effect = lifecycle.send(.evaluated(matched: false)).predicateWaitEffect

        while true {
            if Task.isCancelled, case .finish = effect {
                // Preserve an already-decided terminal outcome.
            } else if Task.isCancelled {
                effect = lifecycle.send(.cancelled).predicateWaitEffect
            }

            switch effect {
            case .settleVisible(let budget):
                let observed = await observedSelection(
                    cases,
                    scope: .visible,
                    after: nil,
                    timeout: budget.deadline(overall: deadline).remainingSeconds(),
                    observeSemanticState: observeSemanticState
                )
                if let observed {
                    last = observed
                    observedSequence = observed.observation.event.sequence
                }
                effect = lifecycle.send(.evaluated(
                    matched: observed?.selection.selectedCaseIndex != nil
                )).predicateWaitEffect

            case .discover(let budget):
                let observed = await observedSelection(
                    cases,
                    scope: .discovery,
                    after: observedSequence,
                    timeout: budget.deadline(overall: deadline).map {
                        min($0.remainingSeconds(), SemanticObservationTiming.defaultTimeout)
                    },
                    observeSemanticState: observeSemanticState
                )
                if let observed {
                    last = observed
                    observedSequence = observed.observation.event.sequence
                }
                effect = lifecycle.send(.evaluated(
                    matched: observed?.selection.selectedCaseIndex != nil
                )).predicateWaitEffect

            case .awaitObservation:
                guard deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) else {
                    effect = lifecycle.send(.deadlineReached).predicateWaitEffect
                    continue
                }
                let observed = await observedSelection(
                    cases,
                    scope: .visible,
                    after: observedSequence,
                    timeout: deadline.remainingSeconds(),
                    observeSemanticState: observeSemanticState
                )
                guard let observed else {
                    effect = lifecycle.send(.deadlineReached).predicateWaitEffect
                    continue
                }
                last = observed
                observedSequence = observed.observation.event.sequence
                effect = lifecycle.send(.observation(
                    matched: observed.selection.selectedCaseIndex != nil
                )).predicateWaitEffect

            case .finish(let outcome):
                let miss: HeistCaseSelectionOutcome = outcome == .matched ? .noMatch : .timedOut
                return result(cases, last: last, miss: miss, deadline: deadline, timeout: rawTimeout)
            }
        }
    }

    private static func emptyResult(timeout: Double) -> HeistCaseSelectionResult {
        HeistCaseSelectionResult(
            cases: [],
            outcome: .noMatch,
            elapsedMs: 0,
            timeout: timeout,
            lastObservedSummary: nil
        )
    }

    @MainActor
    private static func initialSelection(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        observeSemanticState: ObservationSource
    ) async -> ObservedSelection? {
        await observedSelection(
            cases,
            scope: .visible,
            after: nil,
            timeout: 0,
            observeSemanticState: observeSemanticState
        )
    }

    @MainActor
    private static func observedSelection(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?,
        observeSemanticState: ObservationSource
    ) async -> ObservedSelection? {
        guard let observation = await observeSemanticState(scope, sequence, timeout) else {
            return nil
        }
        return ObservedSelection(
            observation: observation,
            selection: evaluate(cases, observation: observation)
        )
    }

    private static func result(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        last: ObservedSelection?,
        miss: HeistCaseSelectionOutcome,
        deadline: SemanticObservationDeadline,
        timeout: Double
    ) -> HeistCaseSelectionResult {
        let selection = last?.selection ?? unevaluated(cases)
        let outcome: HeistCaseSelectionOutcome
        if let selectedCaseIndex = selection.selectedCaseIndex {
            outcome = .matchedCase(index: selectedCaseIndex)
        } else {
            outcome = miss
        }
        return HeistCaseSelectionResult(
            cases: selection.cases,
            outcome: outcome,
            elapsedMs: deadline.elapsedMilliseconds(),
            timeout: timeout,
            lastObservedSummary: last?.observation.summary
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
