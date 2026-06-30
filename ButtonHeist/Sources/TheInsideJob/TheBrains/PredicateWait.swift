#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

enum PredicateObservationDiagnostics {
    static let changePredicateNeedsFutureObservationMessage = "change predicate requires future settled observation after baseline"
}

// PredicateWait stores main-actor closures and is constructed/used from main-actor observation code.
@MainActor struct PredicateWait { // swiftlint:disable:this agent_main_actor_value_type
    typealias ObserveEvent = @MainActor (
        SemanticObservationScope,
        SettledObservationSequence?,
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
        after sequence: SettledObservationSequence? = nil,
        allowsTransitionFinalStateWarning: Bool = true
    ) async -> HeistWaitReceipt {
        do {
            return await wait(
                for: try step.resolve(in: .empty),
                initialTrace: initialTrace,
                after: sequence,
                allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning
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
        after sequence: SettledObservationSequence? = nil,
        allowsTransitionFinalStateWarning: Bool = true
    ) async -> HeistWaitReceipt {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = Self.clampedWaitTimeout(step.timeout)
        let scope = SemanticObservationScope.discovery

        let initialEntry = await observeSemanticState(
            scope: scope,
            after: sequence,
            timeout: sequence == nil ? 0 : timeout
        )
        guard let entry = initialEntry else {
            return await waitReceiptWithoutInitialObservation(
                for: step,
                initialTrace: initialTrace,
                start: start,
                shouldPoll: timeout > 0 && sequence == nil,
                observationScope: scope,
                allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning
            )
        }

        var state = PredicateWaitState(predicate: step.predicate)
        var stream = PredicateObservationStreamState()
        let reducer = PredicateWaitReducer(
            step: step,
            timeout: timeout,
            allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning
        )

        let initialDecision = initialDecision(
            for: step,
            entry: entry,
            initialTrace: initialTrace,
            reducer: reducer,
            stream: &stream,
            state: &state,
            timeout: timeout
        )
        if let receipt = terminalReceipt(for: initialDecision, step: step, state: &state, start: start) {
            return receipt
        }

        if let receipt = terminalReceipt(
            for: reducer.decision(state, timedOutWhenUnmatched: false),
            step: step,
            state: &state,
            start: start
        ) {
            return receipt
        }

        guard timeout > 0 else {
            return waitReceipt(for: step, state: state, start: start, success: false)
        }

        if let decision = await pollDecision(
            for: step,
            scope: scope,
            start: start,
            reducer: reducer,
            state: state,
            stream: stream
        ) {
            if let receipt = terminalReceipt(for: decision, step: step, state: &state, start: start) {
                return receipt
            }
        }

        if let receipt = terminalReceipt(
            for: reducer.decision(state),
            step: step,
            state: &state,
            start: start
        ) {
            return receipt
        }

        return waitReceipt(
            for: step,
            state: state,
            start: start,
            success: false
        )
    }

    private func initialDecision(
        for step: ResolvedWaitStep,
        entry: HeistSemanticObservation,
        initialTrace: AccessibilityTrace?,
        reducer: PredicateWaitReducer,
        stream: inout PredicateObservationStreamState,
        state: inout PredicateWaitState,
        timeout: Double
    ) -> PredicateWaitDecision {
        if step.predicate.requiresChangeBaseline,
           let suppliedBaseline = Self.suppliedChangeBaseline(from: initialTrace, entry: entry.event) {
            return observedInitialDecision(
                for: step,
                entry: entry,
                reducer: reducer,
                stream: &stream,
                state: state,
                baselineSeed: .supplied(suppliedBaseline),
                timedOutWhenUnmatched: timeout == 0
            )
        }

        if step.predicate.requiresChangeBaseline {
            let reduced = stream.reducing(
                entry,
                predicate: step.predicate,
                baselineSeed: .currentObservation
            )
            stream = reduced.state
            state = reducer.reduce(
                state,
                event: .baseline(PredicateWaitObservation(reduced.reduction))
            )
            return timeout == 0 ? reducer.decision(state) : .poll(state)
        }

        return observedInitialDecision(
            for: step,
            entry: entry,
            reducer: reducer,
            stream: &stream,
            state: state,
            baselineSeed: .preserve,
            timedOutWhenUnmatched: timeout == 0
        )
    }

    private func observedInitialDecision(
        for step: ResolvedWaitStep,
        entry: HeistSemanticObservation,
        reducer: PredicateWaitReducer,
        stream: inout PredicateObservationStreamState,
        state: PredicateWaitState,
        baselineSeed: PredicateObservationBaselineSeed,
        timedOutWhenUnmatched: Bool
    ) -> PredicateWaitDecision {
        let reduced = stream.reducing(
            entry,
            predicate: step.predicate,
            baselineSeed: baselineSeed
        )
        stream = reduced.state
        return reducer.decision(
            after: .observation(PredicateWaitObservation(reduced.reduction)),
            reducing: state,
            timedOutWhenUnmatched: timedOutWhenUnmatched
        )
    }

    private func pollDecision(
        for step: ResolvedWaitStep,
        scope: SemanticObservationScope,
        start: CFAbsoluteTime,
        reducer: PredicateWaitReducer,
        state: PredicateWaitState,
        stream initialStream: PredicateObservationStreamState
    ) async -> PredicateWaitDecision? {
        var stream = initialStream
        let pollResult = await PredicatePollingEngine<PredicateWaitDecision>(
            observeSemanticState: observeSemanticState
        ).poll(
            scope: scope,
            timeout: step.timeout,
            start: start,
            after: state.observedSequence,
            changeBaselineSequence: state.changeBaseline?.sequence,
            requiresChangeBaseline: step.predicate.requiresChangeBaseline,
            pollWhenTimeoutZero: false,
            initialVisibleFingerprint: state.lastVisibleFingerprint,
            discoveryBootstrap: .ifNoObservation,
            evaluate: { observation, _ in
                let reduced = stream.reducing(observation, predicate: step.predicate)
                stream = reduced.state
                return reducer.decision(
                    after: .observation(PredicateWaitObservation(reduced.reduction)),
                    reducing: state,
                    timedOutWhenUnmatched: false
                )
            },
            isMatched: \.isSatisfied
        )
        return pollResult.lastEvaluation
    }

    private func observeSemanticState(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> HeistSemanticObservation? {
        guard let event = await observeEvent(
            scope,
            sequence,
            timeout ?? SemanticObservationTiming.defaultTimeout
        ) else { return nil }
        return semanticObservation(event)
    }

    private func waitReceiptWithoutInitialObservation(
        for step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace?,
        start: CFAbsoluteTime,
        shouldPoll: Bool,
        observationScope: SemanticObservationScope,
        allowsTransitionFinalStateWarning: Bool
    ) async -> HeistWaitReceipt {
        var state = PredicateWaitState(predicate: step.predicate)
        var stream = PredicateObservationStreamState()
        let timeout = Self.clampedWaitTimeout(step.timeout)
        let reducer = PredicateWaitReducer(
            step: step,
            timeout: timeout,
            allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning
        )

        if shouldPoll {
            let pollResult = await PredicatePollingEngine<PredicateWaitDecision>(
                observeSemanticState: observeSemanticState
            ).poll(
                scope: observationScope,
                timeout: step.timeout,
                start: start,
                after: nil,
                changeBaselineSequence: nil,
                requiresChangeBaseline: step.predicate.requiresChangeBaseline,
                pollWhenTimeoutZero: false,
                discoveryBootstrap: .afterInitialDiscoveryAttempt,
                evaluate: { observation, _ in
                    let baselineSeed: PredicateObservationBaselineSeed =
                        step.predicate.requiresChangeBaseline && stream.changeBaseline == nil
                            ? .previousObservationIfAvailable
                            : .preserve
                    let reduced = stream.reducing(
                        observation,
                        predicate: step.predicate,
                        baselineSeed: baselineSeed
                    )
                    stream = reduced.state
                    return reducer.decision(
                        after: .observation(PredicateWaitObservation(reduced.reduction)),
                        reducing: state,
                        timedOutWhenUnmatched: false
                    )
                },
                isMatched: \.isSatisfied
            )

            if let decision = pollResult.lastEvaluation {
                if let receipt = terminalReceipt(for: decision, step: step, state: &state, start: start) {
                    return receipt
                }
            }
        }

        if let receipt = terminalReceipt(
            for: reducer.decision(state, timedOutWhenUnmatched: false),
            step: step,
            state: &state,
            start: start
        ) {
            return receipt
        }

        if let traceEvaluation = initialTraceChangeEvaluation(
            for: step.predicate,
            initialTrace: initialTrace
        ) {
            return waitReceipt(
                for: step,
                trace: initialTrace,
                observationSummary: nil,
                expectation: traceEvaluation,
                start: start,
                success: traceEvaluation.met
            )
        }
        return waitReceipt(for: step, state: state, start: start, success: false)
    }

    private func terminalReceipt(
        for decision: PredicateWaitDecision,
        step: ResolvedWaitStep,
        state: inout PredicateWaitState,
        start: CFAbsoluteTime
    ) -> HeistWaitReceipt? {
        state = decision.state
        switch decision {
        case .satisfied(_, let warning):
            return waitReceipt(for: step, state: state, start: start, success: true, warning: warning)
        case .failed:
            return waitReceipt(for: step, state: state, start: start, success: false)
        case .poll:
            return nil
        }
    }

    private func initialTraceChangeEvaluation(
        for predicate: AccessibilityPredicate,
        initialTrace: AccessibilityTrace?
    ) -> ExpectationResult? {
        guard predicate.requiresChangeBaseline,
              let initialTrace,
              let lastCapture = initialTrace.captures.last
        else { return nil }
        return PredicateEvaluation.evaluate(
            predicate,
            currentElements: lastCapture.interface.projectedElements,
            accumulatedDelta: initialTrace.accumulatedDelta
        )
    }

    private func waitReceipt(
        for step: ResolvedWaitStep,
        trace: AccessibilityTrace? = nil,
        observationSummary: String? = nil,
        expectation: ExpectationResult,
        start: CFAbsoluteTime,
        success: Bool,
        warning: HeistPredicateWarning? = nil,
        changeBaseline: WaitChangeBaseline? = nil,
        sawObservationAfterBaseline: Bool = false,
        observedSequence: SettledObservationSequence? = nil
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
            warning: warning,
            presenceTimeoutMessage: presenceMessage,
            settledDiagnostics: settledDiagnostics,
            observedSequence: observedSequence
        )
    }

    private func waitReceipt(
        for step: ResolvedWaitStep,
        state: PredicateWaitState,
        start: CFAbsoluteTime,
        success: Bool,
        warning: HeistPredicateWarning? = nil
    ) -> HeistWaitReceipt {
        let expectation = warning.map {
            ExpectationResult(met: true, predicate: step.predicate, actual: $0.message)
        } ?? state.lastEvaluation
        return waitReceipt(
            for: step,
            trace: state.lastTrace,
            observationSummary: state.lastObservationSummary,
            expectation: expectation,
            start: start,
            success: success,
            warning: warning,
            changeBaseline: state.changeBaseline,
            sawObservationAfterBaseline: state.sawObservationAfterBaseline,
            observedSequence: state.observedSequence
        )
    }

    // MARK: - Wait Building

    nonisolated static func suppliedChangeBaseline(
        from trace: AccessibilityTrace?,
        entry: SettledSemanticObservationEvent
    ) -> WaitChangeBaseline? {
        guard let capture = trace?.captures.first else { return nil }
        return WaitChangeBaseline(
            sequence: suppliedBaselineSequence(for: capture, entry: entry),
            capture: capture
        )
    }

    private nonisolated static func suppliedBaselineSequence(
        for capture: AccessibilityTrace.Capture,
        entry: SettledSemanticObservationEvent
    ) -> SettledObservationSequence {
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
        let sequence: SettledObservationSequence
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
}

extension WaitChangeBaseline {
    init(event: SettledSemanticObservationEvent) {
        self.init(sequence: event.sequence, capture: event.trace.captures.last)
    }

    init?(previousOf event: SettledSemanticObservationEvent) {
        guard let previous = event.previous,
              previous.sequence < event.sequence,
              let capture = event.trace.captures.first
        else { return nil }
        self.init(sequence: previous.sequence, capture: capture)
    }
}

extension PredicateWait {
    nonisolated static func clampedWaitTimeout(_ timeout: Double) -> Double {
        max(immediateTimeout, min(timeout, defaultWaitTimeout))
    }

    static func unresolvedWaitPredicate() -> AccessibilityPredicate {
        AccessibilityPredicate.state(.missing(ElementPredicate(identifier: "__unresolved_heist_predicate__")))
    }

    static let changePredicateNeedsFutureObservationMessage = PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage

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
        warning: HeistPredicateWarning? = nil,
        presenceTimeoutMessage: String? = nil,
        settledDiagnostics: SettledWaitDiagnostics? = nil,
        observedSequence: SettledObservationSequence? = nil
    ) -> HeistWaitReceipt {
        let message = warning?.message ?? (success
            ? waitSuccessMessage(for: step.predicate, elapsed: elapsed)
            : waitTimeoutMessage(
                for: step,
                expectation: expectation,
                observationSummary: observationSummary,
                elapsed: elapsed,
                presenceTimeoutMessage: presenceTimeoutMessage,
                settledDiagnostics: settledDiagnostics
            ))
        return HeistWaitReceipt(
            waitOutcome: HeistWaitOutcome(
                status: success ? .matched : .timedOut,
                message: message,
                accessibilityTrace: trace,
                expectation: expectation,
                observedSequence: observedSequence,
                observationSummary: observationSummary,
                warning: warning
            )
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
            interactionDigest: AccessibilityTrace.InteractionDigest(
                elementCountBefore: capture.interface.projectedElements.count,
                elementCountAfter: capture.interface.projectedElements.count,
                elementSetChanged: false,
                screenIdBefore: capture.context.screenId ?? InterfaceSummary.screenId(for: capture.interface),
                screenIdAfter: capture.context.screenId ?? InterfaceSummary.screenId(for: capture.interface),
                firstResponderChanged: false
            ),
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

enum PredicateObservationBaselineSeed {
    case preserve
    case supplied(WaitChangeBaseline)
    case currentObservation
    case previousObservationIfAvailable
}

/// Reduces a settled observation stream into current-state match evidence and
/// baseline-to-current transition evidence without reading mutable runtime state.
struct PredicateObservationStreamState {
    let latestReduction: PredicateObservationReduction?
    private let changeState: PredicateChangeObservationState

    init() {
        self.init(changeState: .awaitingBaseline, latestReduction: nil)
    }

    private init(
        changeState: PredicateChangeObservationState,
        latestReduction: PredicateObservationReduction?
    ) {
        self.changeState = changeState
        self.latestReduction = latestReduction
    }

    var changeBaseline: WaitChangeBaseline? {
        changeState.baseline
    }

    func reducing(
        _ observation: HeistSemanticObservation,
        predicate: AccessibilityPredicate,
        baselineSeed: PredicateObservationBaselineSeed = .preserve
    ) -> PredicateObservationStreamReduction {
        var changeState = changeState
        let shouldAppendToChangeWindow = changeState.prepareForObservation(
            observation,
            baselineSeed: baselineSeed
        )

        if shouldAppendToChangeWindow {
            changeState.append(observation)
        }

        let evidence = PredicateObservationEvidence(
            snapshot: PredicateObservationSnapshot(observation),
            transition: changeState.transition(observedSequence: observation.event.sequence)
        )
        let reduction = PredicateObservationReduction(
            evidence: evidence,
            expectation: PredicateEvaluation.evaluate(predicate, in: evidence)
        )
        return PredicateObservationStreamReduction(
            state: PredicateObservationStreamState(
                changeState: changeState,
                latestReduction: reduction
            ),
            reduction: reduction
        )
    }
}

private enum PredicateChangeObservationState {
    case awaitingBaseline
    case observing(PredicateChangeObservationCursor)

    var baseline: WaitChangeBaseline? {
        guard case .observing(let cursor) = self else { return nil }
        return cursor.baseline
    }

    mutating func prepareForObservation(
        _ observation: HeistSemanticObservation,
        baselineSeed: PredicateObservationBaselineSeed
    ) -> Bool {
        switch self {
        case .observing:
            return true
        case .awaitingBaseline:
            switch baselineSeed {
            case .preserve:
                return false
            case .supplied(let suppliedBaseline):
                self = .observing(PredicateChangeObservationCursor(baseline: suppliedBaseline))
                return true
            case .currentObservation:
                self = .observing(PredicateChangeObservationCursor(
                    baseline: WaitChangeBaseline(event: observation.event)
                ))
                return false
            case .previousObservationIfAvailable:
                let inferredBaseline = WaitChangeBaseline(previousOf: observation.event)
                    ?? WaitChangeBaseline(event: observation.event)
                self = .observing(PredicateChangeObservationCursor(baseline: inferredBaseline))
                return true
            }
        }
    }

    mutating func append(_ observation: HeistSemanticObservation) {
        guard case .observing(var cursor) = self else { return }
        cursor.append(observation)
        self = .observing(cursor)
    }

    func transition(observedSequence: SettledObservationSequence) -> PredicateTransitionEvidence? {
        guard case .observing(let cursor) = self else { return nil }
        return PredicateTransitionEvidence(
            baseline: cursor.baseline,
            observedSequence: observedSequence,
            accumulatedTrace: cursor.accumulatedTrace
        )
    }
}

private struct PredicateChangeObservationCursor {
    let baseline: WaitChangeBaseline
    private(set) var accumulatedTrace: WaitAccumulatedTrace?

    init(baseline: WaitChangeBaseline) {
        self.baseline = baseline
        self.accumulatedTrace = WaitAccumulatedTrace(baseline: baseline)
    }

    mutating func append(_ observation: HeistSemanticObservation) {
        accumulatedTrace?.append(observation)
    }
}

struct PredicateObservationStreamReduction {
    let state: PredicateObservationStreamState
    let reduction: PredicateObservationReduction
}

struct PredicateObservationReduction {
    let evidence: PredicateObservationEvidence
    let expectation: ExpectationResult

    var observation: HeistSemanticObservation {
        evidence.observation
    }

    var trace: AccessibilityTrace? {
        evidence.trace
    }

    var changeBaseline: WaitChangeBaseline? {
        evidence.changeBaseline
    }

    var sawObservationAfterBaseline: Bool {
        evidence.sawObservationAfterBaseline
    }
}

extension PredicateWaitObservation {
    init(_ reduction: PredicateObservationReduction) {
        self.init(
            trace: reduction.trace ?? reduction.observation.accessibilityTrace,
            summary: reduction.observation.summary,
            visibleFingerprint: .known(reduction.observation.visibleFingerprint),
            sequence: reduction.observation.event.sequence,
            changeBaseline: reduction.changeBaseline,
            sawObservationAfterBaseline: reduction.sawObservationAfterBaseline,
            expectation: reduction.expectation
        )
    }
}

struct PredicateObservationEvidence {
    private let snapshot: PredicateObservationSnapshot
    private let stateMatches: ElementMatchSet
    private let transition: PredicateTransitionEvidence?

    fileprivate init(
        snapshot: PredicateObservationSnapshot,
        transition: PredicateTransitionEvidence?
    ) {
        self.snapshot = snapshot
        self.stateMatches = ElementMatchSet(interface: snapshot.interface)
        self.transition = transition
    }

    var observation: HeistSemanticObservation {
        snapshot.observation
    }

    var trace: AccessibilityTrace? {
        transition?.trace ?? snapshot.trace
    }

    var changeBaseline: WaitChangeBaseline? {
        transition?.baseline
    }

    var sawObservationAfterBaseline: Bool {
        transition?.sawObservationAfterBaseline ?? false
    }

    func evaluate(_ predicate: AccessibilityPredicate) -> ExpectationResult {
        switch predicate {
        case .state(let state):
            return state.evaluate(in: stateMatches).expectation(for: predicate)
        case .changePredicate, .noChangePredicate:
            guard let transition else {
                return ExpectationResult(met: false, predicate: predicate, actual: "noTrace")
            }
            guard transition.sawObservationAfterBaseline else {
                return ExpectationResult(
                    met: false,
                    predicate: predicate,
                    actual: PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
                )
            }
            return PredicateChangeMatchSet(
                currentElements: stateMatches.elements,
                transition: transition
            ).evaluate(predicate)
        }
    }
}

private struct PredicateObservationSnapshot {
    let observation: HeistSemanticObservation
    let sequence: SettledObservationSequence
    let interface: Interface
    let trace: AccessibilityTrace
    let summary: String

    init(_ observation: HeistSemanticObservation) {
        self.observation = observation
        self.sequence = observation.event.sequence
        self.interface = observation.state.interface
        self.trace = observation.accessibilityTrace
        self.summary = observation.summary
    }
}

private struct PredicateChangeMatchSet {
    let currentElements: [HeistElement]
    let transition: PredicateTransitionEvidence

    func evaluate(_ predicate: AccessibilityPredicate) -> ExpectationResult {
        predicate.evaluate(
            currentElements: currentElements,
            accumulatedDelta: transition.accumulatedDelta
        )
    }
}

private struct PredicateTransitionEvidence {
    let baseline: WaitChangeBaseline
    let observedSequence: SettledObservationSequence
    private let accumulatedTrace: WaitAccumulatedTrace?

    init(
        baseline: WaitChangeBaseline,
        observedSequence: SettledObservationSequence,
        accumulatedTrace: WaitAccumulatedTrace?
    ) {
        self.baseline = baseline
        self.observedSequence = observedSequence
        self.accumulatedTrace = accumulatedTrace
    }

    var trace: AccessibilityTrace? {
        accumulatedTrace?.trace
    }

    var accumulatedDelta: AccessibilityTrace.AccumulatedDelta? {
        accumulatedTrace?.delta
    }

    var sawObservationAfterBaseline: Bool {
        observedSequence > baseline.sequence
    }
}

struct PredicatePollingResult<Evaluation> {
    let lastObservation: HeistSemanticObservation?
    let lastEvaluation: Evaluation?
    let elapsedMs: Int
}

private struct PredicatePollingCursor<Evaluation> {
    var observedSequence: SettledObservationSequence?
    var changeBaseline: PredicatePollingChangeBaseline
    var lastObservation: HeistSemanticObservation?
    var lastEvaluation: Evaluation?

    init(
        observedSequence: SettledObservationSequence?,
        changeBaselineSequence: SettledObservationSequence?,
        requiresChangeBaseline: Bool
    ) {
        self.observedSequence = observedSequence
        self.changeBaseline = PredicatePollingChangeBaseline(
            requiresChangeBaseline: requiresChangeBaseline,
            initialSequence: changeBaselineSequence
        )
    }
}

private enum PredicatePollingChangeBaseline {
    case notRequired
    case awaitingFirstObservation
    case observingSince(SettledObservationSequence)

    init(requiresChangeBaseline: Bool, initialSequence: SettledObservationSequence?) {
        guard requiresChangeBaseline else {
            self = .notRequired
            return
        }
        if let initialSequence {
            self = .observingSince(initialSequence)
        } else {
            self = .awaitingFirstObservation
        }
    }

    var sequence: SettledObservationSequence? {
        guard case .observingSince(let sequence) = self else { return nil }
        return sequence
    }

    mutating func recordObservation(_ observation: HeistSemanticObservation) {
        guard case .awaitingFirstObservation = self else { return }
        self = .observingSince(observation.event.previous?.sequence ?? observation.event.sequence)
    }
}

struct PredicatePollingEngine<Evaluation> {
    typealias ObservationSource = @MainActor (
        SemanticObservationScope,
        SettledObservationSequence?,
        Double?
    ) async -> HeistSemanticObservation?

    let observeSemanticState: ObservationSource

    @MainActor
    func poll(
        scope: SemanticObservationScope,
        timeout rawTimeout: Double,
        start: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(),
        after initialObservedSequence: SettledObservationSequence? = nil,
        changeBaselineSequence initialChangeBaselineSequence: SettledObservationSequence? = nil,
        requiresChangeBaseline: Bool,
        pollWhenTimeoutZero: Bool = true,
        initialVisibleFingerprint: PredicateVisibleFingerprint = .unknown,
        discoveryBootstrap: PredicateDiscoveryBootstrap = .ifNoObservation,
        evaluate: (HeistSemanticObservation, SettledObservationSequence?) -> Evaluation,
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
        var cursor = PredicatePollingCursor<Evaluation>(
            observedSequence: initialObservedSequence,
            changeBaselineSequence: initialChangeBaselineSequence,
            requiresChangeBaseline: requiresChangeBaseline
        )
        var waitMachine = PredicatePollingState(
            initialVisibleFingerprint: initialVisibleFingerprint,
            scope: scope,
            needsInitialProbe: discoveryBootstrap.needsInitialProbe(
                initialObservedSequence: initialObservedSequence
            )
        )

        repeat {
            let tickStart = CFAbsoluteTimeGetCurrent()
            let discoveryProbeAlreadyDue = waitMachine.nextProbe == .discovery
            let visiblePoll = await pollVisibleTick(
                deadline: deadline,
                allowSettledWait: timeout > 0 && !discoveryProbeAlreadyDue,
                cursor: &cursor,
                evaluate: evaluate,
                isMatched: isMatched
            )

            switch visiblePoll {
            case .observed(let visibleEvaluation):
                waitMachine.recordVisibleTick(
                    .observed(
                        fingerprint: PredicateVisibleFingerprint(cursor.lastObservation?.visibleFingerprint),
                        matched: isMatched(visibleEvaluation)
                    )
                )
                if isMatched(visibleEvaluation) {
                    return PredicatePollingResult(
                        lastObservation: cursor.lastObservation,
                        lastEvaluation: cursor.lastEvaluation,
                        elapsedMs: Self.elapsedMilliseconds(since: start)
                    )
                }
            case .unavailable:
                waitMachine.recordVisibleTick(.unavailable)
            }

            if waitMachine.nextProbe == .discovery {
                let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
                let discoveryEvaluation = await pollObservation(
                    scope: .discovery,
                    timeout: min(remaining, SemanticObservationTiming.defaultTimeout),
                    cursor: &cursor,
                    evaluate: evaluate
                )

                if let discoveryEvaluation {
                    waitMachine.recordDiscoveryProbe()
                    if isMatched(discoveryEvaluation) {
                        return PredicatePollingResult(
                            lastObservation: cursor.lastObservation,
                            lastEvaluation: cursor.lastEvaluation,
                            elapsedMs: Self.elapsedMilliseconds(since: start)
                        )
                    }
                } else if timeout == 0 {
                    break
                }
            }

            if timeout == 0 { break }
            guard await Self.sleepUntilNextVisibleTick(startedAt: tickStart, deadline: deadline) else { break }
        } while CFAbsoluteTimeGetCurrent() < deadline

        return PredicatePollingResult(
            lastObservation: cursor.lastObservation,
            lastEvaluation: cursor.lastEvaluation,
            elapsedMs: Self.elapsedMilliseconds(since: start)
        )
    }

    @MainActor
    private func pollVisibleTick(
        deadline: CFAbsoluteTime,
        allowSettledWait: Bool,
        cursor: inout PredicatePollingCursor<Evaluation>,
        evaluate: (HeistSemanticObservation, SettledObservationSequence?) -> Evaluation,
        isMatched: (Evaluation) -> Bool
    ) async -> PredicateVisiblePoll<Evaluation> {
        var immediateEvaluation: Evaluation?
        if let evaluation = await pollObservation(
            scope: .visible,
            timeout: 0,
            cursor: &cursor,
            evaluate: evaluate
        ) {
            if isMatched(evaluation) {
                return .observed(evaluation)
            }
            immediateEvaluation = evaluation
        }

        guard allowSettledWait else {
            return immediateEvaluation.map(PredicateVisiblePoll.observed) ?? .unavailable
        }

        let remaining = max(0, deadline - CFAbsoluteTimeGetCurrent())
        guard remaining > 0 else {
            return immediateEvaluation.map(PredicateVisiblePoll.observed) ?? .unavailable
        }

        let evaluation = await pollObservation(
            scope: .visible,
            timeout: min(remaining, PredicatePollingCadence.visibleTickIntervalSeconds),
            cursor: &cursor,
            evaluate: evaluate
        )
        return (evaluation ?? immediateEvaluation).map(PredicateVisiblePoll.observed) ?? .unavailable
    }

    @MainActor
    private func pollObservation(
        scope: SemanticObservationScope,
        timeout: Double?,
        cursor: inout PredicatePollingCursor<Evaluation>,
        evaluate: (HeistSemanticObservation, SettledObservationSequence?) -> Evaluation
    ) async -> Evaluation? {
        guard let observation = await observeSemanticState(
            scope,
            cursor.observedSequence,
            timeout
        ) else {
            return nil
        }

        cursor.observedSequence = observation.event.sequence
        cursor.lastObservation = observation
        cursor.changeBaseline.recordObservation(observation)

        let evaluation = evaluate(observation, cursor.changeBaseline.sequence)
        cursor.lastEvaluation = evaluation
        return evaluation
    }

    private static func sleepUntilNextVisibleTick(
        startedAt tickStart: CFAbsoluteTime,
        deadline: CFAbsoluteTime
    ) async -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        let remaining = deadline - now
        guard remaining > 0 else { return false }
        let tickElapsed = now - tickStart
        let sleepSeconds = min(
            remaining,
            max(0, PredicatePollingCadence.visibleTickIntervalSeconds - tickElapsed)
        )
        guard sleepSeconds > 0 else { return true }
        let nanoseconds = UInt64((sleepSeconds * 1_000_000_000).rounded(.up))
        return await Task.cancellableSleep(for: .nanoseconds(nanoseconds))
    }

    private static func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

enum PredicateVisiblePoll<Evaluation> {
    case unavailable
    case observed(Evaluation)
}

enum PredicatePollingCadence {
    static let visibleTickIntervalSeconds: Double = 0.1
    static let discoveryProbeIntervalVisibleTicks = 5
}

enum PredicateDiscoveryBootstrap {
    case ifNoObservation
    case afterInitialDiscoveryAttempt

    func needsInitialProbe(
        initialObservedSequence: SettledObservationSequence?
    ) -> Bool {
        switch self {
        case .ifNoObservation:
            return initialObservedSequence == nil
        case .afterInitialDiscoveryAttempt:
            return false
        }
    }
}

enum PredicateNextProbe: Equatable {
    case visible
    case discovery
}

enum PredicateVisibleTick {
    case unavailable
    case observed(fingerprint: PredicateVisibleFingerprint, matched: Bool)
}

enum PredicatePollingState {
    case visibleOnly
    case discovery(PredicateDiscoveryPollingState)

    init(
        initialVisibleFingerprint: PredicateVisibleFingerprint,
        scope: SemanticObservationScope,
        needsInitialProbe: Bool
    ) {
        switch scope {
        case .visible:
            self = .visibleOnly
        case .discovery:
            self = .discovery(needsInitialProbe
                ? .probeDue(fingerprint: initialVisibleFingerprint, visibleTicksSinceProbe: 0)
                : .coolingDown(fingerprint: initialVisibleFingerprint, visibleTicksSinceProbe: 0))
        }
    }

    var nextProbe: PredicateNextProbe {
        switch self {
        case .visibleOnly:
            return .visible
        case .discovery(let discovery):
            return discovery.nextProbe
        }
    }

    mutating func recordVisibleTick(_ tick: PredicateVisibleTick) {
        switch self {
        case .visibleOnly:
            return
        case .discovery(let discovery):
            self = .discovery(discovery.afterVisibleTick(tick))
        }
    }

    mutating func recordDiscoveryProbe() {
        switch self {
        case .visibleOnly:
            return
        case .discovery(let discovery):
            self = .discovery(discovery.afterDiscoveryProbe())
        }
    }
}

enum PredicateDiscoveryPollingState {
    case probeDue(fingerprint: PredicateVisibleFingerprint, visibleTicksSinceProbe: Int)
    case coolingDown(fingerprint: PredicateVisibleFingerprint, visibleTicksSinceProbe: Int)

    var nextProbe: PredicateNextProbe {
        switch self {
        case .probeDue:
            return .discovery
        case .coolingDown:
            return .visible
        }
    }

    func afterVisibleTick(_ tick: PredicateVisibleTick) -> PredicateDiscoveryPollingState {
        switch tick {
        case .unavailable:
            return afterVisibleUnavailable()
        case .observed(let nextFingerprint, let matched):
            return afterVisibleObserved(nextFingerprint: nextFingerprint, matched: matched)
        }
    }

    func afterDiscoveryProbe() -> PredicateDiscoveryPollingState {
        switch self {
        case .probeDue(let fingerprint, _),
             .coolingDown(let fingerprint, _):
            return .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: 0)
        }
    }

    private func afterVisibleUnavailable() -> PredicateDiscoveryPollingState {
        switch self {
        case .probeDue(let fingerprint, let ticks):
            return .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: ticks + 1)
        case .coolingDown(let fingerprint, let ticks):
            let nextTicks = ticks + 1
            return nextTicks >= PredicatePollingCadence.discoveryProbeIntervalVisibleTicks
                ? .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
                : .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
        }
    }

    private func afterVisibleObserved(
        nextFingerprint observedFingerprint: PredicateVisibleFingerprint,
        matched: Bool
    ) -> PredicateDiscoveryPollingState {
        switch self {
        case .probeDue(let previousFingerprint, let ticks):
            let fingerprint = observedFingerprint.replacingUnknown(with: previousFingerprint)
            return matched
                ? .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: 0)
                : .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: ticks + 1)

        case .coolingDown(let previousFingerprint, let ticks):
            let fingerprint = observedFingerprint.replacingUnknown(with: previousFingerprint)
            guard !matched else {
                return .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: 0)
            }
            let nextTicks = ticks + 1
            if observedFingerprint != previousFingerprint,
               case .known = observedFingerprint {
                return .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
            }
            return nextTicks >= PredicatePollingCadence.discoveryProbeIntervalVisibleTicks
                ? .probeDue(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
                : .coolingDown(fingerprint: fingerprint, visibleTicksSinceProbe: nextTicks)
        }
    }
}

private extension HeistSemanticObservation {
    var visibleFingerprint: String {
        state.screen.visibleOnly.semanticHash
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
