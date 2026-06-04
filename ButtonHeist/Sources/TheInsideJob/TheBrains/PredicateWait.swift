#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

// PredicateWait stores main-actor closures and is constructed/used from main-actor observation code.
@MainActor struct PredicateWait { // swiftlint:disable:this agent_main_actor_value_type
    typealias ObserveEvent = @MainActor (
        SemanticObservationScope,
        UInt64?,
        Double?
    ) async -> SettledSemanticObservationEvent?
    typealias LatestEvent = @MainActor () -> SettledSemanticObservationEvent?
    typealias SemanticProjection = @MainActor (SettledSemanticObservationEvent) -> HeistSemanticObservation
    typealias PresenceTimeoutMessage = @MainActor (AccessibilityPredicate, String) -> String?

    let observeEvent: ObserveEvent
    let latestEvent: LatestEvent
    let semanticObservation: SemanticProjection
    let presenceTimeoutMessage: PresenceTimeoutMessage

    func wait(
        for step: WaitStep,
        initialTrace: AccessibilityTrace? = nil
    ) async -> HeistWaitReceipt {
        do {
            return await wait(
                for: try step.resolve(in: .empty),
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

    func wait(
        for step: ResolvedWaitStep,
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
                latestSequence: latestEvent()?.sequence
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
            guard let baseline = await acquireChangedPredicateBaseline(
                scope: step.predicate.observationScope,
                timeout: min(timeout, SemanticObservationTiming.defaultTimeout)
            ) else {
                return waitReceipt(
                    for: step,
                    state: state,
                    start: start,
                    success: false
                )
            }
            state.recordChangeBaseline(semanticObservation(baseline))
        } else if let initial = await nextWaitEvaluation(
            forCurrentPredicate: step,
            after: state.observedSequence,
            waitTimeout: timeout,
            changeBaselineSequence: state.changeBaseline?.sequence
        ) {
            state.record(initial)
            if state.lastEvaluation.met || timeout == 0 {
                return waitReceipt(
                    for: step,
                    state: state,
                    start: start,
                    success: state.lastEvaluation.met
                )
            }
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
                timeout: min(remaining, SemanticObservationTiming.defaultTimeout),
                changeBaselineSequence: state.changeBaseline?.sequence
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

    private func observeSemanticState(
        scope: SemanticObservationScope,
        after sequence: UInt64?,
        timeout: Double?
    ) async -> HeistSemanticObservation? {
        guard let event = await observeEvent(
            scope,
            sequence,
            timeout ?? SemanticObservationTiming.defaultTimeout
        ) else { return nil }
        return semanticObservation(event)
    }

    private func acquireChangedPredicateBaseline(
        scope: SemanticObservationScope,
        timeout: Double
    ) async -> SettledSemanticObservationEvent? {
        if let latest = latestEvent() {
            return latest
        }
        return await observeEvent(scope, nil, timeout)
    }

    private func nextWaitEvaluation(
        forCurrentPredicate step: ResolvedWaitStep,
        after sequence: UInt64?,
        waitTimeout: Double,
        changeBaselineSequence: UInt64?
    ) async -> WaitEvaluation? {
        let firstProbe = await nextWaitEvaluation(
            for: step,
            after: sequence,
            timeout: 0,
            changeBaselineSequence: changeBaselineSequence
        )
        guard firstProbe == nil, waitTimeout == 0 else {
            return firstProbe
        }
        return await nextWaitEvaluation(
            for: step,
            after: sequence,
            timeout: 0,
            changeBaselineSequence: changeBaselineSequence
        )
    }

    private func nextWaitEvaluation(
        for step: ResolvedWaitStep,
        after sequence: UInt64?,
        timeout: Double,
        changeBaselineSequence: UInt64?
    ) async -> WaitEvaluation? {
        guard let observation = await observeSemanticState(
            scope: step.predicate.observationScope,
            after: sequence,
            timeout: timeout
        ) else { return nil }
        return (
            observation,
            PredicateEvaluation.evaluate(
                step.predicate,
                in: observation,
                changeBaselineSequence: changeBaselineSequence
            )
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
        let elapsed = InteractionObservationProjection.elapsedSeconds(since: start)
        let presenceMessage = success || observationSummary == nil
            ? nil
            : presenceTimeoutMessage(step.predicate, elapsed)
        let latest = latestEvent()
        let settledDiagnostics = success ? nil : InteractionObservationProjection.SettledWaitDiagnostics(
            baseline: changeBaseline.map(InteractionObservationProjection.SettledEventSummary.init(event:)),
            last: latest.map(InteractionObservationProjection.SettledEventSummary.init(event:)),
            lastDelta: trace?.endpointDeltaProjection ?? latest?.delta,
            sawFutureObservation: sawFutureObservation
        )
        return InteractionObservationProjection.waitReceipt(
            for: step,
            trace: trace,
            observationSummary: observationSummary,
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

    mutating func recordChangeBaseline(_ observation: HeistSemanticObservation) {
        changeBaseline = observation.event
        lastTrace = observation.accessibilityTrace
        lastObservationSummary = observation.summary
        observedSequence = observation.event.sequence
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
