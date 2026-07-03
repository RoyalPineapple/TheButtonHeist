#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport
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
            state: &state,
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
                event: .baseline(PredicateWaitSnapshot(reduced.reduction))
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
            after: .observation(PredicateWaitSnapshot(reduced.reduction)),
            reducing: state,
            timedOutWhenUnmatched: timedOutWhenUnmatched
        )
    }

    private func pollDecision(
        for step: ResolvedWaitStep,
        scope: SemanticObservationScope,
        start: CFAbsoluteTime,
        reducer: PredicateWaitReducer,
        state: inout PredicateWaitState,
        stream initialStream: PredicateObservationStreamState
    ) async -> PredicateWaitDecision? {
        var stream = initialStream
        var waitState = state
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
                let decision = reducer.decision(
                    after: .observation(PredicateWaitSnapshot(reduced.reduction)),
                    reducing: waitState,
                    timedOutWhenUnmatched: false
                )
                waitState = decision.state
                return decision
            },
            isMatched: \.isSatisfied
        )
        state = pollResult.last?.evaluation.state ?? waitState
        return pollResult.last?.evaluation
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
            var waitState = state
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
                    let decision = reducer.decision(
                        after: .observation(PredicateWaitSnapshot(reduced.reduction)),
                        reducing: waitState,
                        timedOutWhenUnmatched: false
                    )
                    waitState = decision.state
                    return decision
                },
                isMatched: \.isSatisfied
            )

            state = pollResult.last?.evaluation.state ?? waitState
            if let decision = pollResult.last?.evaluation {
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
            accumulatedDelta: initialTrace.accumulatedDelta(
                projection: predicate.deltaProjection
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
        warning: HeistPredicateWarning? = nil,
        changeReadiness: PredicateChangeReadiness = .notRequired,
        observedSequence: SettledObservationSequence? = nil
    ) -> HeistWaitReceipt {
        let elapsed = Self.elapsedSeconds(since: start)
        let presenceMessage = success || observationSummary == nil
            ? nil
            : presenceTimeoutMessage(step.predicate, elapsed)
        let latest = latestEvent()
        let settledDiagnostics = success ? nil : SettledWaitDiagnostics(
            changeReadiness: changeReadiness,
            last: latest.map(SettledEventSummary.init(event:)),
            lastDelta: trace?.accumulatedEndpointDelta ?? trace?.endpointDelta ?? latest?.delta,
            settleFailure: latestSettleFailure()
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
        } ?? state.evaluation
        return waitReceipt(
            for: step,
            trace: state.lastTrace,
            observationSummary: state.lastObservationSummary,
            expectation: expectation,
            start: start,
            success: success,
            warning: warning,
            changeReadiness: state.changeReadiness,
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
        let changeReadiness: PredicateChangeReadiness
        let last: SettledEventSummary?
        let lastDelta: AccessibilityTrace.Delta?
        let settleFailure: String?

        var baseline: SettledEventSummary? {
            changeReadiness.baseline.map(SettledEventSummary.init(baseline:))
        }

        var observedChangeAfterBaseline: Bool {
            changeReadiness.observedChangeAfterBaseline
        }
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
            status: success ? .matched : .timedOut,
            message: message,
            accessibilityTrace: trace,
            expectation: expectation,
            observedSequence: observedSequence,
            observationSummary: observationSummary,
            warning: warning
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
        if diagnostics.baseline != nil, !diagnostics.observedChangeAfterBaseline {
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

private enum WaitAccumulatedTrace {
    case unavailable
    case captures(WaitTraceCaptures)
    case noChangeAfterBaseline(WaitNoChangeAfterBaselineEvidence)

    init(baseline: WaitChangeBaseline) {
        if let capture = baseline.capture {
            self = .captures(WaitTraceCaptures(captures: [capture]))
        } else {
            self = .unavailable
        }
    }

    var trace: AccessibilityTrace? {
        switch self {
        case .unavailable:
            return nil
        case .captures(let evidence):
            return evidence.trace
        case .noChangeAfterBaseline(let evidence):
            return evidence.trace
        }
    }

    func delta(projection: AccessibilityTrace.DeltaProjection) -> AccessibilityTrace.AccumulatedDelta? {
        switch self {
        case .unavailable:
            return nil
        case .captures(let evidence):
            return evidence.trace.accumulatedDelta(projection: projection)
        case .noChangeAfterBaseline(let evidence):
            return evidence.delta
        }
    }

    var isAvailable: Bool {
        switch self {
        case .unavailable:
            return false
        case .captures, .noChangeAfterBaseline:
            return true
        }
    }

    mutating func append(_ observation: HeistSemanticObservation, projection: AccessibilityTrace.DeltaProjection) {
        guard let capture = observation.accessibilityTrace.captures.last else { return }
        switch self {
        case .unavailable:
            return
        case .captures(var evidence):
            guard let last = evidence.last else {
                evidence.append(capture)
                self = .captures(evidence)
                return
            }
            if last.hash == capture.hash,
               AccessibilityTrace.Delta.between(
                   last,
                   capture,
                   projection: projection
               ).meaningfulWaitDelta == nil {
                self = .noChangeAfterBaseline(WaitNoChangeAfterBaselineEvidence(capture: last))
            } else {
                evidence.append(capture)
                self = .captures(evidence)
            }
        case .noChangeAfterBaseline(let evidence):
            if evidence.capture.hash == capture.hash,
               AccessibilityTrace.Delta.between(
                   evidence.capture,
                   capture,
                   projection: projection
               ).meaningfulWaitDelta == nil {
                return
            }
            var changedEvidence = WaitTraceCaptures(captures: [evidence.capture])
            changedEvidence.append(capture)
            self = .captures(changedEvidence)
        }
    }
}

private struct WaitTraceCaptures {
    private var captures: [AccessibilityTrace.Capture]

    init(captures: [AccessibilityTrace.Capture]) {
        self.captures = captures
    }

    var last: AccessibilityTrace.Capture? {
        captures.last
    }

    var trace: AccessibilityTrace {
        AccessibilityTrace(captures: captures)
    }

    mutating func append(_ capture: AccessibilityTrace.Capture) {
        captures.append(capture)
    }
}

private struct WaitNoChangeAfterBaselineEvidence {
    let capture: AccessibilityTrace.Capture

    var trace: AccessibilityTrace {
        AccessibilityTrace(captures: [capture, capture])
    }

    var delta: AccessibilityTrace.AccumulatedDelta? {
        trace.accumulatedDelta ?? AccessibilityTrace.AccumulatedDelta(
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
    private let changeState: PredicateChangeObservationState

    init() {
        self.init(changeState: .awaitingBaseline)
    }

    private init(changeState: PredicateChangeObservationState) {
        self.changeState = changeState
    }

    var changeBaseline: WaitChangeBaseline? {
        changeState.baseline
    }

    func reducing(
        _ observation: HeistSemanticObservation,
        predicate: AccessibilityPredicate,
        baselineSeed: PredicateObservationBaselineSeed = .preserve
    ) -> PredicateObservationStreamReduction {
        let projection = predicate.deltaProjection
        let advance = changeState.advancing(
            observation,
            baselineSeed: baselineSeed,
            projection: projection
        )

        let evidence = PredicateObservationEvidence(
            snapshot: PredicateObservationSnapshot(observation),
            changeReadiness: advance.readiness,
            transition: advance.transition
        )
        let reduction = PredicateObservationReduction(
            evidence: evidence,
            expectation: PredicateEvaluation.evaluate(predicate, in: evidence)
        )
        return PredicateObservationStreamReduction(
            state: PredicateObservationStreamState(changeState: advance.state),
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

    func advancing(
        _ observation: HeistSemanticObservation,
        baselineSeed: PredicateObservationBaselineSeed,
        projection: AccessibilityTrace.DeltaProjection
    ) -> PredicateChangeObservationAdvance {
        switch self {
        case .observing(var cursor):
            cursor.append(observation)
            return cursor.advance(observedSequence: observation.event.sequence)
        case .awaitingBaseline:
            switch baselineSeed {
            case .preserve:
                return PredicateChangeObservationAdvance(
                    state: .awaitingBaseline,
                    readiness: .notRequired,
                    transition: nil
                )
            case .supplied(let suppliedBaseline):
                var cursor = PredicateChangeObservationCursor(
                    baseline: suppliedBaseline,
                    projection: projection
                )
                cursor.append(observation)
                return cursor.advance(observedSequence: observation.event.sequence)
            case .currentObservation:
                let cursor = PredicateChangeObservationCursor(
                    baseline: WaitChangeBaseline(event: observation.event),
                    projection: projection
                )
                return cursor.advance(observedSequence: observation.event.sequence)
            case .previousObservationIfAvailable:
                let inferredBaseline = WaitChangeBaseline(previousOf: observation.event)
                    ?? WaitChangeBaseline(event: observation.event)
                var cursor = PredicateChangeObservationCursor(
                    baseline: inferredBaseline,
                    projection: projection
                )
                cursor.append(observation)
                return cursor.advance(observedSequence: observation.event.sequence)
            }
        }
    }
}

private struct PredicateChangeObservationCursor {
    let baseline: WaitChangeBaseline
    let projection: AccessibilityTrace.DeltaProjection
    private(set) var accumulatedTrace: WaitAccumulatedTrace

    init(baseline: WaitChangeBaseline, projection: AccessibilityTrace.DeltaProjection) {
        self.baseline = baseline
        self.projection = projection
        self.accumulatedTrace = WaitAccumulatedTrace(baseline: baseline)
    }

    mutating func append(_ observation: HeistSemanticObservation) {
        accumulatedTrace.append(observation, projection: projection)
    }

    func advance(observedSequence: SettledObservationSequence) -> PredicateChangeObservationAdvance {
        guard let observedChange = PredicateObservedChange(
            baseline: baseline,
            observedSequence: observedSequence
        ) else {
            return PredicateChangeObservationAdvance(
                state: .observing(self),
                readiness: .baselineOnly(baseline),
                transition: nil
            )
        }

        guard accumulatedTrace.isAvailable else {
            return PredicateChangeObservationAdvance(
                state: .observing(self),
                readiness: .unavailableTrace(observedChange),
                transition: nil
            )
        }

        return PredicateChangeObservationAdvance(
            state: .observing(self),
            readiness: .observedTransition(observedChange),
            transition: PredicateTransitionEvidence(
                observedChange: observedChange,
                accumulatedTrace: accumulatedTrace,
                projection: projection
            )
        )
    }
}

private struct PredicateChangeObservationAdvance {
    let state: PredicateChangeObservationState
    let readiness: PredicateChangeReadiness
    let transition: PredicateTransitionEvidence?
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
        evidence.changeReadiness.baseline
    }

    var changeReadiness: PredicateChangeReadiness {
        evidence.changeReadiness
    }
}

extension PredicateWaitSnapshot {
    init(_ reduction: PredicateObservationReduction) {
        self.init(
            observation: PredicateWaitObservation(
                trace: reduction.trace ?? reduction.observation.accessibilityTrace,
                summary: reduction.observation.summary,
                visibleFingerprint: .known(reduction.observation.visibleFingerprint),
                sequence: reduction.observation.event.sequence
            ),
            expectation: reduction.expectation,
            changeReadiness: reduction.changeReadiness
        )
    }
}

struct PredicateObservationEvidence {
    private let snapshot: PredicateObservationSnapshot
    private let stateGraph: ElementMatchGraph
    let changeReadiness: PredicateChangeReadiness
    private let transition: PredicateTransitionEvidence?

    fileprivate init(
        snapshot: PredicateObservationSnapshot,
        changeReadiness: PredicateChangeReadiness,
        transition: PredicateTransitionEvidence?
    ) {
        self.snapshot = snapshot
        self.stateGraph = ElementMatchGraph(interface: snapshot.interface)
        self.changeReadiness = changeReadiness
        self.transition = transition
    }

    var observation: HeistSemanticObservation {
        snapshot.observation
    }

    var trace: AccessibilityTrace? {
        transition?.trace ?? snapshot.trace
    }

    func evaluate(_ predicate: AccessibilityPredicate) -> ExpectationResult {
        switch predicate {
        case .state(let state):
            return state.evaluate(in: stateGraph).expectation(for: predicate)
        case .changePredicate, .noChangePredicate:
            switch changeReadiness {
            case .notRequired, .unavailableTrace:
                return ExpectationResult(met: false, predicate: predicate, actual: "noTrace")
            case .baselineOnly:
                return ExpectationResult(
                    met: false,
                    predicate: predicate,
                    actual: PredicateObservationDiagnostics.changePredicateNeedsFutureObservationMessage
                )
            case .observedTransition:
                guard let transition else {
                    return ExpectationResult(met: false, predicate: predicate, actual: "noTrace")
                }
                return PredicateChangeMatchSet(
                    currentElements: stateGraph.all.elements,
                    transition: transition
                ).evaluate(predicate)
            }
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
    let observedChange: PredicateObservedChange
    private let accumulatedTrace: WaitAccumulatedTrace
    private let projection: AccessibilityTrace.DeltaProjection

    init(
        observedChange: PredicateObservedChange,
        accumulatedTrace: WaitAccumulatedTrace,
        projection: AccessibilityTrace.DeltaProjection
    ) {
        self.observedChange = observedChange
        self.accumulatedTrace = accumulatedTrace
        self.projection = projection
    }

    var trace: AccessibilityTrace? {
        accumulatedTrace.trace
    }

    var accumulatedDelta: AccessibilityTrace.AccumulatedDelta? {
        accumulatedTrace.delta(projection: projection)
    }
}

struct PredicatePollingObservationEvaluation<Evaluation> {
    let observation: HeistSemanticObservation
    let evaluation: Evaluation
}

struct PredicatePollingResult<Evaluation> {
    let last: PredicatePollingObservationEvaluation<Evaluation>?
    let elapsedMs: Int
}

private struct PredicatePollingCursor<Evaluation> {
    var observedSequence: SettledObservationSequence?
    var changeBaseline: PredicatePollingChangeBaseline
    var last: PredicatePollingObservationEvaluation<Evaluation>?

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
        let deadline = start + timeout
        var cursor = PredicatePollingCursor<Evaluation>(
            observedSequence: initialObservedSequence,
            changeBaselineSequence: initialChangeBaselineSequence,
            requiresChangeBaseline: requiresChangeBaseline
        )
        let reducer = PredicatePollingReducer(
            timeout: timeout,
            pollWhenTimeoutZero: pollWhenTimeoutZero
        )
        var reduction = reducer.start(
            scope: scope,
            initialObservedSequence: initialObservedSequence,
            initialVisibleFingerprint: initialVisibleFingerprint,
            discoveryBootstrap: discoveryBootstrap
        )
        var tickStart = start

        while true {
            switch reduction.effect {
            case .observe(let request):
                if request.kind == .visibleImmediate {
                    tickStart = CFAbsoluteTimeGetCurrent()
                }

                let observed = await pollObservation(
                    request: request,
                    cursor: &cursor,
                    evaluate: evaluate
                )
                let timing = Self.tickTiming(deadline: deadline, tickStart: tickStart)
                let event = pollingEvent(
                    for: request,
                    observed: observed,
                    timing: timing,
                    isMatched: isMatched
                )
                reduction = reducer.reduce(reduction.state, event: event)

            case .sleep(let sleep):
                guard await Self.sleep(sleep) else {
                    reduction = reducer.reduce(reduction.state, event: .sleepCancelled)
                    continue
                }
                reduction = reducer.reduce(
                    reduction.state,
                    event: .sleepCompleted(remaining: Self.remaining(deadline: deadline))
                )

            case .finish:
                return PredicatePollingResult(
                    last: cursor.last,
                    elapsedMs: Self.elapsedMilliseconds(since: start)
                )
            }
        }
    }

    private func pollingEvent(
        for request: PredicatePollingObservationRequest,
        observed: PredicatePollingObservationEvaluation<Evaluation>?,
        timing: PredicatePollingTickTiming,
        isMatched: (Evaluation) -> Bool
    ) -> PredicatePollingEvent {
        switch request.scope {
        case .visible:
            guard let observed else {
                return .visibleUnavailable(timing: timing)
            }
            return .visibleObserved(
                PredicatePollingVisibleObservation(
                    sequence: observed.observation.event.sequence,
                    fingerprint: PredicateVisibleFingerprint(observed.observation.visibleFingerprint),
                    matched: isMatched(observed.evaluation)
                ),
                timing: timing
            )
        case .discovery:
            guard let observed else {
                return .discoveryUnavailable(timing: timing)
            }
            return .discoveryObserved(
                PredicatePollingDiscoveryObservation(
                    sequence: observed.observation.event.sequence,
                    matched: isMatched(observed.evaluation)
                ),
                timing: timing
            )
        }
    }

    @MainActor
    private func pollObservation(
        request: PredicatePollingObservationRequest,
        cursor: inout PredicatePollingCursor<Evaluation>,
        evaluate: (HeistSemanticObservation, SettledObservationSequence?) -> Evaluation
    ) async -> PredicatePollingObservationEvaluation<Evaluation>? {
        guard let observation = await observeSemanticState(
            request.scope,
            request.after,
            request.timeout
        ) else {
            return nil
        }

        cursor.observedSequence = observation.event.sequence
        cursor.changeBaseline.recordObservation(observation)

        let evaluation = evaluate(observation, cursor.changeBaseline.sequence)
        let observed = PredicatePollingObservationEvaluation(
            observation: observation,
            evaluation: evaluation
        )
        cursor.last = observed
        return observed
    }

    private static func sleep(_ sleep: PredicatePollingSleep) async -> Bool {
        guard sleep.duration > 0 else { return true }
        let nanoseconds = UInt64((sleep.duration * 1_000_000_000).rounded(.up))
        return await Task.cancellableSleep(for: .nanoseconds(nanoseconds))
    }

    private static func tickTiming(
        deadline: CFAbsoluteTime,
        tickStart: CFAbsoluteTime
    ) -> PredicatePollingTickTiming {
        let now = CFAbsoluteTimeGetCurrent()
        return PredicatePollingTickTiming(
            remaining: remaining(deadline: deadline, now: now),
            elapsed: max(0, now - tickStart)
        )
    }

    private static func remaining(deadline: CFAbsoluteTime) -> Double {
        remaining(deadline: deadline, now: CFAbsoluteTimeGetCurrent())
    }

    private static func remaining(deadline: CFAbsoluteTime, now: CFAbsoluteTime) -> Double {
        max(0, deadline - now)
    }

    private static func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

private extension HeistSemanticObservation {
    var visibleFingerprint: String {
        state.screen.visibleOnly.semanticHash
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
