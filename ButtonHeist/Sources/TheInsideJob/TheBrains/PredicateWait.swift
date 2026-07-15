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
    internal typealias SettleVisible = @MainActor (
        SemanticObservationDeadline
    ) async -> SettledSemanticObservationEvent?
    internal typealias RevealTarget = @MainActor (
        ResolvedAccessibilityTarget,
        SemanticObservationDeadline?
    ) async -> SettledSemanticObservationEvent?
    internal typealias DiscoveryObserver = @MainActor (
        SettledSemanticObservationEvent
    ) -> Bool
    internal typealias Discover = @MainActor (
        ResolvedAccessibilityTarget?,
        SemanticObservationDeadline?,
        @escaping DiscoveryObserver
    ) async -> SettledSemanticObservationEvent?
    internal typealias LatestObservationCursor = @MainActor () -> ObservationCursor?
    internal typealias ObservationEntries = @MainActor (
        ObservationCursor?
    ) -> ObservationEntrySequence?
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
    internal let settleVisible: SettleVisible
    internal let revealTarget: RevealTarget
    internal let discover: Discover
    internal let latestObservationCursor: LatestObservationCursor
    internal let observationEntries: ObservationEntries

    internal init(
        observeEvent: @escaping ObserveEvent,
        latestEvent: @escaping LatestEvent,
        latestSettleFailure: @escaping LatestSettleFailure,
        semanticObservation: @escaping SemanticObserver,
        buildObservationWindow: @escaping BuildObservationWindow,
        presenceTimeoutMessage: @escaping PresenceTimeoutMessage,
        announcementCursor: @escaping AnnouncementCursor,
        waitForAnnouncement: @escaping AnnouncementWait,
        settleVisible: SettleVisible? = nil,
        revealTarget: RevealTarget? = nil,
        discover: Discover? = nil,
        latestObservationCursor: @escaping LatestObservationCursor = { nil },
        observationEntries: @escaping ObservationEntries = { _ in nil }
    ) {
        self.observeEvent = observeEvent
        self.latestEvent = latestEvent
        self.latestSettleFailure = latestSettleFailure
        self.semanticObservation = semanticObservation
        self.buildObservationWindow = buildObservationWindow
        self.presenceTimeoutMessage = presenceTimeoutMessage
        self.announcementCursor = announcementCursor
        self.waitForAnnouncement = waitForAnnouncement
        self.settleVisible = settleVisible ?? { deadline in
            await observeEvent(.visible, nil, deadline.remainingSeconds())
        }
        self.revealTarget = revealTarget ?? { _, _ in nil }
        self.discover = discover ?? { _, deadline, observer in
            let event = await observeEvent(.discovery, nil, deadline?.remainingSeconds())
            if let event { _ = observer(event) }
            return event
        }
        self.latestObservationCursor = latestObservationCursor
        self.observationEntries = observationEntries
    }

    internal func wait(
        for step: ResolvedWaitRuntimeInput,
        initialTrace: AccessibilityTrace? = nil,
        changeBaseline: PredicateChangeBaselineSource = .establishFromFirstObservation,
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

        return await Execution(
            wait: self,
            step: step,
            start: start,
            timeout: timeout,
            changeBaseline: changeBaseline,
            onReadyToPoll: onReadyToPoll
        ).run()
    }

    @MainActor
    private final class Execution {
        private let wait: PredicateWait
        private let step: ResolvedWaitRuntimeInput
        private let start: CFAbsoluteTime
        private let deadline: SemanticObservationDeadline
        private let changeBaseline: PredicateChangeBaselineSource
        private let onReadyToPoll: ReadyToPoll?
        private let reducer = Reducer()
        private var state: State
        private var stream = PredicateObservationStreamState()
        private var lifecycle = StateDriver(
            initial: PredicateWaitLifecycleState.initialVisible,
            machine: PredicateWaitLifecycleMachine()
        )
        private var effect = PredicateWaitLifecycleEffect.settleVisible(.overall)
        private var ignoreObservationsThrough: SettledObservationSequence?

        init(
            wait: PredicateWait,
            step: ResolvedWaitRuntimeInput,
            start: CFAbsoluteTime,
            timeout: Double,
            changeBaseline: PredicateChangeBaselineSource,
            onReadyToPoll: ReadyToPoll?
        ) {
            self.wait = wait
            self.step = step
            self.start = start
            deadline = SemanticObservationDeadline(start: start, timeoutSeconds: timeout)
            self.changeBaseline = changeBaseline
            self.onReadyToPoll = onReadyToPoll
            state = State(predicate: step.predicateExpression)
        }

        func run() async -> HeistWaitReceipt {
            var signalIterator: AsyncStream<PredicateWaitLifecycleSignal>.Iterator?
            while true {
                applyCancellation()
                switch effect {
                case .settleVisible(let budget):
                    await settleVisible(budget)
                case .discover(let budget):
                    if let signals = await runDiscovery(budget) {
                        signalIterator = signals.makeAsyncIterator()
                    }
                case .awaitObservation:
                    guard var iterator = signalIterator else {
                        effect = lifecycle.send(.deadlineReached).predicateWaitEffect
                        continue
                    }
                    var signal = await iterator.next()
                    signalIterator = iterator
                    while case .observation(let observation) = signal,
                          let ignored = ignoreObservationsThrough,
                          observation.event.sequence <= ignored {
                        signal = await iterator.next()
                        signalIterator = iterator
                    }
                    consume(signal)
                case .finish(let outcome):
                    return wait.waitReceipt(
                        for: step,
                        state: state,
                        start: start,
                        success: outcome == .matched
                    )
                }
            }
        }

        private func applyCancellation() {
            guard Task.isCancelled else { return }
            guard case .finish = effect else {
                effect = lifecycle.send(.cancelled).predicateWaitEffect
                return
            }
        }

        private func settleVisible(_ budget: PredicateWaitVisibleBudget) async {
            let matched = evaluate(
                await wait.settleVisible(budget.deadline(overall: deadline)),
                lifecycleState: lifecycle.state
            )
            effect = lifecycle.send(.evaluated(matched: matched)).predicateWaitEffect
        }

        private func runDiscovery(
            _ budget: PredicateWaitDiscoveryBudget
        ) async -> AsyncStream<PredicateWaitLifecycleSignal>? {
            let discoveryState = lifecycle.state
            let discoveryDeadline = budget.deadline(overall: deadline)
            var matched = false
            var evaluatedSequence: SettledObservationSequence?
            let event: SettledSemanticObservationEvent?
            if let waitTarget = step.predicate.waitTarget,
               let revealed = await wait.revealTarget(waitTarget, discoveryDeadline) {
                evaluatedSequence = revealed.sequence
                matched = evaluate(revealed, lifecycleState: discoveryState)
                event = revealed
            } else {
                event = await wait.discover(step.predicate.waitTarget, discoveryDeadline) { event in
                    evaluatedSequence = event.sequence
                    let eventMatched = self.evaluate(event, lifecycleState: discoveryState)
                    matched = matched || eventMatched
                    return eventMatched
                }
            }
            if !matched, event?.sequence != evaluatedSequence {
                matched = evaluate(event, lifecycleState: discoveryState)
            }
            let signals = prepareObservationPolling(
                after: event,
                discoveryState: discoveryState,
                matched: matched
            )
            effect = lifecycle.send(.evaluated(matched: matched)).predicateWaitEffect
            return signals
        }

        private func prepareObservationPolling(
            after event: SettledSemanticObservationEvent?,
            discoveryState: PredicateWaitLifecycleState,
            matched: Bool
        ) -> AsyncStream<PredicateWaitLifecycleSignal>? {
            if discoveryState == .initialDiscovery, !matched {
                if let event {
                    onReadyToPoll?(event.sequence)
                }
                if let observations = wait.observationEntries(wait.latestObservationCursor()) {
                    return predicateWaitLifecycleSignals(
                        observations: observations,
                        timeout: deadline.remainingSeconds()
                    )
                }
            } else if discoveryState == .triggeredDiscovery {
                ignoreObservationsThrough = wait.latestObservationCursor()?.sequence
            }
            return nil
        }

        private func consume(_ signal: PredicateWaitLifecycleSignal?) {
            switch signal {
            case .observation(let observation):
                ignoreObservationsThrough = nil
                let matched = evaluate(observation.event, lifecycleState: lifecycle.state)
                effect = lifecycle.send(.observation(matched: matched)).predicateWaitEffect
            case .deadlineReached:
                effect = lifecycle.send(.deadlineReached).predicateWaitEffect
            case nil:
                effect = lifecycle.send(Task.isCancelled ? .cancelled : .deadlineReached).predicateWaitEffect
            }
        }

        private func evaluate(
            _ event: SettledSemanticObservationEvent?,
            lifecycleState: PredicateWaitLifecycleState
        ) -> Bool {
            guard let event else { return false }
            let reduced = wait.reduceObservation(
                wait.semanticObservation(event),
                predicate: step.predicate,
                predicateExpression: step.predicateExpression,
                baselineSeed: baselineSeed(for: lifecycleState),
                stream: stream
            )
            stream = reduced.state
            let decision = reducer.decision(
                after: .observation(Snapshot(reduced.reduction)),
                reducing: state,
                timedOutWhenUnmatched: false
            )
            state = decision.state
            return decision.isSatisfied
        }

        private func baselineSeed(
            for lifecycleState: PredicateWaitLifecycleState
        ) -> PredicateObservationBaselineSeed {
            guard stream.observationBaseline == nil else { return .preserve }
            switch changeBaseline {
            case .supplied(let supplied):
                return supplied.map(PredicateObservationBaselineSeed.supplied) ?? .preserve
            case .establishFromFirstObservation:
                return lifecycleState == .initialVisible ? .preserve : .currentObservation
            }
        }
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

}

private extension ResolvedAccessibilityPredicate {
    var waitTarget: ResolvedAccessibilityTarget? {
        switch core {
        case .presence(let presence):
            return presence.target
        case .changed(.screen(let assertions)):
            guard assertions.count == 1,
                  case .presence(let presence) = assertions[0]
            else { return nil }
            return presence.target
        case .changed(.elements(let assertions)):
            guard assertions.count == 1 else { return nil }
            return assertions[0].target
        case .announcement, .noChange:
            return nil
        }
    }
}

private extension PresencePredicateCore where Phase == ResolvedAccessibilityPredicatePhase {
    var target: ResolvedAccessibilityTarget {
        switch self {
        case .exists(let target), .missing(let target):
            return target
        }
    }
}

private extension ElementAssertionCore where Phase == ResolvedAccessibilityPredicatePhase {
    var target: ResolvedAccessibilityTarget {
        switch self {
        case .presence(let presence):
            return presence.target
        case .appeared(let target), .disappeared(let target), .updated(let target, _):
            return target
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
