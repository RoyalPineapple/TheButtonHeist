#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

enum PredicateObservationDiagnostics {
    static let changePredicateNeedsFutureObservationMessage = "change predicate requires future settled observation after baseline"
}

private struct PredicateWaitPollEvaluation {
    let expectation: ExpectationResult
    let warning: HeistPredicateWarning?

    var met: Bool {
        expectation.met || warning != nil
    }
}

private enum FinalStateSatisfactionTiming: String {
    case baseline
    case afterObservation = "after_observation"
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

        var state = WaitPredicateState(predicate: step.predicate)
        var stream = PredicateObservationStreamState()

        let initialOutcome = recordInitialEntry(
            entry,
            for: step,
            initialTrace: initialTrace,
            timeout: timeout,
            stream: &stream,
            state: &state
        )
        switch initialOutcome {
        case .matched:
            return waitReceipt(for: step, state: state, start: start, success: true)
        case .timedOut:
            if allowsTransitionFinalStateWarning,
               let warning = finalStateSatisfiedTransitionWarning(for: step.predicate, state: state) {
                return waitReceipt(for: step, state: state, start: start, success: true, warning: warning)
            }
            return waitReceipt(for: step, state: state, start: start, success: false)
        case .poll:
            break
        }

        if allowsTransitionFinalStateWarning,
           let warning = finalStateSatisfiedTransitionWarning(for: step.predicate, state: state) {
            return waitReceipt(for: step, state: state, start: start, success: true, warning: warning)
        }

        guard timeout > 0 else {
            return waitReceipt(for: step, state: state, start: start, success: false)
        }

        let pollResult = await PredicatePollingEngine<PredicateWaitPollEvaluation>(
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
                return pollEvaluation(
                    for: reduced.reduction,
                    predicate: step.predicate,
                    state: state,
                    allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning
                )
            },
            isMatched: { $0.met }
        )

        if let reduction = stream.latestReduction,
           pollResult.lastEvaluation != nil {
            state.record(reduction)
            if reduction.expectation.met {
                return waitReceipt(for: step, state: state, start: start, success: true)
            }
            if let warning = pollResult.lastEvaluation?.warning {
                return waitReceipt(for: step, state: state, start: start, success: true, warning: warning)
            }
        }

        if allowsTransitionFinalStateWarning,
           let warning = finalStateSatisfiedTransitionWarning(for: step.predicate, state: state) {
            return waitReceipt(
                for: step,
                state: state,
                start: start,
                success: true,
                warning: warning
            )
        }

        return waitReceipt(
            for: step,
            state: state,
            start: start,
            success: false
        )
    }

    private func recordInitialEntry(
        _ entry: HeistSemanticObservation,
        for step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace?,
        timeout: Double,
        stream: inout PredicateObservationStreamState,
        state: inout WaitPredicateState
    ) -> PredicateInitialObservationOutcome {
        if step.predicate.requiresChangeBaseline,
           let suppliedBaseline = Self.suppliedChangeBaseline(from: initialTrace, entry: entry.event) {
            let reduced = stream.reducing(
                entry,
                predicate: step.predicate,
                baselineSeed: .supplied(suppliedBaseline)
            )
            stream = reduced.state
            state.record(reduced.reduction)
            if state.lastEvaluation.met {
                return .matched
            }
            return timeout == 0 ? .timedOut : .poll
        }

        if step.predicate.requiresChangeBaseline {
            let reduced = stream.reducing(
                entry,
                predicate: step.predicate,
                baselineSeed: .currentObservation
            )
            stream = reduced.state
            state.recordBaseline(reduced.reduction)
            return timeout == 0 ? .timedOut : .poll
        }

        let reduced = stream.reducing(entry, predicate: step.predicate)
        stream = reduced.state
        state.record(reduced.reduction)
        if state.lastEvaluation.met {
            return .matched
        }
        return timeout == 0 ? .timedOut : .poll
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
        var state = WaitPredicateState(predicate: step.predicate)
        var stream = PredicateObservationStreamState()

        if shouldPoll {
            let pollResult = await PredicatePollingEngine<PredicateWaitPollEvaluation>(
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
                    return pollEvaluation(
                        for: reduced.reduction,
                        predicate: step.predicate,
                        state: state,
                        allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning
                    )
                },
                isMatched: { $0.met }
            )

            if let reduction = stream.latestReduction,
               pollResult.lastEvaluation != nil {
                state.record(reduction)
                if reduction.expectation.met {
                    return waitReceipt(for: step, state: state, start: start, success: true)
                }
                if let warning = pollResult.lastEvaluation?.warning {
                    return waitReceipt(for: step, state: state, start: start, success: true, warning: warning)
                }
            }
        }

        if allowsTransitionFinalStateWarning,
           let warning = finalStateSatisfiedTransitionWarning(for: step.predicate, state: state) {
            return waitReceipt(for: step, state: state, start: start, success: true, warning: warning)
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

    private func pollEvaluation(
        for reduction: PredicateObservationReduction,
        predicate: AccessibilityPredicate,
        state: WaitPredicateState,
        allowsTransitionFinalStateWarning: Bool
    ) -> PredicateWaitPollEvaluation {
        let expectation = reduction.expectation
        guard !expectation.met, allowsTransitionFinalStateWarning else {
            return PredicateWaitPollEvaluation(expectation: expectation, warning: nil)
        }

        var warningState = state
        warningState.record(reduction)
        return PredicateWaitPollEvaluation(
            expectation: expectation,
            warning: finalStateSatisfiedTransitionWarning(for: predicate, state: warningState)
        )
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

    private func finalStateSatisfiedTransitionWarning(
        for predicate: AccessibilityPredicate,
        state: WaitPredicateState
    ) -> HeistPredicateWarning? {
        if let element = predicate.singleAppearedElementMatcher {
            return presenceFinalStateWarning(
                for: predicate,
                state: state,
                element: element,
                expectedPresence: true
            )
        }

        if let element = predicate.singleDisappearedElementMatcher {
            return presenceFinalStateWarning(
                for: predicate,
                state: state,
                element: element,
                expectedPresence: false
            )
        }

        if let update = predicate.singleUpdatedElementWithDestination {
            return updateFinalStateWarning(
                for: predicate,
                state: state,
                update: update
            )
        }

        return nil
    }

    private func presenceFinalStateWarning(
        for predicate: AccessibilityPredicate,
        state: WaitPredicateState,
        element: ElementPredicate,
        expectedPresence: Bool
    ) -> HeistPredicateWarning? {
        guard let baselineElements = state.changeBaseline?.capture?.interface.projectedElements else {
            return nil
        }

        let timing: FinalStateSatisfactionTiming
        let evidence: String
        if let baselineEvidence = Self.presenceEvidence(of: element, in: baselineElements),
           expectedPresence {
            timing = .baseline
            evidence = baselineEvidence
        } else if !expectedPresence,
                  !Self.isPresent(element, in: baselineElements) {
            timing = .baseline
            evidence = Self.warningSubject(for: element)
        } else if let finalElements = state.finalElements,
                  let finalEvidence = Self.presenceEvidence(of: element, in: finalElements),
                  expectedPresence {
            timing = .afterObservation
            evidence = finalEvidence
        } else if let finalElements = state.finalElements,
                  !expectedPresence,
                  !Self.isPresent(element, in: finalElements) {
            timing = .afterObservation
            evidence = Self.warningSubject(for: element)
        } else {
            return nil
        }

        let subject = Self.warningSubject(for: element)
        let stateDescription = expectedPresence ? "present" : "absent"
        let transitionDescription = expectedPresence ? "appearance" : "disappearance"
        let timingDescription = timing == .baseline
            ? "was already \(stateDescription) when the wait began"
            : "satisfied the \(stateDescription) final state without an observed transition"
        let message = "\(subject) \(timingDescription), so no \(transitionDescription) was observed. "
            + "The final state satisfied the wait."
        return HeistPredicateWarning(
            code: "transition_not_observed_final_state_satisfied",
            predicate: predicate.description,
            impliedPredicate: AccessibilityPredicate.state(expectedPresence ? .exists(element) : .missing(element)).description,
            finalStateTiming: timing.rawValue,
            evidence: evidence,
            message: message
        )
    }

    private func updateFinalStateWarning(
        for predicate: AccessibilityPredicate,
        state: WaitPredicateState,
        update: ElementUpdatePredicate
    ) -> HeistPredicateWarning? {
        guard let baselineElements = state.changeBaseline?.capture?.interface.projectedElements
        else { return nil }

        let timing: FinalStateSatisfactionTiming
        let evidence: String
        if let baselineEvidence = updateFinalStateEvidence(update, in: baselineElements) {
            timing = .baseline
            evidence = baselineEvidence
        } else if let finalElements = state.finalElements,
                  let finalEvidence = updateFinalStateEvidence(update, in: finalElements) {
            timing = .afterObservation
            evidence = finalEvidence
        } else {
            return nil
        }

        let timingDescription = timing == .baseline
            ? "was already satisfied when the wait began"
            : "became satisfied without an observed matching transition"
        let message = "The destination update state \(timingDescription), so no update transition was observed. "
            + "The final state satisfied the wait."
        return HeistPredicateWarning(
            code: "transition_not_observed_final_state_satisfied",
            predicate: predicate.description,
            impliedPredicate: Self.impliedUpdateFinalStateDescription(update),
            finalStateTiming: timing.rawValue,
            evidence: evidence,
            message: message
        )
    }

    private func updateFinalStateEvidence(
        _ update: ElementUpdatePredicate,
        in elements: [HeistElement]
    ) -> String? {
        guard let change = update.change?.destinationChange else { return nil }
        let candidates = update.element.map {
            ElementMatchSet(elements: elements).matching($0).elements
        } ?? elements

        for element in candidates
        where Self.destinationPropertyChange(for: change.property, in: element)?.satisfies(change) == true {
            return Self.warningEvidence(for: element)
        }
        return nil
    }

    private static func isPresent(_ predicate: ElementPredicate, in elements: [HeistElement]) -> Bool {
        !ElementMatchSet(elements: elements).matching(predicate).isEmpty
    }

    private static func presenceEvidence(of predicate: ElementPredicate, in elements: [HeistElement]) -> String? {
        ElementMatchSet(elements: elements).matching(predicate).elements.first.map(warningEvidence(for:))
    }

    private static func warningEvidence(for element: HeistElement) -> String {
        if let label = element.label, !label.isEmpty {
            return "label=\(label)"
        }
        if let identifier = element.identifier, !identifier.isEmpty {
            return "identifier=\(identifier)"
        }
        return "description=\(element.description)"
    }

    private static func impliedUpdateFinalStateDescription(_ update: ElementUpdatePredicate) -> String? {
        guard let destinationChange = update.change?.destinationChange else { return nil }
        let subject = update.element.map { "element=\($0)" } ?? "element=any"
        return ScoreDescription.call("destination_state", [
            subject,
            "change=\(destinationChange)",
        ])
    }

    private static func destinationPropertyChange(
        for property: ElementProperty,
        in element: HeistElement
    ) -> PropertyChange? {
        switch property {
        case .label, .identifier:
            return nil
        case .value:
            return ValueProperty.value(in: element).map { .value(old: nil, new: $0) }
        case .traits:
            return TraitsProperty.value(in: element).map { .traits(old: nil, new: $0) }
        case .hint:
            return HintProperty.value(in: element).map { .hint(old: nil, new: $0) }
        case .actions:
            return ActionsProperty.value(in: element).map { .actions(old: nil, new: $0) }
        case .frame:
            return FrameProperty.value(in: element).map { .frame(old: nil, new: $0) }
        case .activationPoint:
            return ActivationPointProperty.value(in: element).map { .activationPoint(old: nil, new: $0) }
        case .customContent:
            return CustomContentProperty.value(in: element).map { .customContent(old: nil, new: $0) }
        case .rotors:
            return RotorsProperty.value(in: element).map { .rotors(old: nil, new: $0) }
        }
    }

    private static func warningSubject(for predicate: ElementPredicate) -> String {
        for check in predicate.checks {
            if case .label(.exact(let label)) = check, !label.isEmpty {
                return label
            }
        }
        return "The element"
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
            observedSequence: observedSequence,
            observationSummary: observationSummary
        )
    }

    private func waitReceipt(
        for step: ResolvedWaitStep,
        state: WaitPredicateState,
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
        observedSequence: SettledObservationSequence? = nil,
        observationSummary receiptObservationSummary: String? = nil
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
                observationSummary: receiptObservationSummary,
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

struct WaitChangeBaseline {
    let sequence: SettledObservationSequence
    let capture: AccessibilityTrace.Capture?

    var hash: String? {
        capture?.hash
    }

    init(sequence: SettledObservationSequence, capture: AccessibilityTrace.Capture?) {
        self.sequence = sequence
        self.capture = capture
    }

    init(event: SettledSemanticObservationEvent) {
        self.sequence = event.sequence
        self.capture = event.trace.captures.last
    }

    init?(previousOf event: SettledSemanticObservationEvent) {
        guard let previous = event.previous,
              previous.sequence < event.sequence,
              let capture = event.trace.captures.first
        else { return nil }
        self.sequence = previous.sequence
        self.capture = capture
    }
}

enum PredicateInitialObservationOutcome {
    case matched
    case timedOut
    case poll
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

enum PredicateVisibleFingerprint: Equatable {
    case unknown
    case known(String)

    init(_ rawValue: String?) {
        if let rawValue {
            self = .known(rawValue)
        } else {
            self = .unknown
        }
    }

    func replacingUnknown(with fallback: PredicateVisibleFingerprint) -> PredicateVisibleFingerprint {
        switch self {
        case .known:
            return self
        case .unknown:
            return fallback
        }
    }
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

private extension AccessibilityPredicate {
    var singleAppearedElementMatcher: ElementPredicate? {
        guard case .changePredicate(.elementsScope(let assertions)) = self,
              assertions.count == 1,
              case .appearedElement(let element) = assertions[0] else {
            return nil
        }
        return element
    }

    var singleDisappearedElementMatcher: ElementPredicate? {
        guard case .changePredicate(.elementsScope(let assertions)) = self,
              assertions.count == 1,
              case .disappearedElement(let element) = assertions[0] else {
            return nil
        }
        return element
    }

    var singleUpdatedElementWithDestination: ElementUpdatePredicate? {
        guard case .changePredicate(.elementsScope(let assertions)) = self,
              assertions.count == 1,
              case .updatedElement(let update) = assertions[0],
              update.change?.destinationChange != nil else {
            return nil
        }
        return update
    }
}

private extension AnyPropertyChange {
    var destinationChange: AnyPropertyChange? {
        switch self {
        case .value(let change):
            return change.after.map { .value(ElementPropertyChange<ValueProperty>(after: $0)) }
        case .traits(let change):
            return change.after.map { .traits(ElementPropertyChange<TraitsProperty>(after: $0)) }
        case .hint(let change):
            return change.after.map { .hint(ElementPropertyChange<HintProperty>(after: $0)) }
        case .actions(let change):
            return change.after.map { .actions(ElementPropertyChange<ActionsProperty>(after: $0)) }
        case .frame(let change):
            return change.after.map { .frame(ElementPropertyChange<FrameProperty>(after: $0)) }
        case .activationPoint(let change):
            return change.after.map { .activationPoint(ElementPropertyChange<ActivationPointProperty>(after: $0)) }
        case .customContent(let change):
            return change.after.map { .customContent(ElementPropertyChange<CustomContentProperty>(after: $0)) }
        case .rotors(let change):
            return change.after.map { .rotors(ElementPropertyChange<RotorsProperty>(after: $0)) }
        }
    }
}

private struct WaitPredicateState {
    var lastTrace: AccessibilityTrace?
    var lastObservationSummary: String?
    var lastVisibleFingerprint: PredicateVisibleFingerprint = .unknown
    var observedSequence: SettledObservationSequence?
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

    var finalElements: [HeistElement]? {
        lastTrace?.captures.last?.interface.projectedElements
    }

    mutating func record(_ reduction: PredicateObservationReduction) {
        lastTrace = reduction.trace ?? reduction.observation.accessibilityTrace
        lastObservationSummary = reduction.observation.summary
        lastVisibleFingerprint = .known(reduction.observation.visibleFingerprint)
        lastEvaluation = reduction.expectation
        observedSequence = reduction.observation.event.sequence
        changeBaseline = reduction.changeBaseline
        sawObservationAfterBaseline = reduction.sawObservationAfterBaseline
    }

    mutating func recordBaseline(_ reduction: PredicateObservationReduction) {
        lastTrace = reduction.observation.accessibilityTrace
        lastObservationSummary = reduction.observation.summary
        lastVisibleFingerprint = .known(reduction.observation.visibleFingerprint)
        observedSequence = reduction.observation.event.sequence
        changeBaseline = reduction.changeBaseline
        sawObservationAfterBaseline = reduction.sawObservationAfterBaseline
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
