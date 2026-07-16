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

    internal struct ExecutionProjection<Result, Evidence>
    where Evidence: Sendable & Equatable {
        let target: ResolvedAccessibilityTarget?
        let continuesAfterInitialMiss: Bool
        let initialEvidence: Evidence
        let evaluate: @MainActor (
            HeistSemanticObservation,
            PredicateWaitLifecyclePhase,
            Evidence
        ) -> PredicateWaitLifecycleEvaluation<Evidence>
        let result: @MainActor (
            PredicateWaitLifecycleOutcome,
            SemanticObservationDeadline,
            Evidence
        ) -> Result
    }

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
        if case .announcement(let announcement) = step.predicate.core {
            return await waitForAnnouncementPredicate(
                announcement,
                step: step,
                initialTrace: initialTrace,
                start: start,
                timeout: step.timeout,
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

        let projection = PredicateExecutionProjection(
            wait: self,
            step: step,
            start: start,
            changeBaseline: changeBaseline
        )
        return await execute(
            start: start,
            timeout: step.timeout.seconds,
            projection: ExecutionProjection(
                target: step.predicate.waitTarget,
                continuesAfterInitialMiss: true,
                initialEvidence: projection.initialEvidence,
                evaluate: { observation, lifecyclePhase, evidence in
                    projection.evaluate(
                        observation,
                        lifecyclePhase: lifecyclePhase,
                        evidence: evidence
                    )
                },
                result: { outcome, _, evidence in
                    projection.result(outcome, evidence: evidence)
                }
            ),
            onReadyToPoll: onReadyToPoll
        )
    }

    internal func execute<Result, Evidence>(
        start: CFAbsoluteTime,
        timeout: Double,
        projection: ExecutionProjection<Result, Evidence>,
        onReadyToPoll: ReadyToPoll? = nil
    ) async -> Result where Evidence: Sendable & Equatable {
        await Execution(
            wait: self,
            start: start,
            timeout: timeout,
            projection: projection,
            onReadyToPoll: onReadyToPoll
        ).run()
    }

    @MainActor
    private final class Execution<Result, Evidence> where Evidence: Sendable & Equatable {
        private let wait: PredicateWait
        private let deadline: SemanticObservationDeadline
        private let projection: ExecutionProjection<Result, Evidence>
        private let onReadyToPoll: ReadyToPoll?
        private var lifecycle: StateDriver<PredicateWaitLifecycleMachine<Evidence>>
        private var effect: PredicateWaitLifecycleEffect
        private var ignoreObservationsThrough: SettledObservationSequence?

        init(
            wait: PredicateWait,
            start: CFAbsoluteTime,
            timeout: Double,
            projection: ExecutionProjection<Result, Evidence>,
            onReadyToPoll: ReadyToPoll?
        ) {
            self.wait = wait
            deadline = SemanticObservationDeadline(start: start, timeoutSeconds: timeout)
            self.projection = projection
            self.onReadyToPoll = onReadyToPoll
            lifecycle = StateDriver(
                initial: .initialVisible(projection.initialEvidence),
                machine: PredicateWaitLifecycleMachine(
                    continuesAfterInitialMiss: projection.continuesAfterInitialMiss
                )
            )
            effect = .settleVisible(.overall)
        }

        func run() async -> Result {
            var observationIterator: ObservationEntrySequence.Iterator?
            while true {
                applyCancellation()
                switch effect {
                case .settleVisible(let budget):
                    await settleVisible(budget)
                case .discover(let budget):
                    if let observations = await runDiscovery(budget) {
                        observationIterator = observations.makeAsyncIterator()
                    }
                case .awaitObservation:
                    guard let iterator = observationIterator else {
                        effect = lifecycle.send(.deadlineReached).predicateWaitEffect
                        continue
                    }
                    observationIterator = await consumeNextObservation(from: iterator)
                case .finish(let outcome):
                    return projection.result(outcome, deadline, lifecycle.state.evidence)
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
            let evaluation = evaluate(
                await wait.settleVisible(budget.deadline(overall: deadline)),
                lifecyclePhase: lifecycle.state.phase,
                evidence: lifecycle.state.evidence
            )
            effect = lifecycle.send(.evaluated(evaluation)).predicateWaitEffect
        }

        private func runDiscovery(
            _ budget: PredicateWaitDiscoveryBudget
        ) async -> ObservationEntrySequence? {
            let discoveryPhase = lifecycle.state.phase
            let discoveryDeadline = budget.deadline(overall: deadline)
            var latestEvaluation = PredicateWaitLifecycleEvaluation(
                evidence: lifecycle.state.evidence,
                matched: false
            )
            var matchedEvaluation: PredicateWaitLifecycleEvaluation<Evidence>?
            var evaluatedSequence: SettledObservationSequence?
            let event: SettledSemanticObservationEvent?
            if let waitTarget = projection.target,
               let revealed = await wait.revealTarget(waitTarget, discoveryDeadline) {
                evaluatedSequence = revealed.sequence
                let evaluation = evaluate(
                    revealed,
                    lifecyclePhase: discoveryPhase,
                    evidence: latestEvaluation.evidence
                )
                latestEvaluation = evaluation
                if evaluation.matched {
                    matchedEvaluation = evaluation
                }
                event = revealed
            } else {
                event = await wait.discover(projection.target, discoveryDeadline) { event in
                    evaluatedSequence = event.sequence
                    let evaluation = self.evaluate(
                        event,
                        lifecyclePhase: discoveryPhase,
                        evidence: latestEvaluation.evidence
                    )
                    latestEvaluation = evaluation
                    if evaluation.matched {
                        matchedEvaluation = evaluation
                    }
                    return evaluation.matched
                }
            }
            if matchedEvaluation == nil, event?.sequence != evaluatedSequence {
                let evaluation = evaluate(
                    event,
                    lifecyclePhase: discoveryPhase,
                    evidence: latestEvaluation.evidence
                )
                latestEvaluation = evaluation
                if evaluation.matched {
                    matchedEvaluation = evaluation
                }
            }
            let evaluation = matchedEvaluation ?? latestEvaluation
            let observations = prepareObservationPolling(
                after: event,
                discoveryPhase: discoveryPhase,
                matched: evaluation.matched
            )
            effect = lifecycle.send(.evaluated(evaluation)).predicateWaitEffect
            return observations
        }

        private func prepareObservationPolling(
            after event: SettledSemanticObservationEvent?,
            discoveryPhase: PredicateWaitLifecyclePhase,
            matched: Bool
        ) -> ObservationEntrySequence? {
            if discoveryPhase == .initialDiscovery, !matched {
                if let event {
                    onReadyToPoll?(event.sequence)
                }
                if let observations = wait.observationEntries(wait.latestObservationCursor()) {
                    return observations
                }
            } else if discoveryPhase == .triggeredDiscovery {
                ignoreObservationsThrough = wait.latestObservationCursor()?.sequence
            }
            return nil
        }

        private func consumeNextObservation(
            from initialIterator: ObservationEntrySequence.Iterator
        ) async -> ObservationEntrySequence.Iterator? {
            var iterator = initialIterator
            while true {
                switch await nextPredicateWaitLifecyclePoll(
                    iterator: iterator,
                    timeout: deadline.remainingSeconds()
                ) {
                case .observation(let observation, let nextIterator):
                    iterator = nextIterator
                    if let ignored = ignoreObservationsThrough,
                       observation.event.sequence <= ignored {
                        continue
                    }
                    consume(observation)
                    return nextIterator
                case .deadlineReached:
                    effect = lifecycle.send(.deadlineReached).predicateWaitEffect
                    return nil
                case .cancelled:
                    effect = lifecycle.send(.cancelled).predicateWaitEffect
                    return nil
                }
            }
        }

        private func consume(_ observation: ObservationEntry) {
            ignoreObservationsThrough = nil
            let evaluation = evaluate(
                observation.event,
                lifecyclePhase: lifecycle.state.phase,
                evidence: lifecycle.state.evidence
            )
            effect = lifecycle.send(.observation(evaluation)).predicateWaitEffect
        }

        private func evaluate(
            _ event: SettledSemanticObservationEvent?,
            lifecyclePhase: PredicateWaitLifecyclePhase,
            evidence: Evidence
        ) -> PredicateWaitLifecycleEvaluation<Evidence> {
            guard let event else {
                return PredicateWaitLifecycleEvaluation(evidence: evidence, matched: false)
            }
            return projection.evaluate(
                wait.semanticObservation(event),
                lifecyclePhase,
                evidence
            )
        }
    }

    @MainActor
    private final class PredicateExecutionProjection {
        private let wait: PredicateWait
        private let step: ResolvedWaitRuntimeInput
        private let start: CFAbsoluteTime
        private let changeBaseline: PredicateChangeBaselineSource

        var initialEvidence: LifecycleEvidence {
            LifecycleEvidence(predicate: step.predicateExpression)
        }

        init(
            wait: PredicateWait,
            step: ResolvedWaitRuntimeInput,
            start: CFAbsoluteTime,
            changeBaseline: PredicateChangeBaselineSource
        ) {
            self.wait = wait
            self.step = step
            self.start = start
            self.changeBaseline = changeBaseline
        }

        func evaluate(
            _ observation: HeistSemanticObservation,
            lifecyclePhase: PredicateWaitLifecyclePhase,
            evidence: LifecycleEvidence
        ) -> PredicateWaitLifecycleEvaluation<LifecycleEvidence> {
            let reduced = wait.reduceObservation(
                observation,
                predicate: step.predicate,
                predicateExpression: step.predicateExpression,
                baselineSeed: baselineSeed(
                    for: lifecyclePhase,
                    evidence: evidence
                ),
                stream: evidence.stream
            )
            let recorded = evidence.recording(reduced)
            return PredicateWaitLifecycleEvaluation(
                evidence: recorded,
                matched: recorded.evaluation.met
            )
        }

        func result(
            _ outcome: PredicateWaitLifecycleOutcome,
            evidence: LifecycleEvidence
        ) -> HeistWaitReceipt {
            wait.waitReceipt(
                for: step,
                evidence: evidence,
                start: start,
                success: outcome == .matched
            )
        }

        private func baselineSeed(
            for lifecyclePhase: PredicateWaitLifecyclePhase,
            evidence: LifecycleEvidence
        ) -> PredicateObservationBaselineSeed {
            guard evidence.stream.observationBaseline == nil else { return .preserve }
            switch changeBaseline {
            case .supplied(let supplied):
                return supplied.map(PredicateObservationBaselineSeed.supplied) ?? .preserve
            case .establishFromFirstObservation:
                return lifecyclePhase == .initialVisible ? .preserve : .currentObservation
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
