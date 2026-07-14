#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport
import ThePlans

import TheScore

internal enum PredicateObservationDiagnostics {
    internal static let changePredicateNeedsFutureObservationMessage = "change predicate requires future settled observation after baseline"
}

internal enum AnnouncementWaitCursorStrategy: Sendable, Equatable {
    case futureOnly
    case heistScoped
}

internal enum PredicateChangeBaselineSource: Sendable, Equatable {
    case establishFromFirstObservation
    case supplied(SettledCapture?)

    internal var capture: SettledCapture? {
        guard case .supplied(let capture) = self else { return nil }
        return capture
    }
}

internal struct WaitObservationPlan: Sendable, Equatable {
    internal static let temporalScope = SemanticObservationScope.discovery

    internal let scope: SemanticObservationScope

    internal init(predicate _: ResolvedAccessibilityPredicate) {
        scope = Self.temporalScope
    }

    internal init(step: ResolvedWaitRuntimeInput) {
        self.init(predicate: step.predicate)
    }
}

// PredicateWait stores main-actor closures and is constructed/used from main-actor observation code.
@MainActor internal struct PredicateWait { // swiftlint:disable:this agent_main_actor_value_type
    internal typealias ObserveEvent = @MainActor (
        SemanticObservationScope,
        SettledObservationSequence?,
        Double?
    ) async -> SettledSemanticObservationEvent?
    internal typealias LatestEvent = @MainActor () -> SettledSemanticObservationEvent?
    internal typealias LatestSettleFailure = @MainActor () -> String?
    internal typealias SemanticObserver = @MainActor (SettledSemanticObservationEvent) -> HeistSemanticObservation
    internal typealias BuildObservationWindow = @MainActor (
        SettledCapture,
        SettledSemanticObservationEvent
    ) -> ObservationWindow?
    internal typealias PresenceTimeoutMessage = @MainActor (ResolvedAccessibilityPredicate, String) -> String?
    internal typealias AnnouncementCursor = @MainActor (AnnouncementWaitCursorStrategy) -> AccessibilityNotificationCursor
    internal typealias AnnouncementWait = @MainActor (
        AccessibilityNotificationCursor,
        ResolvedAnnouncementPredicate,
        Double
    ) async -> CapturedAnnouncement?
    /// Called after an unmatched initial observation is reduced and before polling begins.
    internal typealias ReadyToPoll = @MainActor (SettledObservationSequence) -> Void

    internal let observeEvent: ObserveEvent
    internal let latestEvent: LatestEvent
    internal let latestSettleFailure: LatestSettleFailure
    internal let semanticObservation: SemanticObserver
    internal let buildObservationWindow: BuildObservationWindow
    internal let presenceTimeoutMessage: PresenceTimeoutMessage
    internal let announcementCursor: AnnouncementCursor
    internal let waitForAnnouncement: AnnouncementWait

    internal init(
        observeEvent: @escaping ObserveEvent,
        latestEvent: @escaping LatestEvent,
        latestSettleFailure: @escaping LatestSettleFailure,
        semanticObservation: @escaping SemanticObserver,
        buildObservationWindow: @escaping BuildObservationWindow,
        presenceTimeoutMessage: @escaping PresenceTimeoutMessage,
        announcementCursor: @escaping AnnouncementCursor,
        waitForAnnouncement: @escaping AnnouncementWait
    ) {
        self.observeEvent = observeEvent
        self.latestEvent = latestEvent
        self.latestSettleFailure = latestSettleFailure
        self.semanticObservation = semanticObservation
        self.buildObservationWindow = buildObservationWindow
        self.presenceTimeoutMessage = presenceTimeoutMessage
        self.announcementCursor = announcementCursor
        self.waitForAnnouncement = waitForAnnouncement
    }

    internal func wait(
        for step: ResolvedWaitRuntimeInput,
        initialTrace: AccessibilityTrace? = nil,
        after sequence: SettledObservationSequence? = nil,
        changeBaseline: PredicateChangeBaselineSource = .establishFromFirstObservation,
        observationPlan: WaitObservationPlan? = nil,
        announcementCursorStrategy: AnnouncementWaitCursorStrategy = .futureOnly,
        onReadyToPoll: ReadyToPoll? = nil
    ) async -> HeistWaitReceipt {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = Self.clampedWaitTimeout(step.timeout)
        if case .announcement(let announcement) = step.predicate.core {
            return await waitForAnnouncementPredicate(
                announcement,
                step: step,
                initialTrace: initialTrace,
                start: start,
                timeout: timeout,
                cursorStrategy: announcementCursorStrategy
            )
        }

        if let traceEvaluation = initialTraceChangeEvaluation(
            for: step,
            initialTrace: initialTrace
        ), traceEvaluation.met {
            return waitReceipt(
                for: step,
                trace: initialTrace,
                observationSummary: nil,
                expectation: traceEvaluation,
                start: start,
                success: true
            )
        }

        let plan = observationPlan ?? WaitObservationPlan(step: step)

        let initialEntry = await observeSemanticState(
            scope: plan.scope,
            after: sequence,
            timeout: sequence == nil ? 0 : timeout
        )
        guard let entry = initialEntry else {
            return await waitReceiptWithoutInitialObservation(
                for: step,
                initialTrace: initialTrace,
                start: start,
                shouldPoll: timeout > 0 && sequence == nil,
                observationScope: plan.scope,
                changeBaseline: changeBaseline
            )
        }

        var state = State(predicate: step.predicateExpression)
        var stream = PredicateObservationStreamState()
        let reducer = Reducer()

        let initialDecision = initialDecision(
            for: step,
            entry: entry,
            initialTrace: initialTrace,
            baselineSource: changeBaseline,
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

        onReadyToPoll?(entry.event.sequence)

        if let decision = await pollDecision(
            for: step,
            scope: plan.scope,
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
        for step: ResolvedWaitRuntimeInput,
        entry: HeistSemanticObservation,
        initialTrace: AccessibilityTrace?,
        baselineSource: PredicateChangeBaselineSource,
        reducer: Reducer,
        stream: inout PredicateObservationStreamState,
        state: inout State,
        timeout: Double
    ) -> Decision {
        if step.predicate.requiresChangeBaseline {
            switch baselineSource {
            case .supplied(let suppliedBaseline):
                return observedInitialDecision(
                    for: step,
                    entry: entry,
                    reducer: reducer,
                    stream: &stream,
                    state: state,
                    baselineSeed: suppliedBaseline.map(PredicateObservationBaselineSeed.supplied)
                        ?? .preserve,
                    timedOutWhenUnmatched: timeout == 0
                )
            case .establishFromFirstObservation:
                let reduced = stream.reducing(
                    entry,
                    predicate: step.predicate,
                    predicateExpression: step.predicateExpression,
                    baselineSeed: .currentObservation
                )
                stream = reduced.state
                state = reducer.reduce(
                    state,
                    event: .baseline(Snapshot(reduced.reduction))
                )
                return timeout == 0 ? reducer.decision(state) : .poll(state)
            }
        }

        return observedInitialDecision(
            for: step,
            entry: entry,
            reducer: reducer,
            stream: &stream,
            state: state,
            baselineSeed: .currentObservation,
            timedOutWhenUnmatched: timeout == 0
        )
    }

    private func observedInitialDecision(
        for step: ResolvedWaitRuntimeInput,
        entry: HeistSemanticObservation,
        reducer: Reducer,
        stream: inout PredicateObservationStreamState,
        state: State,
        baselineSeed: PredicateObservationBaselineSeed,
        timedOutWhenUnmatched: Bool
    ) -> Decision {
        let reduced = reduceObservation(
            entry,
            predicate: step.predicate,
            predicateExpression: step.predicateExpression,
            baselineSeed: baselineSeed,
            stream: stream
        )
        stream = reduced.state
        return reducer.decision(
            after: .observation(Snapshot(reduced.reduction)),
            reducing: state,
            timedOutWhenUnmatched: timedOutWhenUnmatched
        )
    }

    private func pollDecision(
        for step: ResolvedWaitRuntimeInput,
        scope: SemanticObservationScope,
        start: CFAbsoluteTime,
        reducer: Reducer,
        state: inout State,
        stream initialStream: PredicateObservationStreamState
    ) async -> Decision? {
        var stream = initialStream
        var waitState = state
        let pollResult = await PredicatePollingEngine<Decision>(
            observeSemanticState: observeSemanticState
        ).poll(
            scope: scope,
            timeout: step.timeout,
            start: start,
            after: state.observedSequence,
            pollWhenTimeoutZero: false,
            initialVisibleFingerprint: state.lastVisibleFingerprint,
            discoveryBootstrap: .ifNoObservation,
            evaluate: { observation in
                let reduced = reduceObservation(
                    observation,
                    predicate: step.predicate,
                    predicateExpression: step.predicateExpression,
                    baselineSeed: .preserve,
                    stream: stream
                )
                stream = reduced.state
                let decision = reducer.decision(
                    after: .observation(Snapshot(reduced.reduction)),
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

    internal func reduceObservation(
        _ observation: HeistSemanticObservation,
        predicate: ResolvedAccessibilityPredicate,
        predicateExpression: AccessibilityPredicate,
        baselineSeed: PredicateObservationBaselineSeed,
        stream: PredicateObservationStreamState
    ) -> PredicateObservationStreamReduction {
        let seeded = stream.reducing(
            observation,
            predicate: predicate,
            predicateExpression: predicateExpression,
            baselineSeed: baselineSeed
        )
        guard predicate.requiresChangeBaseline,
              let baseline = seeded.state.observationBaseline else { return seeded }
        let window = buildObservationWindow(
            baseline,
            observation.event
        )
        return stream.reducing(
            observation,
            predicate: predicate,
            predicateExpression: predicateExpression,
            baselineSeed: .supplied(baseline),
            observationWindow: window
        )
    }

    internal func observeSemanticState(
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
}

#endif // DEBUG
#endif // canImport(UIKit)
