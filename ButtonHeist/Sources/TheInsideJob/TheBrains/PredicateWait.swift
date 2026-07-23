#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

import TheScore

internal enum PredicateObservationDiagnostics {
    internal static let changePredicateNeedsFutureObservationMessage = "change predicate requires future settled observation after baseline"
}

internal enum PredicateChangeBaselineSource: Sendable, Equatable {
    case establishFromFirstObservation
    case supplied(Observation.Moment?)
}

private struct PredicateWaitDiscoveryResult<Evidence>
where Evidence: Sendable & Equatable {
    let evaluation: PredicateWaitEvaluation<Evidence>
    let event: Observation.SnapshotEvent?
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
        ) async -> PredicateWaitEvaluation<Evidence>
        let result: @MainActor (
            PredicateWaitOutcome,
            SemanticObservationDeadline,
            Evidence
        ) async -> Result
    }

    internal let vault: TheVault
    private let navigation: Navigation
    internal let actionEvidenceProjector: ActionEvidenceProjector
    internal var observeScheduledEffect: @MainActor (ScheduledEffect) -> Void = { _ in }

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
        actionExpectationContext: ActionExpectationContext? = nil,
        onReadyToPoll: ReadyToPoll? = nil,
        startedAt: RuntimeElapsed.Instant? = nil
    ) async -> HeistWaitResult {
        let start = startedAt ?? RuntimeElapsed.now
        if case .announcement(let announcement) = step.predicate.core {
            return await waitForAnnouncementPredicate(
                announcement,
                step: step,
                initialTrace: actionExpectationContext == nil ? initialTrace : nil,
                start: start,
                timeout: step.timeout,
                cursor: actionExpectationContext?.announcementCursor
                    ?? vault.accessibilityNotifications.cursor(),
                isActionExpectation: actionExpectationContext != nil
            )
        }

        var replayedEvidence: LifecycleEvidence?
        if let contextReduction = await reduceActionContext(
            for: step,
            context: actionExpectationContext
        ) {
            switch contextReduction {
            case .matched(let reduction):
                return await waitResult(
                    for: step,
                    trace: reduction.trace,
                    observationSummary: reduction.observation.summary,
                    expectation: reduction.expectation,
                    start: start,
                    success: true,
                    baseline: reduction.changeBaseline,
                    eventsSinceBaseline: reduction.eventsSinceBaseline,
                    observationMoment: reduction.observation.event.moment
                )
            case .unmatched(let evidence):
                replayedEvidence = evidence
            case .empty:
                break
            case .unavailable(let error):
                return unavailableActionContextResult(
                    for: step,
                    context: actionExpectationContext,
                    error: error
                )
            }
        }

        if replayedEvidence == nil,
           let traceEvaluation = initialTraceChangeEvaluation(
            for: step,
            initialTrace: initialTrace
        ), traceEvaluation.met {
            return await waitResult(
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
                start: start,
                replayedEvidence: replayedEvidence
            ),
            onReadyToPoll: onReadyToPoll
        )
    }

    private func unavailableActionContextResult(
        for step: ResolvedWaitRuntimeInput,
        context: ActionExpectationContext?,
        error: Observation.LogReadError
    ) -> HeistWaitResult {
        let message = "Action expectation observation history unavailable: \(error)"
        let traceEvidence = context.flatMap {
            AccessibilityTraceEvidence(
                trace: AccessibilityTrace(captures: [$0.preActionMoment.capture]),
                completeness: .incomplete
            )
        }
        return .failed(
            failureKind: .actionFailed,
            message: message,
            traceEvidence: traceEvidence,
            expectation: ExpectationResult.Unmet(
                predicate: step.predicateExpression,
                actual: message
            )
        )
    }

    private func changeProjection(
        for step: ResolvedWaitRuntimeInput,
        changeBaseline: PredicateChangeBaselineSource,
        start: RuntimeElapsed.Instant,
        replayedEvidence: LifecycleEvidence?
    ) -> ExecutionProjection<HeistWaitResult, LifecycleEvidence> {
        ExecutionProjection(
            target: step.predicate.waitTarget,
            continuesAfterInitialMiss: true,
            initialEvidence: replayedEvidence ?? LifecycleEvidence(
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
                        isInitialVisible ? .currentObservation : .preserve
                    }
                }
                let reduced = await self.reduceObservation(
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
                await self.waitResult(
                    for: step,
                    trace: evidence.lastTrace,
                    observationSummary: evidence.lastObservationSummary,
                    expectation: evidence.evaluation,
                    start: start,
                    success: outcome == .matched,
                    baseline: evidence.changeBaseline,
                    eventsSinceBaseline: evidence.eventsSinceBaseline,
                    observationMoment: evidence.observedMoment,
                    timeoutMismatchMessage: outcome == .timedOut
                        ? evidence.timeoutMismatchMessage
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
            let admittedEvent = await wait.latestAdmittedVisibleEvent()
            var evaluation = await evaluate(
                admittedEvent,
                isInitialVisible: true,
                evidence: projection.initialEvidence
            )
            if evaluation.matched {
                return await finish(.matched, evidence: evaluation.evidence)
            }
            if Task.isCancelled {
                return await finish(.cancelled, evidence: evaluation.evidence)
            }
            guard projection.continuesAfterInitialMiss,
                  deadline.hasTimeRemaining(at: RuntimeElapsed.now) else {
                return await finish(.timedOut, evidence: evaluation.evidence)
            }

            var latestEvaluatedSequence = admittedEvent?.sequence
            if admittedEvent == nil {
                let settledEvent = await wait.settleVisible(deadline)
                latestEvaluatedSequence = settledEvent?.sequence
                evaluation = await evaluate(
                    settledEvent,
                    isInitialVisible: true,
                    evidence: evaluation.evidence
                )
                if evaluation.matched {
                    return await finish(.matched, evidence: evaluation.evidence)
                }
                if Task.isCancelled {
                    return await finish(.cancelled, evidence: evaluation.evidence)
                }
                guard deadline.hasTimeRemaining(at: RuntimeElapsed.now) else {
                    return await finish(.timedOut, evidence: evaluation.evidence)
                }
            }

            let initialDiscovery = await runDiscovery(
                deadline: deadline,
                after: latestEvaluatedSequence,
                evidence: evaluation.evidence
            )
            recordTerminalVerificationCost(since: initialRouteStart)
            evaluation = initialDiscovery.evaluation
            if evaluation.matched {
                return await finish(.matched, evidence: evaluation.evidence)
            }
            if Task.isCancelled {
                return await finish(.cancelled, evidence: evaluation.evidence)
            }
            if let event = initialDiscovery.event {
                onReadyToPoll?(event.sequence)
            }

            let stream = wait.vault.semanticObservationStream
            var moment = await stream.latestCommittedObservationMoment(scope: .visible)
            while true {
                wait.observeScheduledEffect(.observationWait)
                switch await stream.waitForObservation(
                    since: moment,
                    scope: .visible,
                    deadline: deadline.reserving(terminalVerificationReserveSeconds)
                ) {
                case .observation(let observation):
                    moment = observation.moment
                    evaluation = await evaluate(
                        observation,
                        isInitialVisible: false,
                        evidence: evaluation.evidence
                    )
                    if evaluation.matched {
                        return await finish(.matched, evidence: evaluation.evidence)
                    }
                    if Task.isCancelled {
                        return await finish(.cancelled, evidence: evaluation.evidence)
                    }

                    let discoveryStart = RuntimeElapsed.now
                    let discovery = await runDiscovery(
                        deadline: deadline,
                        after: observation.sequence,
                        evidence: evaluation.evidence
                    )
                    recordTerminalVerificationCost(since: discoveryStart)
                    evaluation = discovery.evaluation
                    if evaluation.matched {
                        return await finish(.matched, evidence: evaluation.evidence)
                    }
                    if Task.isCancelled {
                        return await finish(.cancelled, evidence: evaluation.evidence)
                    }
                    moment = await stream.latestCommittedObservationMoment(scope: .visible) ?? moment
                case .deadlineReached, .unavailable:
                    return await terminalVerification(evidence: evaluation.evidence)
                case .cycleCompleted:
                    continue
                case .cancelled:
                    return await finish(.cancelled, evidence: evaluation.evidence)
                }
            }
        }

        private func terminalVerification(evidence: Evidence) async -> Result {
            let settledEvent = await wait.settleVisible(deadline)
            let visibleEvaluation = await evaluate(
                settledEvent,
                isInitialVisible: false,
                evidence: evidence
            )
            if visibleEvaluation.matched {
                return await finish(.matched, evidence: visibleEvaluation.evidence)
            }
            if Task.isCancelled {
                return await finish(.cancelled, evidence: visibleEvaluation.evidence)
            }

            let discovery = await runDiscovery(
                deadline: deadline,
                after: settledEvent?.sequence,
                evidence: visibleEvaluation.evidence
            )
            if discovery.evaluation.matched {
                return await finish(.matched, evidence: discovery.evaluation.evidence)
            }
            return await finish(
                Task.isCancelled ? .cancelled : .timedOut,
                evidence: discovery.evaluation.evidence
            )
        }

        private func runDiscovery(
            deadline: SemanticObservationDeadline,
            after sequence: SettledObservationSequence?,
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
            var lastEvaluatedSequence = sequence
            let event: Observation.SnapshotEvent?
            if let waitTarget = projection.target,
               let revealed = await wait.revealTarget(waitTarget, deadline) {
                if revealed.sequence != lastEvaluatedSequence {
                    lastEvaluatedSequence = revealed.sequence
                    evaluation = await evaluate(
                        revealed,
                        isInitialVisible: false,
                        evidence: evaluation.evidence
                    )
                }
                event = revealed
            } else {
                event = await wait.discover(projection.target, deadline) { event in
                    guard !evaluation.matched,
                          event.sequence != lastEvaluatedSequence else { return evaluation.matched }
                    lastEvaluatedSequence = event.sequence
                    evaluation = await self.evaluate(
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
                evaluation = await evaluate(
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
            _ event: Observation.SnapshotEvent?,
            isInitialVisible: Bool,
            evidence: Evidence
        ) async -> PredicateWaitEvaluation<Evidence> {
            guard let event else {
                return PredicateWaitEvaluation(evidence: evidence, matched: false)
            }
            return await projection.evaluate(
                wait.actionEvidenceProjector.projectSettledEvidence(from: event),
                isInitialVisible,
                evidence
            )
        }

        private func finish(_ outcome: PredicateWaitOutcome, evidence: Evidence) async -> Result {
            await projection.result(outcome, deadline, evidence)
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
    ) async -> PredicateObservationStreamReduction {
        let seeded = stream.seedingBaseline(
            baselineSeed,
            from: observation.event,
            when: predicate.requiresChangeBaseline
        )
        let eventsSinceBaseline: Observation.EventsSince?
        if let baseline = seeded.observationBaseline {
            eventsSinceBaseline = await vault.semanticObservationStream.storeOwner.readLog {
                $0.events(since: baseline)
            }
        } else {
            eventsSinceBaseline = nil
        }
        return seeded.reducing(
            observation,
            predicate: predicate,
            predicateExpression: predicateExpression,
            eventsSinceBaseline: eventsSinceBaseline
        )
    }

    internal func latestCommittedEvent() async -> Observation.SnapshotEvent? {
        await vault.semanticObservationStream.latestCommittedEvent()
    }

    private func latestAdmittedVisibleEvent() async -> Observation.SnapshotEvent? {
        await vault.semanticObservationStream.storeOwner.admittedObservation(
            scope: .visible,
            after: nil
        )?.event
    }

    internal func latestSettleFailure() async -> String? {
        await vault.semanticObservationStream.latestSettleFailureDiagnostic()
    }

    /// Publishes discovery observations while settlement exclusively evaluates them.
    internal func publishStandaloneWaitDiscovery(
        target: ResolvedAccessibilityTarget?,
        deadline: SemanticObservationDeadline,
        control: Settlement.ObservationEffectControl
    ) async {
        observeScheduledEffect(.discovery)
        _ = await discover(target, deadline) { _ in control.stopRequested }
    }

    internal func presenceTimeoutMessage(
        _ predicate: ResolvedAccessibilityPredicate,
        _ elapsed: String
    ) -> String? {
        vault.presenceWaitTimeoutMessage(for: predicate, elapsed: elapsed)
    }

    private func settleVisible(
        _ deadline: SemanticObservationDeadline
    ) async -> Observation.SnapshotEvent? {
        if let current = await vault.semanticObservationStream.admittedObservation(
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
    ) async -> Observation.SnapshotEvent? {
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
            return await vault.semanticObservationStream.latestCommittedEvent()
        case .failed:
            return nil
        }
    }

    private func discover(
        _ target: ResolvedAccessibilityTarget?,
        _ deadline: SemanticObservationDeadline,
        _ observer: @escaping @MainActor (Observation.SnapshotEvent) async -> Bool
    ) async -> Observation.SnapshotEvent? {
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
                await observer(event) ? .goalSatisfied : .continue
            },
        ) else { return nil }
        return exploration.event
    }

}

extension ResolvedAccessibilityPredicate {
    internal var waitTarget: ResolvedAccessibilityTarget? {
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
