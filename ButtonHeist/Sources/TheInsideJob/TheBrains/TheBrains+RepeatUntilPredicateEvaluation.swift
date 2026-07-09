#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains.RepeatUntil {
    internal struct Observation {
        internal let sequence: SettledObservationSequence
        internal let trace: AccessibilityTrace?
        internal let summary: String?

        internal init?(_ receipt: HeistWaitReceipt) {
            guard let sequence = receipt.observedSequence else { return nil }
            self.sequence = sequence
            trace = receipt.accessibilityTrace
            summary = receipt.observationSummary
        }
    }

    internal struct MetCheck {
        internal let observation: Observation
        internal let expectation: MetExpectationResult
        internal let receipt: HeistWaitReceipt

        internal init(
            observation: Observation,
            expectation: MetExpectationResult,
            receipt: HeistWaitReceipt
        ) {
            self.observation = observation
            self.expectation = expectation
            self.receipt = receipt
        }
    }

    internal struct UnmetCheck {
        internal let observation: Observation
        internal let expectation: UnmetExpectationResult
        internal let receipt: HeistWaitReceipt

        internal init(
            observation: Observation,
            expectation: UnmetExpectationResult,
            receipt: HeistWaitReceipt
        ) {
            self.observation = observation
            self.expectation = expectation
            self.receipt = receipt
        }
    }

    internal enum ObservedCheck {
        case met(MetCheck)
        case unmet(UnmetCheck)

        internal init?(
            receipt: HeistWaitReceipt,
            expectation: ExpectationResult? = nil
        ) {
            guard let observation = Observation(receipt) else { return nil }
            self.init(
                observation: observation,
                check: PredicateExpectationCheck(expectation ?? receipt.expectation),
                receipt: receipt
            )
        }

        internal init(
            observation: Observation,
            check: PredicateExpectationCheck,
            receipt: HeistWaitReceipt
        ) {
            switch check {
            case .met(let expectation):
                self = .met(MetCheck(
                    observation: observation,
                    expectation: expectation,
                    receipt: receipt
                ))
            case .unmet(let expectation):
                self = .unmet(UnmetCheck(
                    observation: observation,
                    expectation: expectation,
                    receipt: receipt
                ))
            }
        }
    }

    internal enum InitialCheck {
        case unavailable(HeistWaitReceipt)
        case met(MetCheck)
        case unmet(UnmetCheck)

        internal static func make(receipt: HeistWaitReceipt) -> InitialCheck {
            guard let check = ObservedCheck(receipt: receipt) else {
                return .unavailable(receipt)
            }
            switch check {
            case .met(let check):
                return .met(check)
            case .unmet(let check):
                return .unmet(check)
            }
        }
    }

    internal enum PostBodyCheck {
        case deadlineElapsed(UnmetExpectationResult)
        case changedMet(MetCheck)
        case changedUnmet(UnmetCheck)
        case noProgress(observation: Observation?, expectation: UnmetExpectationResult, receipt: HeistWaitReceipt)

        internal var iterationOutcome: IterationOutcome {
            switch self {
            case .deadlineElapsed(let expectation),
                 .noProgress(_, let expectation, _):
                return .continued(expectation)
            case .changedMet(let check):
                return .predicateMet(check.expectation)
            case .changedUnmet(let check):
                return .continued(check.expectation)
            }
        }

        internal var observation: Observation? {
            switch self {
            case .deadlineElapsed:
                return nil
            case .changedMet(let check):
                return check.observation
            case .changedUnmet(let check):
                return check.observation
            case .noProgress(let observation, _, _):
                return observation
            }
        }
    }
}

extension TheBrains {
    internal func repeatUntilShouldCheckStopPredicate(
        afterBodyFailure failedStep: HeistExecutionStepResult,
        in iterationResults: [HeistExecutionStepResult]
    ) -> Bool {
        guard iterationResults.contains(where: { $0.path == failedStep.path }) else { return false }
        guard failedStep.kind == .action,
              failedStep.failure?.category == .action,
              failedStep.actionEvidence?.dispatchResult?.outcome.isSuccess == false else {
            return false
        }
        switch failedStep.actionEvidence?.dispatchResult?.outcome.errorKind {
        case nil, .some(.actionFailed):
            return true
        case .some(.accessibilityTreeUnavailable),
             .some(.elementNotFound),
             .some(.timeout),
             .some(.validationError),
             .some(.authFailure),
             .some(.general):
            return false
        }
    }

    internal func repeatUntilPostBodyCheck(
        context: RepeatUntil.Context,
        step: ResolvedRepeatUntilStep,
        observation: RepeatUntil.Observation,
        deadline: CFAbsoluteTime
    ) async -> RepeatUntil.PostBodyCheck {
        let remaining = deadline - CFAbsoluteTimeGetCurrent()
        guard remaining > 0 else {
            return .deadlineElapsed(UnmetExpectationResult(
                predicate: step.predicate,
                actual: "repeat_until deadline elapsed"
            ))
        }
        let progressTimeout = min(defaultActionExpectationTimeout, remaining)
        let receipt = await context.runtime.wait(.afterObservation(
            ResolvedWaitStep(predicate: .change(), timeout: progressTimeout),
            baselineTrace: observation.trace,
            sequence: observation.sequence
        ))
        let expectation = repeatUntilStopExpectation(
            step.predicate,
            trace: receipt.accessibilityTrace,
            fallback: receipt.message ?? receipt.expectation.actual
        )
        let stopCheck = PredicateExpectationCheck(expectation)
        let observedCheck = RepeatUntil.Observation(receipt).map {
            RepeatUntil.ObservedCheck(observation: $0, check: stopCheck, receipt: receipt)
        }
        guard receipt.succeeded,
              let check = observedCheck else {
            let noProgressExpectation: UnmetExpectationResult
            switch stopCheck {
            case .met(let metExpectation):
                noProgressExpectation = UnmetExpectationResult(
                    predicate: step.predicate,
                    actual: receipt.observedSequence == nil
                        ? "repeat_until post-body check matched without settled observation"
                        : (metExpectation.result.actual ?? "repeat_until post-body check made no progress")
                )
            case .unmet(let unmetExpectation):
                noProgressExpectation = unmetExpectation
            }
            return .noProgress(
                observation: RepeatUntil.Observation(receipt),
                expectation: noProgressExpectation,
                receipt: receipt
            )
        }
        switch check {
        case .met(let check):
            return .changedMet(check)
        case .unmet(let check):
            return .changedUnmet(check)
        }
    }

    private func repeatUntilStopExpectation(
        _ predicate: AccessibilityPredicate,
        trace: AccessibilityTrace?,
        fallback: String?
    ) -> ExpectationResult {
        guard let trace else {
            return ExpectationResult(
                met: false,
                predicate: predicate,
                actual: fallback ?? "no observed accessibility trace"
            )
        }
        return PredicateEvaluation.evaluate(
            predicate,
            currentElements: trace.captures.last?.interface.projectedElements ?? [],
            accumulatedDelta: trace.accumulatedDelta
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
