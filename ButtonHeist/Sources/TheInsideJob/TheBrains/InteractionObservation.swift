#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

private let defaultSemanticObservationTimeout: Double = 1

/// Owns the before/body/after observation contract for executable interactions.
@MainActor
final class InteractionObservation {
    private let stash: TheStash
    private let tripwire: TheTripwire
    private let postActionObservation: PostActionObservation

    init(stash: TheStash, tripwire: TheTripwire, postActionObservation: PostActionObservation) {
        self.stash = stash
        self.tripwire = tripwire
        self.postActionObservation = postActionObservation
    }

    func prepareBeforeState(timeout: Double? = 1.0) async -> PostActionObservation.BeforeState? {
        guard let event = await stash.settledSemanticObservationEvent(
            scope: .visible, after: nil, timeout: timeout
        ) else { return nil }
        return postActionObservation.captureSemanticState(from: event.observation)
    }

    func observeSemanticState(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> HeistSemanticObservation? {
        let event = await stash.settledSemanticObservationEvent(
            scope: scope,
            after: sequence,
            timeout: timeout ?? defaultSemanticObservationTimeout
        )

        guard let event else { return nil }
        return semanticObservation(from: event)
    }

    func finishAfterAction(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        payload: ResultPayload? = nil,
        afterStatePayload: ((PostActionObservation.BeforeState) -> ResultPayload?)? = nil,
        errorKind: ErrorKind? = nil,
        subjectEvidence: ActionSubjectEvidence? = nil,
        before: PostActionObservation.BeforeState,
        settleOutcome: SettleSession.Outcome? = nil
    ) async -> ActionResult {
        let settleResult = await resolvedSettleOutcome(settleOutcome, baseline: before)
        let didSettle = settleResult.outcome.didSettleCleanly
        if case .cancelled(let cancelMs) = settleResult.outcome {
            return InteractionObservationProjection.failedActionResult(
                method: method, capture: before.capture, message: "cancelled after \(cancelMs)ms",
                payload: payload, subjectEvidence: subjectEvidence, settled: false,
                settleTimeMs: cancelMs
            )
        }

        guard let afterScreen = settleResult.finalScreen else {
            return InteractionObservationProjection.failedActionResult(
                method: method, capture: before.capture, message: "Could not parse post-action accessibility tree",
                payload: payload, subjectEvidence: subjectEvidence, settled: didSettle,
                settleTimeMs: settleResult.outcome.timeMs
            )
        }

        stash.recordSettledSemanticObservation(afterScreen)
        guard let visibleEvent = stash.latestSettledSemanticObservationEvent else {
            return InteractionObservationProjection.failedActionResult(
                method: method, capture: before.capture,
                message: "Could not produce post-action settled semantic observation",
                payload: payload, subjectEvidence: subjectEvidence, settled: didSettle,
                settleTimeMs: settleResult.outcome.timeMs
            )
        }
        let finalState = await semanticStateAfterDiscovery(after: visibleEvent.sequence)
            ?? postActionObservation.captureSemanticState(from: visibleEvent.observation)
        let finalClassification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: finalState.screenSnapshot
        )
        let trace = postActionObservation.makeAccessibilityTrace(
            afterInterface: finalState.interface,
            parentCapture: before.capture,
            classification: finalClassification,
            transient: InteractionObservationProjection.transientElements(
                settleResult: settleResult,
                before: before,
                final: finalState,
                classification: finalClassification
            )
        )

        guard let postCapture = trace.captures.last else {
            let resolvedPayload = success ? (afterStatePayload?(finalState) ?? payload) : payload
            return InteractionObservationProjection.failedActionResult(
                method: method, capture: before.capture, message: message,
                payload: resolvedPayload, subjectEvidence: subjectEvidence
            )
        }

        let resolvedPayload = success ? (afterStatePayload?(finalState) ?? payload) : payload
        return InteractionObservationProjection.actionResult(
            method: method, capture: postCapture, message: message, payload: resolvedPayload,
            errorKind: errorKind, accessibilityTrace: trace, subjectEvidence: subjectEvidence,
            settled: didSettle, settleTimeMs: settleResult.outcome.timeMs, success: success
        )
    }

    func waitForPredicate(
        _ step: WaitStep,
        initialTrace: AccessibilityTrace? = nil,
        after sequence: UInt64? = nil,
        evaluateCurrent: Bool = true
    ) async -> HeistWaitReceipt {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = max(0, min(step.timeout, 30))
        var lastObservation: HeistSemanticObservation?
        var lastTrace: AccessibilityTrace?
        var lastObservationSummary: String?
        var observedSequence: UInt64? = sequence
        var lastEvaluation = ExpectationResult(
            met: false, predicate: step.predicate, actual: "no settled semantic observation available"
        )

        if evaluateCurrent, let initialTraceResult = InteractionObservationProjection.initialTraceResult(
            for: step,
            initialTrace: initialTrace,
            timeout: timeout
        ) {
            lastTrace = initialTraceResult.trace
            lastObservationSummary = initialTraceResult.summary
            lastEvaluation = initialTraceResult.expectation
            observedSequence = stash.latestSettledSemanticObservationEvent?.sequence
            if initialTraceResult.shouldReturn {
                return waitReceipt(for: step, trace: initialTraceResult.trace,
                                   observationSummary: initialTraceResult.summary,
                                   expectation: initialTraceResult.expectation, start: start,
                                   success: initialTraceResult.expectation.met)
            }
        } else if evaluateCurrent,
                  let initial = await observeSemanticState(
                    scope: step.predicate.observationScope, after: observedSequence, timeout: 0
                  ) {
            lastObservation = initial
            lastTrace = initial.accessibilityTrace
            lastObservationSummary = initial.summary
            observedSequence = initial.event.sequence
            lastEvaluation = InteractionObservationProjection.evaluate(step.predicate, in: initial)
            if lastEvaluation.met {
                return waitReceipt(for: step, observation: initial,
                                   expectation: lastEvaluation, start: start, success: true)
            }
        } else if timeout == 0,
                  let observation = await observeSemanticState(
                    scope: step.predicate.observationScope, after: observedSequence, timeout: 0
                  ) {
            lastObservation = observation
            lastTrace = observation.accessibilityTrace
            lastObservationSummary = observation.summary
            observedSequence = observation.event.sequence
            lastEvaluation = InteractionObservationProjection.evaluate(step.predicate, in: observation)
            return waitReceipt(for: step, observation: observation,
                               expectation: lastEvaluation, start: start, success: lastEvaluation.met)
        } else if timeout == 0 {
            return waitReceipt(for: step, observation: nil,
                               expectation: lastEvaluation, start: start, success: false)
        }

        guard timeout > 0 else {
            return waitReceipt(for: step, observation: lastObservation,
                               expectation: lastEvaluation, start: start, success: false)
        }

        let deadline = start + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
            guard let observation = await observeSemanticState(
                scope: step.predicate.observationScope, after: observedSequence,
                timeout: min(remaining, defaultSemanticObservationTimeout)
            ) else {
                continue
            }

            observedSequence = observation.event.sequence
            lastObservation = observation
            lastTrace = observation.accessibilityTrace
            lastObservationSummary = observation.summary
            lastEvaluation = InteractionObservationProjection.evaluate(step.predicate, in: observation)
            if lastEvaluation.met {
                return waitReceipt(for: step, observation: observation,
                                   expectation: lastEvaluation, start: start, success: true)
            }
        }

        return waitReceipt(for: step, trace: lastObservation?.accessibilityTrace ?? lastTrace,
                           observationSummary: lastObservation?.summary ?? lastObservationSummary,
                           expectation: lastEvaluation, start: start, success: false)
    }

    func waitForPredicateAfterCurrentSettledSequence(_ step: WaitStep) async -> HeistWaitReceipt {
        await waitForPredicate(
            step, after: stash.latestSettledSemanticObservationEvent?.sequence, evaluateCurrent: false
        )
    }

    private func semanticObservation(
        from event: SettledSemanticObservationEvent
    ) -> HeistSemanticObservation {
        let current = postActionObservation.captureSemanticState(from: event.observation)
        return InteractionObservationProjection.semanticObservation(event: event, state: current)
    }

    private func semanticStateAfterDiscovery(after sequence: UInt64?) async -> PostActionObservation.BeforeState? {
        guard let event = await stash.settledSemanticObservationEvent(
            scope: .discovery,
            after: sequence,
            timeout: 2.0
        ) else { return nil }
        return postActionObservation.captureSemanticState(from: event.observation)
    }

    private func resolvedSettleOutcome(
        _ settleOutcome: SettleSession.Outcome?,
        baseline: PostActionObservation.BeforeState
    ) async -> SettleSession.Outcome {
        if let settleOutcome {
            return settleOutcome
        }
        let start = CFAbsoluteTimeGetCurrent()
        let settleSession = SettleSession.live(stash: stash, tripwire: tripwire)
        return await settleSession.run(start: start, baselineTripwireSignal: baseline.tripwireSignal)
    }

    private func waitReceipt(
        for step: WaitStep,
        observation: HeistSemanticObservation? = nil,
        trace: AccessibilityTrace? = nil,
        observationSummary: String? = nil,
        expectation: ExpectationResult,
        start: CFAbsoluteTime,
        success: Bool
    ) -> HeistWaitReceipt {
        let summary = observation?.summary ?? observationSummary
        let elapsed = InteractionObservationProjection.elapsedSeconds(since: start)
        let presenceMessage = success || summary == nil
            ? nil
            : stash.presenceWaitTimeoutMessage(for: step.predicate, elapsed: elapsed)
        return InteractionObservationProjection.waitReceipt(
            for: step,
            trace: observation?.accessibilityTrace ?? trace,
            observationSummary: summary,
            expectation: expectation,
            elapsed: elapsed,
            success: success,
            presenceTimeoutMessage: presenceMessage
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
