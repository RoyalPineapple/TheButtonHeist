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

@MainActor internal final class PredicateWait {
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

    private let stash: TheStash
    private let navigation: Navigation
    private let postActionObservation: PostActionObservation
    private var heistAnnouncementCursor: AccessibilityNotificationCursor = .origin

    internal init(
        stash: TheStash,
        navigation: Navigation,
        postActionObservation: PostActionObservation
    ) {
        self.stash = stash
        self.navigation = navigation
        self.postActionObservation = postActionObservation
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
                let stream = wait.stash.semanticObservationStream
                if let cursor = stream.latestObservationCursor(scope: .visible) {
                    return stream.observationEntries(after: cursor, scope: .visible)
                }
                return stream.observationEntries(scope: .visible)
            } else if discoveryPhase == .triggeredDiscovery {
                ignoreObservationsThrough = wait.stash.semanticObservationStream
                    .latestObservationCursor(scope: .visible)?
                    .sequence
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
                wait.postActionObservation.semanticObservation(from: event),
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
        let window = stash.semanticObservationStream.observationWindow(
            from: baseline,
            through: observation.event
        )
        return stream.reducing(
            observation,
            predicate: predicate,
            predicateExpression: predicateExpression,
            baselineSeed: .supplied(baseline),
            observationWindow: window
        )
    }

    internal func resetAnnouncementWaitCursorForHeist(
        to cursor: AccessibilityNotificationCursor
    ) {
        heistAnnouncementCursor = cursor
    }

    internal func announcementCursor(
        _ strategy: AnnouncementWaitCursorStrategy
    ) -> AccessibilityNotificationCursor {
        switch strategy {
        case .futureOnly:
            stash.accessibilityNotifications.cursor()
        case .heistScoped:
            heistAnnouncementCursor
        }
    }

    internal func waitForAnnouncement(
        _ cursor: AccessibilityNotificationCursor,
        _ predicate: ResolvedAnnouncementPredicate,
        _ timeout: Double
    ) async -> CapturedAnnouncement? {
        let announcement = await stash.accessibilityNotifications.waitForAnnouncement(
            after: cursor,
            matching: predicate,
            timeout: timeout
        )
        if let announcement {
            heistAnnouncementCursor = AccessibilityNotificationCursor(
                sequence: max(heistAnnouncementCursor.sequence, announcement.sequence)
            )
        }
        return announcement
    }

    internal func latestEvent() -> SettledSemanticObservationEvent? { stash.latestSettledSemanticObservationEvent }

    internal func latestSettleFailure() -> String? { stash.latestSemanticObservationFailureDiagnostic() }

    internal func presenceTimeoutMessage(
        _ predicate: ResolvedAccessibilityPredicate,
        _ elapsed: String
    ) -> String? {
        stash.presenceWaitTimeoutMessage(for: predicate, elapsed: elapsed)
    }

    private func settleVisible(
        _ deadline: SemanticObservationDeadline
    ) async -> SettledSemanticObservationEvent? {
        if !stash.latestSettledSemanticObservationInvalidated,
           let current = stash.latestSettledSemanticObservationEvent {
            return current
        }
        guard deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) else { return nil }
        guard let evidence = await stash.observeVisibleSemanticEvidence(
            timeout: min(
                Double(SettleSession.defaultTimeoutMs) / 1_000,
                deadline.remainingSeconds()
            )
        ),
        let event = stash.latestSettledSemanticObservationEvent,
        event.sequence == evidence.settledObservationSequence
        else { return nil }
        return event
    }

    private func revealTarget(
        _ target: ResolvedAccessibilityTarget,
        _ deadline: SemanticObservationDeadline?
    ) async -> SettledSemanticObservationEvent? {
        guard target.isElementTarget,
              stash.resolveTarget(target).resolved != nil
        else { return nil }
        if let deadline,
           !deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) {
            return nil
        }
        switch await navigation.elementInflation.inflate(
            for: target,
            method: .scrollToVisible,
        ) {
        case .inflated:
            return stash.latestSettledSemanticObservationEvent
        case .failed:
            return nil
        }
    }

    private func discover(
        _ target: ResolvedAccessibilityTarget?,
        _ deadline: SemanticObservationDeadline?,
        _ observer: @escaping @MainActor (SettledSemanticObservationEvent) -> Bool
    ) async -> SettledSemanticObservationEvent? {
        if let deadline,
           !deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) {
            return nil
        }
        let baseline = Navigation.ExplorationBaseline.currentViewport(
            stash.visibleExplorationBaseline(from: stash.latestObservation)
        )
        guard let exploration = await navigation.exploreScreen(
            target: target,
            baseline: baseline,
            exitPosition: .origin,
            deadline: deadline,
            onObservation: { event in
                observer(event) ? .finish : .continue
            },
        ) else { return nil }
        return exploration.event
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
