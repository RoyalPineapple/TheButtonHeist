#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains.RepeatUntil {
    internal struct ObservedState {
        internal let settlement: Settlement.Result

        internal var summary: String? {
            settlement.evidence.handoff.event?.summary
        }

        internal init(_ settlement: Settlement.Result) {
            self.settlement = settlement
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
              failedStep.actionEvidence?.result?.outcome.isSuccess == false else {
            return .abort
        }
        let shouldCheck: Bool
        switch failedStep.actionEvidence?.result?.outcome.failureKind {
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
        let command: Settlement.Command
        if let observation {
            waitInput = .changedElements(timeout: progressTimeout)
            command = Settlement.Command(
                observing: waitInput,
                baseline: observation.settlement.evidence.handoff.event.map {
                    .supplied(.init(moment: $0.moment))
                } ?? .unavailable(.unavailable)
            )
        } else {
            waitInput = ResolvedWaitRuntimeInput(repeatUntil: step, timeout: progressTimeout)
            command = Settlement.Command(observing: waitInput)
        }
        let settlement = await context.runtime.settle(command)
        let evidence = Settlement.ResultProjector.projectWait(settlement)
        let stopCheck = Settlement.PredicateEvaluation.evaluate(
            step.predicate,
            expression: step.predicateExpression,
            in: settlement
        )
        let observation = RepeatUntil.ObservedState(settlement)
        guard settlement.evidence.handoff.event != nil else {
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
                observation: observation,
                expectation: noProgressExpectation
            )
        }
        let check = RepeatUntil.ObservedCheck(
            observation: observation,
            check: stopCheck
        )
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

}

#endif // DEBUG
#endif // canImport(UIKit)
