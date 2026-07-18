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

    internal var capture: SettledCapture? {
        guard case .supplied(let capture) = self else { return nil }
        return capture
    }
}

private struct PredicateWaitDiscoveryResult<Evidence>
where Evidence: Sendable & Equatable {
    let evaluation: PredicateWaitEvaluation<Evidence>
    let event: SettledObservationEvent?
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

    private let vault: TheVault
    private let navigation: Navigation
    private let postActionObservation: PostActionObservation
    private var heistAnnouncementCursor: AccessibilityNotificationCursor = .origin

    internal init(
        vault: TheVault,
        navigation: Navigation,
        postActionObservation: PostActionObservation
    ) {
        self.vault = vault
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
                evaluate: { observation, isInitialVisible, evidence in
                    projection.evaluate(
                        observation,
                        isInitialVisible: isInitialVisible,
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
        }

        func run() async -> Result {
            var evaluation = evaluate(
                await wait.settleVisible(
                    PredicateWaitVisibleBudget.overall.deadline(overall: deadline)
                ),
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
            var cursor = stream.latestObservationCursor(scope: .visible)
            while true {
                switch await stream.waitForObservation(
                    after: cursor,
                    scope: .visible,
                    deadline: deadline
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

                    let discovery = await runDiscovery(
                        deadline: deadline,
                        evidence: evaluation.evidence
                    )
                    evaluation = discovery.evaluation
                    if evaluation.matched {
                        return finish(.matched, evidence: evaluation.evidence)
                    }
                    if Task.isCancelled {
                        return finish(.cancelled, evidence: evaluation.evidence)
                    }
                    cursor = stream.latestObservationCursor(scope: .visible) ?? cursor
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
                await wait.settleVisible(
                    PredicateWaitVisibleBudget.viewportTransition.deadline(overall: deadline)
                ),
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
                deadline: nil,
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
            deadline: SemanticObservationDeadline?,
            evidence: Evidence
        ) async -> PredicateWaitDiscoveryResult<Evidence> {
            var latestEvaluation = PredicateWaitEvaluation(
                evidence: evidence,
                matched: false
            )
            var matchedEvaluation: PredicateWaitEvaluation<Evidence>?
            var evaluatedSequence: SettledObservationSequence?
            let event: SettledObservationEvent?
            if let waitTarget = projection.target,
               let revealed = await wait.revealTarget(waitTarget, deadline) {
                evaluatedSequence = revealed.sequence
                let evaluation = evaluate(
                    revealed,
                    isInitialVisible: false,
                    evidence: latestEvaluation.evidence
                )
                latestEvaluation = evaluation
                if evaluation.matched {
                    matchedEvaluation = evaluation
                }
                event = revealed
            } else {
                event = await wait.discover(projection.target, deadline) { event in
                    evaluatedSequence = event.sequence
                    let evaluation = self.evaluate(
                        event,
                        isInitialVisible: false,
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
                    isInitialVisible: false,
                    evidence: latestEvaluation.evidence
                )
                latestEvaluation = evaluation
                if evaluation.matched {
                    matchedEvaluation = evaluation
                }
            }
            return PredicateWaitDiscoveryResult(
                evaluation: matchedEvaluation ?? latestEvaluation,
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
                wait.postActionObservation.semanticObservation(from: event),
                isInitialVisible,
                evidence
            )
        }

        private func finish(_ outcome: PredicateWaitOutcome, evidence: Evidence) -> Result {
            projection.result(outcome, deadline, evidence)
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
            _ observation: SettledObservationEvidence,
            isInitialVisible: Bool,
            evidence: LifecycleEvidence
        ) -> PredicateWaitEvaluation<LifecycleEvidence> {
            let reduced = wait.reduceObservation(
                observation,
                predicate: step.predicate,
                predicateExpression: step.predicateExpression,
                baselineSeed: baselineSeed(
                    isInitialVisible: isInitialVisible,
                    evidence: evidence
                ),
                stream: evidence.stream
            )
            let recorded = evidence.recording(reduced)
            return PredicateWaitEvaluation(
                evidence: recorded,
                matched: recorded.evaluation.met
            )
        }

        func result(
            _ outcome: PredicateWaitOutcome,
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
            isInitialVisible: Bool,
            evidence: LifecycleEvidence
        ) -> PredicateObservationBaselineSeed {
            guard evidence.stream.observationBaseline == nil else { return .preserve }
            switch changeBaseline {
            case .supplied(let supplied):
                return supplied.map(PredicateObservationBaselineSeed.supplied) ?? .preserve
            case .establishFromFirstObservation:
                return isInitialVisible ? .preserve : .currentObservation
            }
        }
    }

    internal func reduceObservation(
        _ observation: SettledObservationEvidence,
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
        let window = vault.semanticObservationStream.observationWindow(
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

    internal func latestEvent() -> SettledObservationEvent? { vault.semanticObservationStream.latestEvent }

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
        if !vault.semanticObservationStream.latestSettledObservationInvalidated,
           let current = vault.semanticObservationStream.latestEvent {
            return current
        }
        guard deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) else { return nil }
        guard let evidence = await vault.semanticObservationStream.visibleEvidence(
            timeout: min(
                Double(SettleSession.defaultTimeoutMs) / 1_000,
                deadline.remainingSeconds()
            )
        ),
        let event = vault.semanticObservationStream.latestEvent,
        event.sequence == evidence.event.sequence
        else { return nil }
        return event
    }

    private func revealTarget(
        _ target: ResolvedAccessibilityTarget,
        _ deadline: SemanticObservationDeadline?
    ) async -> SettledObservationEvent? {
        guard target.isElementTarget,
              vault.resolveTarget(target).resolved != nil
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
            return vault.semanticObservationStream.latestEvent
        case .failed:
            return nil
        }
    }

    private func discover(
        _ target: ResolvedAccessibilityTarget?,
        _ deadline: SemanticObservationDeadline?,
        _ observer: @escaping @MainActor (SettledObservationEvent) -> Bool
    ) async -> SettledObservationEvent? {
        if let deadline,
           !deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) {
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
