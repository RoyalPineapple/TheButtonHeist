#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

extension TheBrains.RepeatUntil {
    internal struct Observation {
        internal let sequence: SettledObservationSequence
        internal let traceEvidence: AccessibilityTraceEvidence?
        internal let summary: String?

        internal init(
            sequence: SettledObservationSequence,
            traceEvidence: AccessibilityTraceEvidence?,
            summary: String?
        ) {
            self.sequence = sequence
            self.traceEvidence = traceEvidence
            self.summary = summary
        }

        internal var trace: AccessibilityTrace? { traceEvidence?.trace }

        internal init?(_ receipt: HeistWaitReceipt) {
            guard let sequence = receipt.observedSequence else { return nil }
            self.sequence = sequence
            traceEvidence = receipt.traceEvidence
            summary = receipt.observationSummary
        }

        internal init(_ observation: HeistSemanticObservation) {
            sequence = observation.event.sequence
            traceEvidence = AccessibilityTraceEvidence(
                trace: observation.accessibilityTrace,
                completeness: .incomplete
            )
            summary = observation.summary
        }
    }

    internal struct MetCheck {
        internal let observation: Observation
        internal let expectation: ExpectationResult.Met
        internal let receipt: HeistWaitReceipt

        internal init(
            observation: Observation,
            expectation: ExpectationResult.Met,
            receipt: HeistWaitReceipt
        ) {
            self.observation = observation
            self.expectation = expectation
            self.receipt = receipt
        }
    }

    internal struct UnmetCheck {
        internal let observation: Observation
        internal let expectation: ExpectationResult.Unmet
        internal let receipt: HeistWaitReceipt

        internal init(
            observation: Observation,
            expectation: ExpectationResult.Unmet,
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
                check: expectation ?? receipt.expectation,
                receipt: receipt
            )
        }

        internal init(
            observation: Observation,
            check: ExpectationResult,
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

    internal enum PostBodyCheck {
        case deadlineElapsed(ExpectationResult.Unmet)
        case met(MetCheck)
        case unmet(UnmetCheck)
        case noProgress(observation: Observation?, expectation: ExpectationResult.Unmet, receipt: HeistWaitReceipt)

        internal var iterationOutcome: IterationOutcome {
            switch self {
            case .deadlineElapsed(let expectation),
                 .noProgress(_, let expectation, _):
                return .continued(expectation)
            case .met(let check):
                return .predicateMet(check.expectation)
            case .unmet(let check):
                return .continued(check.expectation)
            }
        }

        internal var observation: Observation? {
            switch self {
            case .deadlineElapsed:
                return nil
            case .met(let check):
                return check.observation
            case .unmet(let check):
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
        observation: RepeatUntil.Observation?,
        iterationResults: [HeistExecutionStepResult],
        deadline: CFAbsoluteTime
    ) async -> RepeatUntil.PostBodyCheck {
        if let observation,
           let actionTraceCheck = repeatUntilActionTracePostBodyCheck(
            step: step,
            observation: observation,
            iterationResults: iterationResults
        ) {
            return actionTraceCheck
        }

        let remaining = deadline - CFAbsoluteTimeGetCurrent()
        guard remaining > 0 else {
            return .deadlineElapsed(ExpectationResult.Unmet(
                predicate: step.predicateExpression,
                actual: "repeat_until deadline elapsed"
            ))
        }
        let progressTimeout = WaitTimeout(seconds: min(defaultActionExpectationTimeout.seconds, remaining))
        let receipt: HeistWaitReceipt
        if let observation {
            receipt = await context.runtime.wait(.afterObservation(
                .changedElements(timeout: progressTimeout),
                baselineTrace: observation.trace,
                sequence: observation.sequence
            ))
        } else {
            receipt = await context.runtime.wait(.baselineTraceOnly(
                ResolvedWaitRuntimeInput(repeatUntil: step, timeout: progressTimeout),
                trace: nil
            ))
        }
        let expectation = repeatUntilStopExpectation(
            authored: step.predicateExpression,
            resolved: step.predicate,
            evidence: receipt.traceEvidence,
            fallback: receipt.message ?? receipt.expectation.actual
        )
        let stopCheck = expectation
        let observedCheck = RepeatUntil.Observation(receipt).map {
            RepeatUntil.ObservedCheck(observation: $0, check: stopCheck, receipt: receipt)
        }
        guard let check = observedCheck else {
            let noProgressExpectation: ExpectationResult.Unmet
            switch stopCheck {
            case .met(let metExpectation):
                noProgressExpectation = ExpectationResult.Unmet(
                    predicate: step.predicateExpression,
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
            return .met(check)
        case .unmet(let check):
            guard receipt.succeeded else {
                return .noProgress(
                    observation: check.observation,
                    expectation: check.expectation,
                    receipt: receipt
                )
            }
            return .unmet(check)
        }
    }

    private func repeatUntilActionTracePostBodyCheck(
        step: ResolvedRepeatUntilStep,
        observation: RepeatUntil.Observation,
        iterationResults: [HeistExecutionStepResult]
    ) -> RepeatUntil.PostBodyCheck? {
        guard let result = iterationResults
            .compactMap(\.actionEvidence?.dispatchResult)
            .last(where: repeatUntilActionResultCarriesSettledChange)
        else { return nil }

        guard let traceEvidence = result.traceEvidence else { return nil }
        let trace = traceEvidence.trace
        let stopExpectation = repeatUntilStopExpectation(
            authored: step.predicateExpression,
            resolved: step.predicate,
            evidence: traceEvidence,
            fallback: result.message
        )
        let sequence = repeatUntilObservedSequence(after: observation, result: result)
        let actionObservation = RepeatUntil.Observation(
            sequence: sequence,
            traceEvidence: traceEvidence,
            summary: repeatUntilObservationSummary(trace)
        )
        switch stopExpectation {
        case .met(let expectation):
            let receipt = HeistWaitReceipt.matched(
                message: expectation.actual,
                traceEvidence: traceEvidence,
                expectation: expectation,
                observedSequence: sequence,
                observationSummary: actionObservation.summary
            )
            return .met(RepeatUntil.MetCheck(
                observation: actionObservation,
                expectation: expectation,
                receipt: receipt
            ))
        case .unmet(let expectation):
            let receipt = HeistWaitReceipt.timedOut(
                message: expectation.actual,
                traceEvidence: traceEvidence,
                expectation: expectation,
                observedSequence: sequence,
                observationSummary: actionObservation.summary
            )
            return .unmet(RepeatUntil.UnmetCheck(
                observation: actionObservation,
                expectation: expectation,
                receipt: receipt
            ))
        }
    }

    private func repeatUntilActionResultCarriesSettledChange(_ result: ActionResult) -> Bool {
        guard result.outcome.isSuccess,
              result.settled == true,
              let evidence = result.traceEvidence
        else { return false }
        return !evidence.trace.changeFacts.isEmpty
    }

    private func repeatUntilObservedSequence(
        after observation: RepeatUntil.Observation,
        result: ActionResult
    ) -> SettledObservationSequence {
        let nextSequence = observation.sequence + 1
        guard let subjectSequence = result.subjectEvidence?.settledObservationSequence else {
            return nextSequence
        }
        return max(nextSequence, subjectSequence + 1)
    }

    private func repeatUntilObservationSummary(_ trace: AccessibilityTrace) -> String? {
        guard let elementCount = trace.captures.last?.interface.projectedElements.count else {
            return nil
        }
        return "interface: \(elementCount) elements"
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
