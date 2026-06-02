#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

private let defaultSemanticObservationTimeout: Double = 1

struct HeistSemanticObservation {
    let event: TheStash.SettledSemanticObservationEvent
    let state: PostActionObservation.BeforeState
    let accessibilityTrace: AccessibilityTrace
    let delta: AccessibilityTrace.Delta?
    let summary: String
}

/// Owns the before/body/after observation contract for executable interactions.
@MainActor
final class InteractionObservation {
    private let stash: TheStash
    private let tripwire: TheTripwire
    private let postActionObservation: PostActionObservation

    init(
        stash: TheStash,
        tripwire: TheTripwire,
        postActionObservation: PostActionObservation
    ) {
        self.stash = stash
        self.tripwire = tripwire
        self.postActionObservation = postActionObservation
    }

    func prepareBeforeState(timeout: Double? = 1.0) async -> PostActionObservation.BeforeState? {
        guard let event = await stash.settledSemanticObservationEvent(
            scope: .visible,
            after: nil,
            timeout: timeout
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
        errorKind: ErrorKind? = nil,
        before: PostActionObservation.BeforeState,
        settleOutcome: SettleSession.Outcome? = nil
    ) async -> ActionResult {
        let settleResult = await resolvedSettleOutcome(settleOutcome, baseline: before)
        let didSettle = settleResult.outcome.didSettleCleanly
        if case .cancelled(let cancelMs) = settleResult.outcome {
            var builder = ActionResultBuilder(method: method, capture: before.capture)
            builder.message = "cancelled after \(cancelMs)ms"
            builder.settled = false
            builder.settleTimeMs = cancelMs
            return builder.failure(errorKind: .actionFailed, payload: payload)
        }

        guard let afterScreen = settleResult.finalScreen else {
            var builder = ActionResultBuilder(method: method, capture: before.capture)
            builder.message = "Could not parse post-action accessibility tree"
            builder.settled = didSettle
            builder.settleTimeMs = settleResult.outcome.timeMs
            return builder.failure(errorKind: .actionFailed, payload: payload)
        }

        stash.recordSettledSemanticObservation(afterScreen)
        guard let visibleEvent = stash.latestSettledSemanticObservationEvent else {
            var builder = ActionResultBuilder(method: method, capture: before.capture)
            builder.message = "Could not produce post-action settled semantic observation"
            builder.settled = didSettle
            builder.settleTimeMs = settleResult.outcome.timeMs
            return builder.failure(errorKind: .actionFailed, payload: payload)
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
            transient: transientElements(
                settleResult: settleResult,
                before: before,
                final: finalState,
                classification: finalClassification
            )
        )

        guard let postCapture = trace.captures.last else {
            return failureActionResult(
                method: method,
                message: message,
                payload: payload,
                errorKind: .actionFailed,
                before: before
            )
        }

        var builder = ActionResultBuilder(method: method, capture: postCapture)
        builder.message = message
        builder.accessibilityTrace = trace
        builder.settled = didSettle
        builder.settleTimeMs = settleResult.outcome.timeMs
        if success {
            return builder.success(payload: payload)
        }
        return builder.failure(errorKind: errorKind ?? .actionFailed, payload: payload)
    }

    func waitForPredicate(_ step: WaitStep, initialTrace: AccessibilityTrace? = nil) async -> HeistWaitReceipt {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = max(0, min(step.timeout, 30))
        var lastObservation: HeistSemanticObservation?
        var lastTrace: AccessibilityTrace?
        var lastObservationSummary: String?
        var observedSequence: UInt64?
        var lastEvaluation = ExpectationResult(
            met: false,
            predicate: step.predicate,
            actual: "no settled semantic observation available"
        )

        if let initialTraceResult = initialTraceResult(for: step, initialTrace: initialTrace, start: start, timeout: timeout) {
            lastTrace = initialTraceResult.trace
            lastObservationSummary = initialTraceResult.summary
            lastEvaluation = initialTraceResult.expectation
            observedSequence = stash.latestSettledSemanticObservationEvent?.sequence
            if initialTraceResult.shouldReturn {
                return initialTraceResult.receipt
            }
        } else if let initial = await observeSemanticState(scope: step.predicate.observationScope, after: nil, timeout: 0) {
            lastObservation = initial
            lastTrace = initial.accessibilityTrace
            lastObservationSummary = initial.summary
            observedSequence = initial.event.sequence
            lastEvaluation = evaluate(step.predicate, in: initial)
            if lastEvaluation.met {
                return waitReceipt(
                    for: step,
                    observation: initial,
                    expectation: lastEvaluation,
                    start: start,
                    success: true
                )
            }
        } else if timeout == 0 {
            return waitReceipt(
                for: step,
                observation: nil,
                expectation: lastEvaluation,
                start: start,
                success: false
            )
        }

        guard timeout > 0 else {
            return waitReceipt(
                for: step,
                observation: lastObservation,
                expectation: lastEvaluation,
                start: start,
                success: false
            )
        }

        let deadline = start + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
            guard let observation = await observeSemanticState(
                scope: step.predicate.observationScope,
                after: observedSequence,
                timeout: min(remaining, defaultSemanticObservationTimeout)
            ) else {
                continue
            }

            observedSequence = observation.event.sequence
            lastObservation = observation
            lastTrace = observation.accessibilityTrace
            lastObservationSummary = observation.summary
            lastEvaluation = evaluate(step.predicate, in: observation)
            if lastEvaluation.met {
                return waitReceipt(
                    for: step,
                    observation: observation,
                    expectation: lastEvaluation,
                    start: start,
                    success: true
                )
            }
        }

        return waitReceipt(
            for: step,
            trace: lastObservation?.accessibilityTrace ?? lastTrace,
            observationSummary: lastObservation?.summary ?? lastObservationSummary,
            expectation: lastEvaluation,
            start: start,
            success: false
        )
    }

    func recordDeliveredBaselineAfterStep() async -> PostActionObservation.BeforeState? {
        (await observeSemanticState(scope: .visible, after: nil, timeout: 0))?.state
    }

    private func initialTraceResult(
        for step: WaitStep,
        initialTrace: AccessibilityTrace?,
        start: CFAbsoluteTime,
        timeout: Double
    ) -> (
        trace: AccessibilityTrace,
        summary: String?,
        expectation: ExpectationResult,
        shouldReturn: Bool,
        receipt: HeistWaitReceipt
    )? {
        guard let initialTrace else { return nil }
        let expectation = evaluate(step.predicate, in: initialTrace)
        let shouldReturn = expectation.met || timeout == 0
        return (
            trace: initialTrace,
            summary: traceSummary(initialTrace),
            expectation: expectation,
            shouldReturn: shouldReturn,
            receipt: waitReceipt(
                for: step,
                trace: initialTrace,
                observationSummary: traceSummary(initialTrace),
                expectation: expectation,
                start: start,
                success: expectation.met
            )
        )
    }

    private func semanticObservation(
        from event: TheStash.SettledSemanticObservationEvent
    ) -> HeistSemanticObservation {
        let current = postActionObservation.captureSemanticState(from: event.observation)
        return HeistSemanticObservation(
            event: event,
            state: current,
            accessibilityTrace: event.trace,
            delta: event.delta,
            summary: heistObservationSummary(current)
        )
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

    private func transientElements(
        settleResult: SettleSession.Outcome,
        before: PostActionObservation.BeforeState,
        final: PostActionObservation.BeforeState,
        classification: ScreenClassifier.Classification
    ) -> [HeistElement] {
        guard !classification.isScreenChange,
              !settleResult.events.containsTripwireSignalChange else {
            return []
        }
        return SettleSession.transientElements(
            seenByKey: settleResult.elementsByKey,
            baseline: before.elements,
            final: final.elements
        ).map { TheStash.WireConversion.convert($0) }
    }

    private func failureActionResult(
        method: ActionMethod,
        message: String?,
        payload: ResultPayload?,
        errorKind: ErrorKind?,
        before: PostActionObservation.BeforeState
    ) -> ActionResult {
        let kind = errorKind ?? .actionFailed
        var builder = ActionResultBuilder(method: method, capture: before.capture)
        builder.message = message
        return builder.failure(errorKind: kind, payload: payload)
    }

    private func evaluate(
        _ predicate: AccessibilityPredicate,
        in observation: HeistSemanticObservation
    ) -> ExpectationResult {
        predicate.evaluate(
            currentElements: observation.state.interface.projectedElements,
            delta: observation.delta
        )
    }

    private func evaluate(
        _ predicate: AccessibilityPredicate,
        in trace: AccessibilityTrace
    ) -> ExpectationResult {
        predicate.evaluate(
            currentElements: trace.captures.last?.interface.projectedElements ?? [],
            delta: trace.endpointDeltaProjection
        )
    }

    private func traceSummary(_ trace: AccessibilityTrace) -> String? {
        guard let capture = trace.captures.last else { return nil }
        var parts = ["known: \(capture.interface.projectedElements.count) elements"]
        if let screenId = capture.context.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    private func heistObservationSummary(_ state: PostActionObservation.BeforeState) -> String {
        var parts = ["known: \(state.interface.projectedElements.count) elements"]
        if let screenId = state.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    private func waitReceipt(
        for step: WaitStep,
        observation: HeistSemanticObservation?,
        expectation: ExpectationResult,
        start: CFAbsoluteTime,
        success: Bool
    ) -> HeistWaitReceipt {
        waitReceipt(
            for: step,
            trace: observation?.accessibilityTrace,
            observationSummary: observation?.summary,
            expectation: expectation,
            start: start,
            success: success
        )
    }

    private func waitReceipt(
        for step: WaitStep,
        trace: AccessibilityTrace?,
        observationSummary: String?,
        expectation: ExpectationResult,
        start: CFAbsoluteTime,
        success: Bool
    ) -> HeistWaitReceipt {
        var builder = ActionResultBuilder(method: .wait)
        builder.accessibilityTrace = trace
        builder.message = success
            ? waitSuccessMessage(for: step.predicate, start: start)
            : waitTimeoutMessage(
                for: step,
                expectation: expectation,
                observationSummary: observationSummary,
                start: start
            )

        let actionResult = success
            ? builder.success()
            : builder.failure(errorKind: .timeout)
        return HeistWaitReceipt(actionResult: actionResult, expectation: expectation)
    }

    private func waitSuccessMessage(
        for predicate: AccessibilityPredicate,
        start: CFAbsoluteTime
    ) -> String {
        let elapsed = elapsedSeconds(since: start)
        switch predicate {
        case .state(.present):
            return elapsed == "0.0" ? "matched immediately" : "matched after \(elapsed)s"
        case .state(.absent):
            return "absent confirmed after \(elapsed)s"
        default:
            return "predicate met after \(elapsed)s"
        }
    }

    private func waitTimeoutMessage(
        for step: WaitStep,
        expectation: ExpectationResult,
        observationSummary: String?,
        start: CFAbsoluteTime
    ) -> String {
        let elapsed = elapsedSeconds(since: start)
        guard let observationSummary else {
            return [
                "timed out after \(elapsed)s waiting for heist predicate",
                "expected: \(step.predicate.description)",
                "last result: \(expectation.actual ?? "not met")",
                "last observed: no settled semantic observation available",
            ].joined(separator: "; ")
        }

        if let presenceMessage = stash.presenceWaitTimeoutMessage(for: step.predicate, elapsed: elapsed) {
            return presenceMessage
        }

        return [
            "timed out after \(elapsed)s waiting for heist predicate",
            "expected: \(step.predicate.description)",
            "last result: \(expectation.actual ?? "not met")",
            "last observed: \(observationSummary)",
        ].joined(separator: "; ")
    }

    private func elapsedSeconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
