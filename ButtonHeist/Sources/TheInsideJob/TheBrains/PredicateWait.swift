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

internal struct WaitObservationPlan: Sendable, Equatable {
    internal let scope: SemanticObservationScope

    internal init(predicate _: AccessibilityPredicate<RootContext>) {
        scope = .discovery
    }

    internal init(step: ResolvedWaitStep) {
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
    internal typealias PresenceTimeoutMessage = @MainActor (AccessibilityPredicate<RootContext>, String) -> String?
    internal typealias AnnouncementCursor = @MainActor (AnnouncementWaitCursorStrategy) -> AccessibilityNotificationCursor
    internal typealias AnnouncementWait = @MainActor (
        AccessibilityNotificationCursor,
        AnnouncementPredicate,
        Double
    ) async -> CapturedAnnouncement?

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
        buildObservationWindow: @escaping BuildObservationWindow = ObservationWindow.direct,
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
        for step: WaitStep,
        initialTrace: AccessibilityTrace? = nil,
        after sequence: SettledObservationSequence? = nil,
        observationPlan: WaitObservationPlan? = nil,
        announcementCursorStrategy: AnnouncementWaitCursorStrategy = .futureOnly
    ) async -> HeistWaitReceipt {
        do {
            let resolvedStep = try step.resolve(in: .empty)
            return await wait(
                for: resolvedStep,
                initialTrace: initialTrace,
                after: sequence,
                observationPlan: observationPlan ?? WaitObservationPlan(step: resolvedStep),
                announcementCursorStrategy: announcementCursorStrategy
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

    internal func wait(
        for step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace? = nil,
        after sequence: SettledObservationSequence? = nil,
        observationPlan: WaitObservationPlan? = nil,
        announcementCursorStrategy: AnnouncementWaitCursorStrategy = .futureOnly
    ) async -> HeistWaitReceipt {
        let start = CFAbsoluteTimeGetCurrent()
        let timeout = Self.clampedWaitTimeout(step.timeout)
        if case .announcement(let announcement) = step.predicate.node {
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
            for: step.predicate,
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
                observationScope: plan.scope
            )
        }

        var state = State(predicate: step.predicate)
        var stream = PredicateObservationStreamState()
        let reducer = Reducer(
            step: step,
            timeout: timeout
        )

        let initialDecision = initialDecision(
            for: step,
            entry: entry,
            initialTrace: initialTrace,
            suppliedBaselineSequence: sequence,
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
        for step: ResolvedWaitStep,
        entry: HeistSemanticObservation,
        initialTrace: AccessibilityTrace?,
        suppliedBaselineSequence: SettledObservationSequence?,
        reducer: Reducer,
        stream: inout PredicateObservationStreamState,
        state: inout State,
        timeout: Double
    ) -> Decision {
        if step.predicate.requiresChangeBaseline,
           let suppliedBaseline = Self.suppliedChangeBaseline(
               from: initialTrace,
               sequence: suppliedBaselineSequence,
               entry: entry.event
           ) {
            return observedInitialDecision(
                for: step,
                entry: entry,
                reducer: reducer,
                stream: &stream,
                state: state,
                baselineSeed: .supplied(suppliedBaseline),
                suppliedTrace: initialTrace,
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
                event: .baseline(Snapshot(reduced.reduction))
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
        reducer: Reducer,
        stream: inout PredicateObservationStreamState,
        state: State,
        baselineSeed: PredicateObservationBaselineSeed,
        suppliedTrace: AccessibilityTrace? = nil,
        timedOutWhenUnmatched: Bool
    ) -> Decision {
        let reduced = reduceObservation(
            entry,
            predicate: step.predicate,
            baselineSeed: baselineSeed,
            stream: stream,
            suppliedTrace: suppliedTrace
        )
        stream = reduced.state
        return reducer.decision(
            after: .observation(Snapshot(reduced.reduction)),
            reducing: state,
            timedOutWhenUnmatched: timedOutWhenUnmatched
        )
    }

    private func pollDecision(
        for step: ResolvedWaitStep,
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
        predicate: AccessibilityPredicate<RootContext>,
        baselineSeed: PredicateObservationBaselineSeed,
        stream: PredicateObservationStreamState,
        suppliedTrace: AccessibilityTrace? = nil
    ) -> PredicateObservationStreamReduction {
        let seeded = stream.reducing(
            observation,
            predicate: predicate,
            baselineSeed: baselineSeed,
            preserving: suppliedTrace
        )
        guard let baseline = seeded.state.changeBaseline else { return seeded }
        let window = buildObservationWindow(
            baseline,
            observation.event
        )
        return stream.reducing(
            observation,
            predicate: predicate,
            baselineSeed: .supplied(baseline),
            observationWindow: window,
            preserving: suppliedTrace
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
