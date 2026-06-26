#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

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
        initialTrace: AccessibilityTrace? = nil,
        after sequence: UInt64? = nil
    ) async -> HeistWaitReceipt {
        do {
            return await wait(
                for: try step.resolve(in: .empty),
                initialTrace: initialTrace,
                after: sequence
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
        initialTrace: AccessibilityTrace? = nil,
        after sequence: UInt64? = nil
    ) async -> HeistWaitReceipt {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = Self.clampedWaitTimeout(step.timeout)
        var state = WaitPredicateState(predicate: step.predicate)
        let scope = step.predicate.observationScope

        guard let entry = await observeSemanticState(
            scope: scope,
            after: sequence,
            timeout: sequence == nil ? 0 : timeout
        ) else {
            return waitReceipt(for: step, state: state, start: start, success: false)
        }

        var accumulatedTrace: WaitAccumulatedTrace?
        if step.predicate.requiresChangeBaseline,
           let suppliedBaseline = Self.suppliedChangeBaseline(from: initialTrace, entry: entry.event) {
            state.recordActionChangeBaseline(suppliedBaseline)
            accumulatedTrace = WaitAccumulatedTrace(baseline: suppliedBaseline)
            accumulatedTrace?.append(entry)
            state.record(
                waitEvaluation(for: step.predicate, observation: entry, accumulatedTrace: accumulatedTrace),
                traceOverride: accumulatedTrace?.trace
            )
            if state.lastEvaluation.met || timeout == 0 {
                return waitReceipt(
                    for: step,
                    state: state,
                    start: start,
                    success: state.lastEvaluation.met
                )
            }
        } else if step.predicate.requiresChangeBaseline {
            state.recordChangeBaseline(entry)
            if let baseline = state.changeBaseline {
                accumulatedTrace = WaitAccumulatedTrace(baseline: baseline)
            }
            if timeout == 0 {
                return waitReceipt(
                    for: step,
                    state: state,
                    start: start,
                    success: false
                )
            }
        } else {
            state.record(waitEvaluation(for: step.predicate, observation: entry, accumulatedTrace: nil))
            if state.lastEvaluation.met || timeout == 0 {
                return waitReceipt(
                    for: step,
                    state: state,
                    start: start,
                    success: state.lastEvaluation.met
                )
            }
        }

        guard timeout > 0 else {
            return waitReceipt(for: step, state: state, start: start, success: false)
        }

        let pollResult = await PredicatePollingEngine<ExpectationResult>(
            observeSemanticState: observeSemanticState
        ).poll(
            scope: scope,
            timeout: step.timeout,
            start: start,
            after: state.observedSequence,
            changeBaselineSequence: state.changeBaseline?.sequence,
            requiresChangeBaseline: step.predicate.requiresChangeBaseline,
            pollWhenTimeoutZero: false,
            evaluate: { observation, _ in
                accumulatedTrace?.append(observation)
                return waitEvaluation(
                    for: step.predicate,
                    observation: observation,
                    accumulatedTrace: accumulatedTrace
                ).expectation
            },
            isMatched: { $0.met }
        )

        if let observation = pollResult.lastObservation,
           let expectation = pollResult.lastEvaluation {
            state.record(
                (observation, expectation),
                traceOverride: accumulatedTrace?.trace
            )
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

    private func waitEvaluation(
        for predicate: AccessibilityPredicate,
        observation: HeistSemanticObservation,
        accumulatedTrace: WaitAccumulatedTrace?
    ) -> WaitEvaluation {
        return (
            observation,
            PredicateEvaluation.evaluate(
                predicate,
                currentElements: observation.state.interface.projectedElements,
                accumulatedDelta: accumulatedTrace?.delta
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
        changeBaseline: WaitChangeBaseline? = nil,
        sawObservationAfterBaseline: Bool = false,
        observedSequence: UInt64? = nil
    ) -> HeistWaitReceipt {
        let elapsed = Self.elapsedSeconds(since: start)
        let presenceMessage = success || observationSummary == nil
            ? nil
            : presenceTimeoutMessage(step.predicate, elapsed)
        let latest = latestEvent()
        let settledDiagnostics = success ? nil : SettledWaitDiagnostics(
            baseline: changeBaseline.map(SettledEventSummary.init(baseline:)),
            last: latest.map(SettledEventSummary.init(event:)),
            lastDelta: trace?.accumulatedEndpointDelta ?? trace?.endpointDelta ?? latest?.delta,
            settleFailure: latestSettleFailure(),
            sawObservationAfterBaseline: sawObservationAfterBaseline
        )
        return Self.waitReceipt(
            for: step,
            trace: trace,
            observationSummary: observationSummary,
            expectation: expectation,
            elapsed: elapsed,
            success: success,
            presenceTimeoutMessage: presenceMessage,
            settledDiagnostics: settledDiagnostics,
            observedSequence: observedSequence,
            observationSummary: observationSummary
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
            sawObservationAfterBaseline: state.sawObservationAfterBaseline,
            observedSequence: state.observedSequence
        )
    }

    // MARK: - Wait Building

    static func suppliedChangeBaseline(
        from trace: AccessibilityTrace?,
        entry: SettledSemanticObservationEvent
    ) -> WaitChangeBaseline? {
        guard let capture = trace?.captures.first else { return nil }
        return WaitChangeBaseline(
            sequence: suppliedBaselineSequence(for: capture, entry: entry),
            capture: capture
        )
    }

    private static func suppliedBaselineSequence(
        for capture: AccessibilityTrace.Capture,
        entry: SettledSemanticObservationEvent
    ) -> UInt64 {
        if entry.trace.captures.last?.hash == capture.hash {
            return entry.sequence
        }
        if entry.trace.captures.first?.hash == capture.hash,
           let previous = entry.previous {
            return previous.sequence
        }
        if let previous = entry.previous {
            return previous.sequence
        }
        return entry.sequence > 0 ? entry.sequence - 1 : 0
    }

    struct SettledEventSummary {
        let sequence: UInt64
        let hash: String?

        init(event: SettledSemanticObservationEvent) {
            sequence = event.sequence
            hash = event.latestCaptureRef?.hash
        }

        init(baseline: WaitChangeBaseline) {
            sequence = baseline.sequence
            hash = baseline.hash
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
        let sawObservationAfterBaseline: Bool
    }

    nonisolated static func clampedWaitTimeout(_ timeout: Double) -> Double {
        max(immediateTimeout, min(timeout, defaultWaitTimeout))
    }

    static func unresolvedWaitPredicate() -> AccessibilityPredicate {
        AccessibilityPredicate.state(.missing(ElementPredicate(identifier: "__unresolved_heist_predicate__")))
    }

    static func elapsedSeconds(since start: CFAbsoluteTime) -> String {
        String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)
    }

    static func waitReceipt(
        for step: ResolvedWaitStep,
        trace: AccessibilityTrace?,
        observationSummary: String?,
        expectation: ExpectationResult,
        elapsed: String,
        success: Bool,
        presenceTimeoutMessage: String? = nil,
        settledDiagnostics: SettledWaitDiagnostics? = nil,
        observedSequence: UInt64? = nil,
        observationSummary receiptObservationSummary: String? = nil
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
        return HeistWaitReceipt(
            actionResult: actionResult,
            expectation: expectation,
            observedSequence: observedSequence,
            observationSummary: receiptObservationSummary
        )
    }

    static func waitSuccessMessage(
        for predicate: AccessibilityPredicate,
        elapsed: String
    ) -> String {
        switch predicate {
        case .state(.exists):
            return elapsed == "0.0" ? "matched immediately" : "matched after \(elapsed)s"
        case .state(.missing):
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
        if diagnostics.baseline != nil, !diagnostics.sawObservationAfterBaseline {
            parts.append("no settled observation arrived after baseline")
        }
        return parts
    }

    private static func deltaSummary(_ delta: AccessibilityTrace.Delta?) -> String {
        guard let delta else { return "none" }
        switch delta {
        case .noChange:
            return "no_change"
        case .elementsChanged:
            return "elements"
        case .screenChanged:
            return "screen"
        }
    }
}

private typealias WaitEvaluation = (observation: HeistSemanticObservation, expectation: ExpectationResult)

struct WaitChangeBaseline {
    let sequence: UInt64
    let capture: AccessibilityTrace.Capture?

    var hash: String? {
        capture?.hash
    }

    init(sequence: UInt64, capture: AccessibilityTrace.Capture?) {
        self.sequence = sequence
        self.capture = capture
    }

    init(event: SettledSemanticObservationEvent) {
        self.sequence = event.sequence
        self.capture = event.trace.captures.last
    }
}

private struct WaitAccumulatedTrace {
    private var captures: [AccessibilityTrace.Capture]
    private var observedNoChangeAfterBaseline = false

    init?(baseline: WaitChangeBaseline) {
        guard let capture = baseline.capture else { return nil }
        self.captures = [capture]
    }

    var trace: AccessibilityTrace {
        AccessibilityTrace(captures: captures)
    }

    var delta: AccessibilityTrace.AccumulatedDelta? {
        trace.accumulatedDelta ?? noChangeDelta
    }

    mutating func append(_ observation: HeistSemanticObservation) {
        guard let capture = observation.accessibilityTrace.captures.last else { return }
        if let last = captures.last,
           last.hash == capture.hash,
           AccessibilityTrace.Delta.between(last, capture).meaningfulWaitDelta == nil {
            observedNoChangeAfterBaseline = true
            return
        }
        captures.append(capture)
    }

    private var noChangeDelta: AccessibilityTrace.AccumulatedDelta? {
        guard observedNoChangeAfterBaseline, let capture = captures.last else { return nil }
        return AccessibilityTrace.AccumulatedDelta(
            elementCount: capture.interface.projectedElements.count,
            captureEdge: AccessibilityTrace.CaptureEdge(before: capture, after: capture),
            screenChanged: nil,
            elementsChanged: nil,
            transient: []
        )
    }
}

private extension AccessibilityTrace.Delta {
    var meaningfulWaitDelta: AccessibilityTrace.Delta? {
        switch self {
        case .noChange(let payload) where payload.transient.isEmpty:
            return nil
        case .noChange, .elementsChanged, .screenChanged:
            return self
        }
    }
}

struct PredicatePollingResult<Evaluation> {
    let lastObservation: HeistSemanticObservation?
    let lastEvaluation: Evaluation?
    let elapsedMs: Int
}

struct PredicatePollingEngine<Evaluation> {
    typealias ObservationSource = @MainActor (
        SemanticObservationScope,
        UInt64?,
        Double?
    ) async -> HeistSemanticObservation?

    let observeSemanticState: ObservationSource

    @MainActor
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
    var changeBaseline: WaitChangeBaseline?
    var sawObservationAfterBaseline = false
    var lastEvaluation: ExpectationResult

    init(predicate: AccessibilityPredicate) {
        lastEvaluation = ExpectationResult(
            met: false,
            predicate: predicate,
            actual: "no settled semantic observation available"
        )
    }

    mutating func record(_ evaluation: WaitEvaluation, traceOverride: AccessibilityTrace? = nil) {
        lastTrace = traceOverride ?? evaluation.observation.accessibilityTrace
        lastObservationSummary = evaluation.observation.summary
        lastEvaluation = evaluation.expectation
        observedSequence = evaluation.observation.event.sequence
        sawObservationAfterBaseline = changeBaseline
            .map { evaluation.observation.event.sequence > $0.sequence } ?? false
    }

    mutating func recordChangeBaseline(_ observation: HeistSemanticObservation) {
        changeBaseline = WaitChangeBaseline(event: observation.event)
        lastTrace = observation.accessibilityTrace
        lastObservationSummary = observation.summary
        observedSequence = observation.event.sequence
    }

    mutating func recordActionChangeBaseline(_ baseline: WaitChangeBaseline) {
        changeBaseline = baseline
        observedSequence = baseline.sequence
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
