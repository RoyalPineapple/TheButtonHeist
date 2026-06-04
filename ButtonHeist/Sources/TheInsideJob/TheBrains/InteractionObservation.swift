#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

private let defaultSemanticObservationTimeout: Double = 1

/// Owns the before/body/after observation contract for executable interactions.
///
/// It coordinates settled semantic evidence. It does not choose command
/// payloads, resolve actionability, decide recording policy, or format reports.
@MainActor
final class InteractionObservation {
    private let stash: TheStash
    private let postActionObservation: PostActionObservation

    private struct PostActionSettleEvidence {
        let outcome: SettleSession.Outcome
        let visibleEvent: SettledSemanticObservationEvent?

        var didSettleCleanly: Bool {
            outcome.outcome.didSettleCleanly
        }

        var timeMs: Int {
            outcome.outcome.timeMs
        }
    }

    private struct FinalSemanticEvidence {
        let state: PostActionObservation.BeforeState
        let trace: AccessibilityTrace

        var capture: AccessibilityTrace.Capture? {
            trace.captures.last
        }
    }

    init(stash: TheStash, postActionObservation: PostActionObservation) {
        self.stash = stash
        self.postActionObservation = postActionObservation
    }

    func prepareBeforeState(timeout: Double? = 1.0) async -> PostActionObservation.BeforeState? {
        guard let event = await stash.observeSettledSemanticObservation(
            scope: .visible, after: nil, timeout: timeout
        ) else { return nil }
        return postActionObservation.captureSemanticState(from: event.observation)
    }

    func observeSemanticState(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> HeistSemanticObservation? {
        let event = await stash.observeSettledSemanticObservation(
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
        let settleEvidence = await settleAfterAction(before: before, outcome: settleOutcome)
        if let cancelled = cancelledActionResult(
            method: method,
            payload: payload,
            subjectEvidence: subjectEvidence,
            before: before,
            settleEvidence: settleEvidence
        ) {
            return cancelled
        }

        guard let finalEvidence = await finalSemanticEvidence(
            before: before,
            settleEvidence: settleEvidence
        ) else {
            return postActionParseFailureResult(
                method: method,
                payload: payload,
                subjectEvidence: subjectEvidence,
                before: before,
                settleEvidence: settleEvidence
            )
        }

        let resolvedPayload = actionPayload(
            success: success,
            payload: payload,
            afterStatePayload: afterStatePayload,
            finalState: finalEvidence.state
        )

        guard finalEvidence.capture != nil else {
            return InteractionObservationProjection.failedActionResult(
                method: method,
                capture: before.capture,
                message: message,
                payload: resolvedPayload,
                subjectEvidence: subjectEvidence
            )
        }

        return buildActionResult(
            success: success,
            method: method,
            message: message,
            payload: resolvedPayload,
            errorKind: errorKind,
            subjectEvidence: subjectEvidence,
            finalEvidence: finalEvidence,
            settleEvidence: settleEvidence
        )
    }

    func waitForPredicate(
        _ step: WaitStep,
        initialTrace: AccessibilityTrace? = nil
    ) async -> HeistWaitReceipt {
        do {
            return await waitForPredicate(
                try step.resolve(in: .empty),
                initialTrace: initialTrace
            )
        } catch {
            let predicate = InteractionObservationProjection.unresolvedWaitPredicate()
            let resolvedStep = ResolvedWaitStep(predicate: predicate, timeout: step.timeout)
            let expectation = ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "\(error)"
            )
            return waitReceipt(
                for: resolvedStep,
                trace: nil,
                observationSummary: nil,
                expectation: expectation,
                start: CFAbsoluteTimeGetCurrent(),
                success: false
            )
        }
    }

    func waitForPredicate(
        _ step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace? = nil
    ) async -> HeistWaitReceipt {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = InteractionObservationProjection.clampedWaitTimeout(step.timeout)
        var state = WaitPredicateState(predicate: step.predicate)

        if let initialTraceResult = InteractionObservationProjection.initialTraceResult(
            for: step,
            initialTrace: initialTrace,
            timeout: timeout
        ) {
            state.record(
                initialTraceResult,
                latestSequence: stash.latestSettledSemanticObservationEvent?.sequence
            )
            if initialTraceResult.shouldReturn {
                return waitReceipt(
                    for: step,
                    state: state,
                    start: start,
                    success: state.lastEvaluation.met
                )
            }
        } else if step.predicate.requiresFutureSettledBaseline {
            guard let baseline = await changedPredicateBaseline(
                scope: step.predicate.observationScope,
                timeout: min(timeout, defaultSemanticObservationTimeout)
            ) else {
                return waitReceipt(
                    for: step,
                    state: state,
                    start: start,
                    success: false
                )
            }
            state.changeBaseline = baseline
            state.observedSequence = baseline.sequence
        } else if let initial = await nextWaitEvaluation(
            for: step, after: state.observedSequence, timeout: 0
        ) {
            state.record(initial)
            if state.lastEvaluation.met {
                return waitReceipt(for: step, state: state, start: start, success: true)
            }
        } else if timeout == 0,
                  let observation = await nextWaitEvaluation(
                    for: step, after: state.observedSequence, timeout: 0
                  ) {
            state.record(observation)
            return waitReceipt(
                for: step,
                state: state,
                start: start,
                success: state.lastEvaluation.met
            )
        } else if timeout == 0 {
            return waitReceipt(
                for: step,
                state: state,
                start: start,
                success: false
            )
        }

        guard timeout > 0 else {
            return waitReceipt(
                for: step,
                state: state,
                start: start,
                success: false
            )
        }

        let deadline = start + timeout
        while CFAbsoluteTimeGetCurrent() < deadline {
            let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
            guard let observation = await nextWaitEvaluation(
                for: step,
                after: state.observedSequence,
                timeout: min(remaining, defaultSemanticObservationTimeout)
            ) else {
                continue
            }

            state.record(observation)
            if state.lastEvaluation.met {
                return waitReceipt(for: step, state: state, start: start, success: true)
            }
        }

        return waitReceipt(
            for: step,
            state: state,
            start: start,
            success: false
        )
    }

    func waitForPredicateCases(
        _ cases: [ResolvedPredicateCase],
        timeout rawTimeout: Double
    ) async -> HeistCaseSelectionResult {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = InteractionObservationProjection.clampedWaitTimeout(rawTimeout)
        let scope = cases.observationScope
        let requiresChangeBaseline = cases.contains { $0.predicate.requiresFutureSettledBaseline }
        var observedSequence: UInt64?
        var changeBaselineSequence: UInt64?
        var lastSelection = PredicateCaseSelection.unevaluated(cases)
        var lastSummary: String?

        repeat {
            let remaining = max(0, start + timeout - CFAbsoluteTimeGetCurrent())
            guard let observation = await observeSemanticState(
                scope: scope,
                after: observedSequence,
                timeout: min(remaining, defaultSemanticObservationTimeout)
            ) else {
                if timeout == 0 { break }
                continue
            }

            observedSequence = observation.event.sequence
            lastSummary = observation.summary
            if requiresChangeBaseline, changeBaselineSequence == nil {
                changeBaselineSequence = observation.event.sequence
            }

            lastSelection = PredicateCaseSelection.evaluate(
                cases,
                observation: observation,
                changeBaselineSequence: changeBaselineSequence
            )

            if lastSelection.selectedCaseIndex != nil {
                return HeistCaseSelectionResult(
                    cases: lastSelection.cases,
                    selectedCaseIndex: lastSelection.selectedCaseIndex,
                    elapsedMs: elapsedMillisecondsSince(start),
                    timeout: rawTimeout,
                    lastObservedSummary: observation.summary
                )
            }

            if timeout == 0 { break }
        } while CFAbsoluteTimeGetCurrent() < start + timeout

        return HeistCaseSelectionResult(
            cases: lastSelection.cases,
            selectedCaseIndex: nil,
            elapsedMs: elapsedMillisecondsSince(start),
            timeout: rawTimeout,
            timedOut: true,
            lastObservedSummary: lastSummary
        )
    }

    private func semanticObservation(
        from event: SettledSemanticObservationEvent
    ) -> HeistSemanticObservation {
        let current = postActionObservation.captureSemanticState(from: event.observation)
        return InteractionObservationProjection.semanticObservation(event: event, state: current)
    }

    private func elapsedMillisecondsSince(_ start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    private func changedPredicateBaseline(
        scope: SemanticObservationScope,
        timeout: Double
    ) async -> SettledSemanticObservationEvent? {
        if let latest = stash.latestSettledSemanticObservationEvent {
            return latest
        }
        return await stash.observeSettledSemanticObservation(
            scope: scope,
            after: nil,
            timeout: timeout
        )
    }

    private func semanticStateAfterDiscovery(after sequence: UInt64?) async -> PostActionObservation.BeforeState? {
        guard let event = await stash.observeSettledSemanticObservation(
            scope: .discovery,
            after: sequence,
            timeout: 2.0
        ) else { return nil }
        return postActionObservation.captureSemanticState(from: event.observation)
    }

    private func settleAfterAction(
        before: PostActionObservation.BeforeState,
        outcome: SettleSession.Outcome?
    ) async -> PostActionSettleEvidence {
        let settledObservation = await stash.semanticObservationStream.settlePostActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            settleOutcome: outcome
        )
        return PostActionSettleEvidence(
            outcome: settledObservation.settle,
            visibleEvent: settledObservation.event
        )
    }

    private func finalSemanticEvidence(
        before: PostActionObservation.BeforeState,
        settleEvidence: PostActionSettleEvidence
    ) async -> FinalSemanticEvidence? {
        guard let visibleEvent = settleEvidence.visibleEvent else { return nil }
        let finalState = await captureFinalSemanticState(after: visibleEvent)
        let trace = buildPostActionTrace(
            before: before,
            final: finalState,
            settleEvidence: settleEvidence
        )
        return FinalSemanticEvidence(state: finalState, trace: trace)
    }

    private func captureFinalSemanticState(
        after visibleEvent: SettledSemanticObservationEvent
    ) async -> PostActionObservation.BeforeState {
        await semanticStateAfterDiscovery(after: visibleEvent.sequence)
            ?? postActionObservation.captureSemanticState(from: visibleEvent.observation)
    }

    private func buildPostActionTrace(
        before: PostActionObservation.BeforeState,
        final: PostActionObservation.BeforeState,
        settleEvidence: PostActionSettleEvidence
    ) -> AccessibilityTrace {
        let classification = ScreenClassifier.classify(
            before: before.screenSnapshot,
            after: final.screenSnapshot
        )
        return postActionObservation.makeAccessibilityTrace(
            afterInterface: final.interface,
            parentCapture: before.capture,
            classification: classification,
            transient: InteractionObservationProjection.transientElements(
                settleResult: settleEvidence.outcome,
                before: before,
                final: final,
                classification: classification
            )
        )
    }

    private func actionPayload(
        success: Bool,
        payload: ResultPayload?,
        afterStatePayload: ((PostActionObservation.BeforeState) -> ResultPayload?)?,
        finalState: PostActionObservation.BeforeState
    ) -> ResultPayload? {
        success ? (afterStatePayload?(finalState) ?? payload) : payload
    }

    private func cancelledActionResult(
        method: ActionMethod,
        payload: ResultPayload?,
        subjectEvidence: ActionSubjectEvidence?,
        before: PostActionObservation.BeforeState,
        settleEvidence: PostActionSettleEvidence
    ) -> ActionResult? {
        guard case .cancelled(let cancelMs) = settleEvidence.outcome.outcome else { return nil }
        return InteractionObservationProjection.failedActionResult(
            method: method,
            capture: before.capture,
            message: "cancelled after \(cancelMs)ms",
            payload: payload,
            subjectEvidence: subjectEvidence,
            settled: false,
            settleTimeMs: cancelMs
        )
    }

    private func postActionParseFailureResult(
        method: ActionMethod,
        payload: ResultPayload?,
        subjectEvidence: ActionSubjectEvidence?,
        before: PostActionObservation.BeforeState,
        settleEvidence: PostActionSettleEvidence
    ) -> ActionResult {
        InteractionObservationProjection.failedActionResult(
            method: method,
            capture: before.capture,
            message: "Could not parse post-action accessibility tree",
            payload: payload,
            subjectEvidence: subjectEvidence,
            settled: settleEvidence.didSettleCleanly,
            settleTimeMs: settleEvidence.timeMs
        )
    }

    private func buildActionResult(
        success: Bool,
        method: ActionMethod,
        message: String?,
        payload: ResultPayload?,
        errorKind: ErrorKind?,
        subjectEvidence: ActionSubjectEvidence?,
        finalEvidence: FinalSemanticEvidence,
        settleEvidence: PostActionSettleEvidence
    ) -> ActionResult {
        InteractionObservationProjection.actionResult(
            method: method,
            capture: finalEvidence.capture ?? finalEvidence.state.capture,
            message: message,
            payload: payload,
            errorKind: errorKind,
            accessibilityTrace: finalEvidence.trace,
            subjectEvidence: subjectEvidence,
            settled: settleEvidence.didSettleCleanly,
            settleTimeMs: settleEvidence.timeMs,
            success: success
        )
    }

    private func waitReceipt(
        for step: ResolvedWaitStep,
        trace: AccessibilityTrace? = nil,
        observationSummary: String? = nil,
        expectation: ExpectationResult,
        start: CFAbsoluteTime,
        success: Bool,
        changeBaseline: SettledSemanticObservationEvent? = nil,
        sawFutureObservation: Bool = false
    ) -> HeistWaitReceipt {
        let summary = observationSummary
        let elapsed = InteractionObservationProjection.elapsedSeconds(since: start)
        let presenceMessage = success || summary == nil
            ? nil
            : stash.presenceWaitTimeoutMessage(for: step.predicate, elapsed: elapsed)
        let settledDiagnostics = success ? nil : InteractionObservationProjection.SettledWaitDiagnostics(
            baseline: changeBaseline.map(InteractionObservationProjection.SettledEventSummary.init(event:)),
            last: stash.latestSettledSemanticObservationEvent.map(
                InteractionObservationProjection.SettledEventSummary.init(event:)
            ),
            lastDelta: trace?.endpointDeltaProjection ?? stash.latestSettledSemanticObservationEvent?.delta,
            sawFutureObservation: sawFutureObservation
        )
        return InteractionObservationProjection.waitReceipt(
            for: step,
            trace: trace,
            observationSummary: summary,
            expectation: expectation,
            elapsed: elapsed,
            success: success,
            presenceTimeoutMessage: presenceMessage,
            settledDiagnostics: settledDiagnostics
        )
    }

    private func waitReceipt(
        for step: ResolvedWaitStep,
        state: WaitPredicateState,
        start: CFAbsoluteTime,
        success: Bool
    ) -> HeistWaitReceipt {
        waitReceipt(
            for: step,
            trace: state.lastTrace,
            observationSummary: state.lastObservationSummary,
            expectation: state.lastEvaluation,
            start: start,
            success: success,
            changeBaseline: state.changeBaseline,
            sawFutureObservation: state.sawFutureObservation
        )
    }

    private func nextWaitEvaluation(
        for step: ResolvedWaitStep,
        after sequence: UInt64?,
        timeout: Double
    ) async -> WaitEvaluation? {
        guard let observation = await observeSemanticState(
            scope: step.predicate.observationScope,
            after: sequence,
            timeout: timeout
        ) else { return nil }
        return (observation, InteractionObservationProjection.evaluate(step.predicate, in: observation))
    }

}

private typealias WaitEvaluation = (observation: HeistSemanticObservation, expectation: ExpectationResult)

private struct WaitPredicateState {
    var lastTrace: AccessibilityTrace?
    var lastObservationSummary: String?
    var observedSequence: UInt64?
    var changeBaseline: SettledSemanticObservationEvent?
    var sawFutureObservation = false
    var lastEvaluation: ExpectationResult

    init(predicate: AccessibilityPredicate) {
        lastEvaluation = ExpectationResult(
            met: false,
            predicate: predicate,
            actual: "no settled semantic observation available"
        )
    }

    mutating func record(
        _ initialTraceResult: InteractionObservationProjection.InitialTraceResult,
        latestSequence: UInt64?
    ) {
        lastTrace = initialTraceResult.trace
        lastObservationSummary = initialTraceResult.summary
        lastEvaluation = initialTraceResult.expectation
        observedSequence = latestSequence
    }

    mutating func record(_ evaluation: WaitEvaluation) {
        lastTrace = evaluation.observation.accessibilityTrace
        lastObservationSummary = evaluation.observation.summary
        lastEvaluation = evaluation.expectation
        observedSequence = evaluation.observation.event.sequence
        sawFutureObservation = changeBaseline
            .map { evaluation.observation.event.sequence > $0.sequence } ?? false
    }
}

struct PredicateCaseSelection {
    let cases: [HeistCaseMatchResult]
    let selectedCaseIndex: Int?

    static func unevaluated(_ cases: [ResolvedPredicateCase]) -> PredicateCaseSelection {
        PredicateCaseSelection(
            cases: cases.map {
                HeistCaseMatchResult(
                    predicate: $0.predicate,
                    result: ExpectationResult(
                        met: false,
                        predicate: $0.predicate,
                        actual: "no settled accessibility state observed"
                    )
                )
            },
            selectedCaseIndex: nil
        )
    }

    static func evaluate(
        _ cases: [ResolvedPredicateCase],
        observation: HeistSemanticObservation,
        changeBaselineSequence: UInt64? = nil
    ) -> PredicateCaseSelection {
        let evaluatedCases = cases.map {
            HeistCaseMatchResult(
                predicate: $0.predicate,
                result: caseResult(
                    for: $0.predicate,
                    observation: observation,
                    changeBaselineSequence: changeBaselineSequence
                )
            )
        }
        return PredicateCaseSelection(
            cases: evaluatedCases,
            selectedCaseIndex: evaluatedCases.firstIndex(where: \.result.met)
        )
    }

    private static func caseResult(
        for predicate: AccessibilityPredicate,
        observation: HeistSemanticObservation,
        changeBaselineSequence: UInt64?
    ) -> ExpectationResult {
        if predicate.requiresFutureSettledBaseline,
           let changeBaselineSequence,
           observation.event.sequence <= changeBaselineSequence {
            return ExpectationResult(
                met: false,
                predicate: predicate,
                actual: "change predicate requires future settled observation after baseline"
            )
        }
        return predicate.evaluate(
            currentElements: observation.state.interface.projectedElements,
            delta: observation.delta
        )
    }
}

private extension AccessibilityPredicate {
    var requiresFutureSettledBaseline: Bool {
        if case .changed = self { return true }
        return false
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
