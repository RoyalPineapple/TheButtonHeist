#if canImport(UIKit)
#if DEBUG
import Foundation
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
}

private struct PredicateWaitDiscoveryResult<Evidence>
where Evidence: Sendable & Equatable {
    let evaluation: PredicateWaitEvaluation<Evidence>
    let event: SettledObservationEvent?
}

@MainActor internal final class PredicateWait {
    /// Called after an unmatched initial observation is reduced and before polling begins.
    internal typealias ReadyToPoll = @MainActor (SettledObservationSequence) -> Void

    internal enum StableObservationDecision: Sendable, Equatable {
        case observe(remainingSeconds: Double)
        case skip
    }

    internal enum ScheduledEffect: Sendable, Equatable {
        case discovery
        case observationWait
        case settlement
    }

    internal struct ExecutionProjection<Result, Evidence>
    where Evidence: Sendable & Equatable {
        let target: ResolvedAccessibilityTarget?
        let continuesAfterInitialMiss: Bool
        let initialEvidence: Evidence
        let evaluate: @MainActor (
            SettledObservationEvidence,
            Bool,
            Evidence
        ) -> PredicateWaitEvaluation<Evidence>
        let result: @MainActor (
            PredicateWaitOutcome,
            SemanticObservationDeadline,
            Evidence
        ) -> Result
    }

    internal let vault: TheVault
    private let navigation: Navigation
    internal let actionEvidenceProjector: ActionEvidenceProjector
    internal var observeScheduledEffect: @MainActor (ScheduledEffect) -> Void = { _ in }
    private var heistAnnouncementCursor: AccessibilityNotificationCursor = .origin

    internal init(
        vault: TheVault,
        navigation: Navigation,
        actionEvidenceProjector: ActionEvidenceProjector
    ) {
        self.vault = vault
        self.navigation = navigation
        self.actionEvidenceProjector = actionEvidenceProjector
    }

    internal func wait(
        for step: ResolvedWaitRuntimeInput,
        initialTrace: AccessibilityTrace? = nil,
        changeBaseline: PredicateChangeBaselineSource = .establishFromFirstObservation,
        announcementCursorStrategy: AnnouncementWaitCursorStrategy = .futureOnly,
        onReadyToPoll: ReadyToPoll? = nil,
        startedAt: RuntimeElapsed.Instant? = nil
    ) async -> HeistWaitResult {
        let start = startedAt ?? RuntimeElapsed.now
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
            return waitResult(
                for: step,
                trace: initialTrace,
                observationSummary: nil,
                expectation: traceEvaluation,
                start: start,
                success: true
            )
        }

        return await execute(
            start: start,
            timeout: step.timeout.seconds,
            projection: changeProjection(
                for: step,
                changeBaseline: changeBaseline,
                start: start
            ),
            onReadyToPoll: onReadyToPoll
        )
    }

    private func changeProjection(
        for step: ResolvedWaitRuntimeInput,
        changeBaseline: PredicateChangeBaselineSource,
        start: RuntimeElapsed.Instant
    ) -> ExecutionProjection<HeistWaitResult, LifecycleEvidence> {
        ExecutionProjection(
            target: step.predicate.waitTarget,
            continuesAfterInitialMiss: true,
            initialEvidence: LifecycleEvidence(
                predicate: step.predicateExpression,
                target: step.predicate.waitTarget
            ),
            evaluate: { observation, isInitialVisible, evidence in
                let baselineSeed: PredicateObservationBaselineSeed
                if evidence.stream.observationBaseline != nil {
                    baselineSeed = .preserve
                } else {
                    baselineSeed = switch changeBaseline {
                    case .supplied(let supplied):
                        supplied.map(PredicateObservationBaselineSeed.supplied) ?? .preserve
                    case .establishFromFirstObservation:
                        isInitialVisible ? .preserve : .currentObservation
                    }
                }
                let reduced = self.reduceObservation(
                    observation,
                    predicate: step.predicate,
                    predicateExpression: step.predicateExpression,
                    baselineSeed: baselineSeed,
                    stream: evidence.stream
                )
                let recorded = evidence.recording(reduced)
                return PredicateWaitEvaluation(
                    evidence: recorded,
                    matched: recorded.evaluation.met
                )
            },
            result: { outcome, _, evidence in
                self.waitResult(
                    for: step,
                    trace: evidence.lastTrace,
                    observationSummary: evidence.lastObservationSummary,
                    expectation: evidence.evaluation,
                    start: start,
                    success: outcome == .matched,
                    baseline: evidence.changeBaseline,
                    window: evidence.observationWindow,
                    observedSequence: evidence.observedSequence,
                    historicalWaitDiagnostics: outcome == .timedOut
                        ? evidence.historicalWaitDiagnostics
                        : nil
                )
            }
        )
    }

    internal func execute<Result, Evidence>(
        start: RuntimeElapsed.Instant,
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

    internal static func stableObservationDecision(
        before deadline: SemanticObservationDeadline,
        at now: RuntimeElapsed.Instant
    ) -> StableObservationDecision {
        let remainingSeconds = deadline.remainingSeconds(at: now)
        guard remainingSeconds >= SettleSession.minimumStableDurationSeconds else {
            return .skip
        }
        return .observe(remainingSeconds: remainingSeconds)
    }

    @MainActor
    private final class Execution<Result, Evidence> where Evidence: Sendable & Equatable {
        private let wait: PredicateWait
        private let deadline: SemanticObservationDeadline
        private let projection: ExecutionProjection<Result, Evidence>
        private let onReadyToPoll: ReadyToPoll?
        private var terminalVerificationReserveSeconds = 0.0

        init(
            wait: PredicateWait,
            start: RuntimeElapsed.Instant,
            timeout: Double,
            projection: ExecutionProjection<Result, Evidence>,
            onReadyToPoll: ReadyToPoll?
        ) {
            self.wait = wait
            deadline = SemanticObservationDeadline(start: start, timeoutSeconds: timeout)
            self.projection = projection
            self.onReadyToPoll = onReadyToPoll
        }

        func run() async -> Result {
            let initialRouteStart = RuntimeElapsed.now
            var evaluation = evaluate(
                await wait.settleVisible(deadline),
                isInitialVisible: true,
                evidence: projection.initialEvidence
            )
            if evaluation.matched {
                return finish(.matched, evidence: evaluation.evidence)
            }
            if Task.isCancelled {
                return finish(.cancelled, evidence: evaluation.evidence)
            }
            guard projection.continuesAfterInitialMiss else {
                return finish(.timedOut, evidence: evaluation.evidence)
            }

            let initialDiscovery = await runDiscovery(
                deadline: deadline,
                evidence: evaluation.evidence
            )
            recordTerminalVerificationCost(since: initialRouteStart)
            evaluation = initialDiscovery.evaluation
            if evaluation.matched {
                return finish(.matched, evidence: evaluation.evidence)
            }
            if Task.isCancelled {
                return finish(.cancelled, evidence: evaluation.evidence)
            }
            if let event = initialDiscovery.event {
                onReadyToPoll?(event.sequence)
            }

            let stream = wait.vault.semanticObservationStream
            var cursor = stream.latestCommittedObservationCursor(scope: .visible)
            while true {
                wait.observeScheduledEffect(.observationWait)
                switch await stream.waitForObservation(
                    after: cursor,
                    scope: .visible,
                    deadline: deadline.reserving(terminalVerificationReserveSeconds)
                ) {
                case .observation(let observation):
                    cursor = observation.cursor
                    evaluation = evaluate(
                        observation.event,
                        isInitialVisible: false,
                        evidence: evaluation.evidence
                    )
                    if evaluation.matched {
                        return finish(.matched, evidence: evaluation.evidence)
                    }
                    if Task.isCancelled {
                        return finish(.cancelled, evidence: evaluation.evidence)
                    }

                    let discoveryStart = RuntimeElapsed.now
                    let discovery = await runDiscovery(
                        deadline: deadline,
                        evidence: evaluation.evidence
                    )
                    recordTerminalVerificationCost(since: discoveryStart)
                    evaluation = discovery.evaluation
                    if evaluation.matched {
                        return finish(.matched, evidence: evaluation.evidence)
                    }
                    if Task.isCancelled {
                        return finish(.cancelled, evidence: evaluation.evidence)
                    }
                    cursor = stream.latestCommittedObservationCursor(scope: .visible) ?? cursor
                case .deadlineReached, .unavailable:
                    return await terminalVerification(evidence: evaluation.evidence)
                case .cycleCompleted:
                    continue
                case .cancelled:
                    return finish(.cancelled, evidence: evaluation.evidence)
                }
            }
        }

        private func terminalVerification(evidence: Evidence) async -> Result {
            let visibleEvaluation = evaluate(
                await wait.settleVisible(deadline),
                isInitialVisible: false,
                evidence: evidence
            )
            if visibleEvaluation.matched {
                return finish(.matched, evidence: visibleEvaluation.evidence)
            }
            if Task.isCancelled {
                return finish(.cancelled, evidence: visibleEvaluation.evidence)
            }

            let discovery = await runDiscovery(
                deadline: deadline,
                evidence: visibleEvaluation.evidence
            )
            if discovery.evaluation.matched {
                return finish(.matched, evidence: discovery.evaluation.evidence)
            }
            return finish(
                Task.isCancelled ? .cancelled : .timedOut,
                evidence: discovery.evaluation.evidence
            )
        }

        private func runDiscovery(
            deadline: SemanticObservationDeadline,
            evidence: Evidence
        ) async -> PredicateWaitDiscoveryResult<Evidence> {
            var evaluation = PredicateWaitEvaluation(
                evidence: evidence,
                matched: false
            )
            guard case .observe = PredicateWait.stableObservationDecision(
                before: deadline,
                at: RuntimeElapsed.now
            ) else {
                return PredicateWaitDiscoveryResult(evaluation: evaluation, event: nil)
            }
            wait.observeScheduledEffect(.discovery)
            var lastEvaluatedSequence: SettledObservationSequence?
            let event: SettledObservationEvent?
            if let waitTarget = projection.target,
               let revealed = await wait.revealTarget(waitTarget, deadline) {
                lastEvaluatedSequence = revealed.sequence
                evaluation = evaluate(
                    revealed,
                    isInitialVisible: false,
                    evidence: evaluation.evidence
                )
                event = revealed
            } else {
                event = await wait.discover(projection.target, deadline) { event in
                    guard !evaluation.matched,
                          event.sequence != lastEvaluatedSequence else { return evaluation.matched }
                    lastEvaluatedSequence = event.sequence
                    evaluation = self.evaluate(
                        event,
                        isInitialVisible: false,
                        evidence: evaluation.evidence
                    )
                    return evaluation.matched
                }
            }
            if !evaluation.matched,
               let event,
               event.sequence != lastEvaluatedSequence {
                evaluation = evaluate(
                    event,
                    isInitialVisible: false,
                    evidence: evaluation.evidence
                )
            }
            return PredicateWaitDiscoveryResult(
                evaluation: evaluation,
                event: event
            )
        }

        private func evaluate(
            _ event: SettledObservationEvent?,
            isInitialVisible: Bool,
            evidence: Evidence
        ) -> PredicateWaitEvaluation<Evidence> {
            guard let event else {
                return PredicateWaitEvaluation(evidence: evidence, matched: false)
            }
            return projection.evaluate(
                wait.actionEvidenceProjector.projectSettledEvidence(from: event),
                isInitialVisible,
                evidence
            )
        }

        private func finish(_ outcome: PredicateWaitOutcome, evidence: Evidence) -> Result {
            projection.result(outcome, deadline, evidence)
        }

        private func recordTerminalVerificationCost(since start: RuntimeElapsed.Instant) {
            terminalVerificationReserveSeconds = max(
                terminalVerificationReserveSeconds,
                RuntimeElapsed.seconds(since: start)
            )
        }
    }

    internal func reduceObservation(
        _ observation: SettledObservationEvidence,
        predicate: ResolvedAccessibilityPredicate,
        predicateExpression: AccessibilityPredicate,
        baselineSeed: PredicateObservationBaselineSeed,
        stream: PredicateObservationStreamState
    ) -> PredicateObservationStreamReduction {
        let seeded = stream.seedingBaseline(
            baselineSeed,
            from: observation.event,
            when: predicate.requiresChangeBaseline
        )
        let window = seeded.observationBaseline.flatMap { baseline in
            vault.semanticObservationStream.observationWindow(
                from: baseline,
                through: observation.event
            )
        }
        return seeded.reducing(
            observation,
            predicate: predicate,
            predicateExpression: predicateExpression,
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
            vault.accessibilityNotifications.cursor()
        case .heistScoped:
            heistAnnouncementCursor
        }
    }

    internal func waitForAnnouncement(
        _ cursor: AccessibilityNotificationCursor,
        _ predicate: ResolvedAnnouncementPredicate,
        _ timeout: Double
    ) async -> CapturedAnnouncement? {
        let announcement = await vault.accessibilityNotifications.waitForAnnouncement(
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

    internal func recordAnnouncementMatch(_ announcement: CapturedAnnouncement) {
        heistAnnouncementCursor = AccessibilityNotificationCursor(
            sequence: max(heistAnnouncementCursor.sequence, announcement.sequence)
        )
    }

    internal func latestCommittedEvent() -> SettledObservationEvent? { vault.semanticObservationStream.latestCommittedEvent }

    internal func latestSettleFailure() -> String? {
        vault.semanticObservationStream.latestSettleFailureDiagnostic
    }

    internal func presenceTimeoutMessage(
        _ predicate: ResolvedAccessibilityPredicate,
        _ elapsed: String
    ) -> String? {
        vault.presenceWaitTimeoutMessage(for: predicate, elapsed: elapsed)
    }

    private func settleVisible(
        _ deadline: SemanticObservationDeadline
    ) async -> SettledObservationEvent? {
        if let current = vault.semanticObservationStream.admittedObservation(
            scope: .visible,
            after: nil
        ) {
            return current.event
        }
        guard case .observe(let remainingSeconds) = Self.stableObservationDecision(
            before: deadline,
            at: RuntimeElapsed.now
        ) else { return nil }
        observeScheduledEffect(.settlement)
        return await vault.semanticObservationStream.admittedVisibleObservation(
            timeout: min(
                Double(SettleSession.defaultTimeoutMs) / 1_000,
                remainingSeconds
            )
        )?.event
    }

    private func revealTarget(
        _ target: ResolvedAccessibilityTarget,
        _ deadline: SemanticObservationDeadline
    ) async -> SettledObservationEvent? {
        guard target.isElementTarget,
              case .resolved(.element) = vault.resolveTarget(target)
        else { return nil }
        if !deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            return nil
        }
        switch await navigation.elementInflation.inflate(
            for: target,
            method: .scrollToVisible,
            operationDeadline: deadline
        ) {
        case .inflated:
            return vault.semanticObservationStream.latestCommittedEvent
        case .failed:
            return nil
        }
    }

    private func discover(
        _ target: ResolvedAccessibilityTarget?,
        _ deadline: SemanticObservationDeadline,
        _ observer: @escaping @MainActor (SettledObservationEvent) -> Bool
    ) async -> SettledObservationEvent? {
        if !deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            return nil
        }
        let baseline = Navigation.ExplorationBaseline.currentViewport(
            vault.visibleExplorationBaseline(from: vault.latestObservation)
        )
        guard let exploration = await navigation.exploreScreen(
            target: target,
            baseline: baseline,
            exitPosition: .origin,
            deadline: deadline,
            onObservation: { event in
                observer(event) ? .goalSatisfied : .continue
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
