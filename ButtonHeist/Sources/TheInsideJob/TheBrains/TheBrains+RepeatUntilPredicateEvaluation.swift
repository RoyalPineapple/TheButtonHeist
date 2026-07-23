#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains.RepeatUntil {
    internal struct ObservedState {
        internal let boundary: Settlement.EvidenceBoundary
        internal let summary: String?

        internal init(
            boundary: Settlement.EvidenceBoundary,
            summary: String?
        ) {
            self.boundary = boundary
            self.summary = summary
        }

        internal init?(
            settlement: Settlement.Result,
            evidence: HeistSettlementEvidence
        ) {
            guard let moment = settlement.evidence.handoff.event?.moment else { return nil }
            boundary = Settlement.EvidenceBoundary(moment: moment)
            summary = evidence.finalSummary
        }

        internal init(_ event: Observation.SnapshotEvent) {
            boundary = Settlement.EvidenceBoundary(moment: event.moment)
            summary = event.summary
        }
    }

    internal struct MetCheck {
        internal let observation: ObservedState
        internal let expectation: ExpectationResult.Met
    }

    internal struct UnmetCheck {
        internal let observation: ObservedState
        internal let expectation: ExpectationResult.Unmet
    }

    internal enum ObservedCheck {
        case met(MetCheck)
        case unmet(UnmetCheck)

        internal init(
            observation: ObservedState,
            check: ExpectationResult
        ) {
            switch check {
            case .met(let expectation):
                self = .met(MetCheck(
                    observation: observation,
                    expectation: expectation
                ))
            case .unmet(let expectation):
                self = .unmet(UnmetCheck(
                    observation: observation,
                    expectation: expectation
                ))
            }
        }
    }

    internal enum PostBodyCheck {
        case deadlineElapsed(ExpectationResult.Unmet)
        case met(MetCheck)
        case unmet(UnmetCheck)
        case noProgress(observation: ObservedState?, expectation: ExpectationResult.Unmet)

        internal var observation: ObservedState? {
            switch self {
            case .deadlineElapsed:
                return nil
            case .met(let check):
                return check.observation
            case .unmet(let check):
                return check.observation
            case .noProgress(let observation, _):
                return observation
            }
        }
    }
}

extension TheBrains {
    internal enum RepeatUntilBodyFailureDisposition {
        case checkPredicate(HeistPassingChildren)
        case abort
    }

    internal func repeatUntilBodyFailureDisposition(
        _ children: HeistAbortedChildren
    ) -> RepeatUntilBodyFailureDisposition {
        guard let failedStep = children.values.first(where: { $0.path == children.abortedAtPath }) else {
            return .abort
        }
        guard failedStep.kind == .action,
              failedStep.failure?.category == .action,
              failedStep.actionEvidence?.dispatchResult?.outcome.isSuccess == false else {
            return .abort
        }
        let shouldCheck: Bool
        switch failedStep.actionEvidence?.dispatchResult?.outcome.failureKind {
        case nil, .some(.actionFailed):
            shouldCheck = true
        case .some(.accessibilityTreeUnavailable),
             .some(.elementNotFound),
             .some(.timeout),
             .some(.validationError):
            shouldCheck = false
        }
        guard shouldCheck else { return .abort }

        var retained = HeistExecutedChildren.empty
        for child in children.values where child.path != children.abortedAtPath {
            retained.append(child)
        }
        guard case .passed(let passingChildren) = retained else { return .abort }
        return .checkPredicate(passingChildren)
    }

    internal func repeatUntilPostBodyCheck(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        observation: RepeatUntil.ObservedState?,
        iterationResults _: HeistPassingChildren,
        deadline: SemanticObservationDeadline
    ) async -> RepeatUntil.PostBodyCheck {
        let remaining = deadline.remainingSeconds()
        guard remaining > 0 else {
            return .deadlineElapsed(ExpectationResult.Unmet(
                predicate: step.predicateExpression,
                actual: "repeat_until deadline elapsed"
            ))
        }
        let progressTimeout: WaitTimeout
        do {
            progressTimeout = try WaitTimeout(validatingSeconds: min(
                defaultActionExpectationTimeout.seconds,
                remaining
            ))
        } catch {
            return .deadlineElapsed(ExpectationResult.Unmet(
                predicate: step.predicateExpression,
                actual: String(describing: error)
            ))
        }
        let waitInput: ResolvedWaitRuntimeInput
        let baseline: Settlement.Baseline
        if let observation {
            waitInput = .changedElements(timeout: progressTimeout)
            baseline = .supplied(observation.boundary)
        } else {
            waitInput = ResolvedWaitRuntimeInput(repeatUntil: step, timeout: progressTimeout)
            baseline = Settlement.Baseline.beforeTrigger(
                observationMoment: nil,
                predicate: waitInput.predicate
            )
        }
        let settlement = await context.runtime.wait(Settlement.Command(
            observing: waitInput,
            baseline: baseline
        ))
        let evidence = Settlement.ResultProjector.projectWait(settlement)
        let expectation = repeatUntilStopExpectation(
            authored: step.predicateExpression,
            resolved: step.predicate,
            evidence: evidence.actionResult.traceEvidence,
            fallback: evidence.actionResult.message ?? evidence.expectation.actual
        )
        let stopCheck = expectation
        let observation = RepeatUntil.ObservedState(
            settlement: settlement,
            evidence: evidence
        )
        let observedCheck = observation.map {
            RepeatUntil.ObservedCheck(observation: $0, check: stopCheck)
        }
        guard let check = observedCheck else {
            let noProgressExpectation: ExpectationResult.Unmet
            switch stopCheck {
            case .met(let metExpectation):
                noProgressExpectation = ExpectationResult.Unmet(
                    predicate: step.predicateExpression,
                    actual: metExpectation.result.actual
                        ?? "repeat_until post-body check made no progress"
                )
            case .unmet(let unmetExpectation):
                noProgressExpectation = unmetExpectation
            }
            return .noProgress(
                observation: nil,
                expectation: noProgressExpectation
            )
        }
        switch check {
        case .met(let check):
            return .met(check)
        case .unmet(let check):
            guard evidence.outcome == .matched else {
                return .noProgress(
                    observation: check.observation,
                    expectation: check.expectation
                )
            }
            return .unmet(check)
        }
    }

    private func repeatUntilStopExpectation(
        authored predicate: AccessibilityPredicate,
        resolved: ResolvedAccessibilityPredicate,
        evidence: AccessibilityTraceEvidence?,
        fallback: String?
    ) -> ExpectationResult {
        guard let evidence else {
            return ExpectationResult(
                met: false,
                predicate: predicate,
                actual: fallback ?? "no observed accessibility trace"
            )
        }
        return ExpectationResult(resolved.evaluate(in: evidence), predicate: predicate)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
