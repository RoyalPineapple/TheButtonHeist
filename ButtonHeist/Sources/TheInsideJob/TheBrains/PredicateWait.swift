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
    typealias LatestSettleFailure = @MainActor () -> String?
    typealias SemanticObserver = @MainActor (SettledSemanticObservationEvent) -> HeistSemanticObservation
    typealias PresenceTimeoutMessage = @MainActor (AccessibilityPredicate, String) -> String?

    let observeEvent: ObserveEvent
    let latestEvent: LatestEvent
    let latestSettleFailure: LatestSettleFailure
    let semanticObservation: SemanticObserver
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
            let predicate = Self.unresolvedWaitPredicate()
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
        let timeout = Self.clampedWaitTimeout(step.timeout)
        var state = WaitPredicateState(predicate: step.predicate)

        if let initialTraceResult = Self.initialTraceResult(
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

        let pollResult = await PredicatePollingEngine<ExpectationResult>(
            observeSemanticState: observeSemanticState
        ).poll(
            scope: step.predicate.observationScope,
            timeout: step.timeout,
            start: start,
            after: state.observedSequence,
            changeBaselineSequence: state.changeBaseline?.sequence,
            requiresChangeBaseline: step.predicate.requiresFutureSettledBaseline,
            pollWhenTimeoutZero: false,
            evaluate: { observation, changeBaselineSequence in
                PredicateEvaluation.evaluate(
                    step.predicate,
                    in: observation,
                    changeBaselineSequence: changeBaselineSequence
                )
            },
            isMatched: { $0.met }
        )

        if let observation = pollResult.lastObservation,
           let expectation = pollResult.lastEvaluation {
            state.record((observation, expectation))
            if expectation.met {
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
        let elapsed = Self.elapsedSeconds(since: start)
        let presenceMessage = success || observationSummary == nil
            ? nil
            : presenceTimeoutMessage(step.predicate, elapsed)
        let latest = latestEvent()
        let settledDiagnostics = success ? nil : SettledWaitDiagnostics(
            baseline: changeBaseline.map(SettledEventSummary.init(event:)),
            last: latest.map(SettledEventSummary.init(event:)),
            lastDelta: trace?.endpointDelta ?? latest?.delta,
            settleFailure: latestSettleFailure(),
            sawFutureObservation: sawFutureObservation
        )
        return Self.waitReceipt(
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

    // MARK: - Wait Building

    struct InitialTraceResult {
        let trace: AccessibilityTrace
        let summary: String?
        let expectation: ExpectationResult
        let shouldReturn: Bool
    }

    struct SettledEventSummary {
        let sequence: UInt64
        let hash: String?

        init(event: SettledSemanticObservationEvent) {
            sequence = event.sequence
            hash = event.latestCaptureRef?.hash
        }

        var description: String {
            if let hash {
                return "sequence \(sequence), hash \(hash)"
            }
            return "sequence \(sequence), hash unavailable"
        }
    }

    struct SettledWaitDiagnostics {
        let baseline: SettledEventSummary?
        let last: SettledEventSummary?
        let lastDelta: AccessibilityTrace.Delta?
        let settleFailure: String?
        let sawFutureObservation: Bool
    }

    nonisolated static func clampedWaitTimeout(_ timeout: Double) -> Double {
        max(0, min(timeout, 30))
    }

    static func unresolvedWaitPredicate() -> AccessibilityPredicate {
        AccessibilityPredicate.state(.absent(ElementPredicate(identifier: "__unresolved_heist_predicate__")))
    }

    static func elapsedSeconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    }

    static func initialTraceResult(
        for step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace?,
        timeout: Double
    ) -> InitialTraceResult? {
        guard let initialTrace else { return nil }
        let expectation = PredicateEvaluation.evaluate(step.predicate, in: initialTrace)
        return InitialTraceResult(
            trace: initialTrace,
            summary: traceSummary(initialTrace),
            expectation: expectation,
            shouldReturn: expectation.met || timeout == 0
        )
    }

    static func traceSummary(_ trace: AccessibilityTrace) -> String? {
        guard let capture = trace.captures.last else { return nil }
        var parts = ["known: \(capture.interface.projectedElements.count) elements"]
        if let screenId = capture.context.screenId {
            parts.insert("screen: \(screenId)", at: 0)
        }
        return parts.joined(separator: "; ")
    }

    static func waitReceipt(
        for step: ResolvedWaitStep,
        trace: AccessibilityTrace?,
        observationSummary: String?,
        expectation: ExpectationResult,
        elapsed: String,
        success: Bool,
        presenceTimeoutMessage: String? = nil,
        settledDiagnostics: SettledWaitDiagnostics? = nil
    ) -> HeistWaitReceipt {
        var builder = ActionResultBuilder(method: .wait)
        builder.accessibilityTrace = trace
        builder.message = success
            ? waitSuccessMessage(for: step.predicate, elapsed: elapsed)
            : waitTimeoutMessage(
                for: step,
                expectation: expectation,
                observationSummary: observationSummary,
                elapsed: elapsed,
                presenceTimeoutMessage: presenceTimeoutMessage,
                settledDiagnostics: settledDiagnostics
            )

        let actionResult = success
            ? builder.success()
            : builder.failure(errorKind: .timeout)
        return HeistWaitReceipt(actionResult: actionResult, expectation: expectation)
    }

    static func waitSuccessMessage(
        for predicate: AccessibilityPredicate,
        elapsed: String
    ) -> String {
        switch predicate {
        case .state(.present):
            return elapsed == "0.0" ? "matched immediately" : "matched after \(elapsed)s"
        case .state(.absent):
            return "absent confirmed after \(elapsed)s"
        default:
            return "predicate met after \(elapsed)s"
        }
    }

    static func waitTimeoutMessage(
        for step: ResolvedWaitStep,
        expectation: ExpectationResult,
        observationSummary: String?,
        elapsed: String,
        presenceTimeoutMessage: String?,
        settledDiagnostics: SettledWaitDiagnostics?
    ) -> String {
        let diagnostics = settledDiagnostics.map(settledDiagnosticsMessage) ?? []
        guard let observationSummary else {
            return ([
                "timed out after \(elapsed)s waiting for heist predicate",
                "expected: \(step.predicate.description)",
                "last result: \(expectation.actual ?? "not met")",
                "last observed: no settled semantic observation available",
            ] + diagnostics).joined(separator: "; ")
        }

        if let presenceTimeoutMessage {
            return ([presenceTimeoutMessage] + diagnostics).joined(separator: "; ")
        }

        return ([
            "timed out after \(elapsed)s waiting for heist predicate",
            "expected: \(step.predicate.description)",
            "last result: \(expectation.actual ?? "not met")",
            "last observed: \(observationSummary)",
        ] + diagnostics).joined(separator: "; ")
    }

    private static func settledDiagnosticsMessage(_ diagnostics: SettledWaitDiagnostics) -> [String] {
        var parts: [String] = []
        if let baseline = diagnostics.baseline {
            parts.append("baseline: \(baseline.description)")
        }
        if let last = diagnostics.last {
            parts.append("last settled: \(last.description)")
        }
        parts.append("last delta: \(deltaSummary(diagnostics.lastDelta))")
        if let settleFailure = diagnostics.settleFailure {
            parts.append(settleFailure)
        }
        if diagnostics.baseline != nil, !diagnostics.sawFutureObservation {
            parts.append("no future settled observation arrived after baseline")
        }
        return parts
    }

    private static func deltaSummary(_ delta: AccessibilityTrace.Delta?) -> String {
        guard let delta else { return "none" }
        switch delta {
        case .noChange:
            return "no_change"
        case .elementsChanged:
            return "elements_changed"
        case .screenChanged:
            return "screen_changed"
        }
    }
}

private typealias WaitEvaluation = (observation: HeistSemanticObservation, expectation: ExpectationResult)

@MainActor
struct PredicatePollingResult<Evaluation> {
    let lastObservation: HeistSemanticObservation?
    let lastEvaluation: Evaluation?
    let elapsedMs: Int
}

@MainActor
struct PredicatePollingEngine<Evaluation> {
    typealias ObservationSource = @MainActor (
        SemanticObservationScope,
        UInt64?,
        Double?
    ) async -> HeistSemanticObservation?

    let observeSemanticState: ObservationSource

    func poll(
        scope: SemanticObservationScope,
        timeout rawTimeout: Double,
        start: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        after initialObservedSequence: UInt64? = nil,
        changeBaselineSequence initialChangeBaselineSequence: UInt64? = nil,
        requiresChangeBaseline: Bool,
        pollWhenTimeoutZero: Bool = true,
        evaluate: (HeistSemanticObservation, UInt64?) -> Evaluation,
        isMatched: (Evaluation) -> Bool
    ) async -> PredicatePollingResult<Evaluation> {
        let timeout = PredicateWait.clampedWaitTimeout(rawTimeout)
        guard timeout > 0 || pollWhenTimeoutZero else {
            return PredicatePollingResult(
                lastObservation: nil,
                lastEvaluation: nil,
                elapsedMs: Self.elapsedMilliseconds(since: start)
            )
        }

        let deadline = start + timeout
        var observedSequence = initialObservedSequence
        var changeBaselineSequence = initialChangeBaselineSequence
        var lastObservation: HeistSemanticObservation?
        var lastEvaluation: Evaluation?

        repeat {
            let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
            guard let observation = await observeSemanticState(
                scope,
                observedSequence,
                min(remaining, SemanticObservationTiming.defaultTimeout)
            ) else {
                if timeout == 0 { break }
                continue
            }

            observedSequence = observation.event.sequence
            lastObservation = observation
            if requiresChangeBaseline, changeBaselineSequence == nil {
                changeBaselineSequence = observation.event.sequence
            }

            let evaluation = evaluate(observation, changeBaselineSequence)
            lastEvaluation = evaluation
            if isMatched(evaluation) {
                return PredicatePollingResult(
                    lastObservation: lastObservation,
                    lastEvaluation: lastEvaluation,
                    elapsedMs: Self.elapsedMilliseconds(since: start)
                )
            }

            if timeout == 0 { break }
        } while CFAbsoluteTimeGetCurrent() < deadline

        return PredicatePollingResult(
            lastObservation: lastObservation,
            lastEvaluation: lastEvaluation,
            elapsedMs: Self.elapsedMilliseconds(since: start)
        )
    }

    private static func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

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
        _ initialTraceResult: PredicateWait.InitialTraceResult,
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
