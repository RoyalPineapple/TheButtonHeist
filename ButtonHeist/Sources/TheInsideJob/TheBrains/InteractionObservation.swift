#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

struct PostActionPayloadContext {
    let afterState: PostActionObservation.BeforeState
    let resolvedElementId: HeistId?
}

@MainActor
final class InteractionObservation {
    private static let defaultVisibleStateTimeout = Double(SettleSession.defaultTimeoutMs) / 1_000

    private let stash: TheStash
    private let navigation: Navigation
    private let postActionObservation: PostActionObservation
    private var heistAnnouncementCursor: AccessibilityNotificationCursor = .origin
    init(
        stash: TheStash,
        navigation: Navigation,
        postActionObservation: PostActionObservation
    ) {
        self.stash = stash
        self.navigation = navigation
        self.postActionObservation = postActionObservation
    }

    private func makePredicateWait(
    ) -> PredicateWait {
        let stash = self.stash
        return PredicateWait(
            observeEvent: { scope, sequence, timeout in
                await stash.observeSettledSemanticObservation(
                    scope: scope,
                    after: sequence,
                    timeout: timeout
                )
            },
            latestEvent: { stash.latestSettledSemanticObservationEvent },
            latestSettleFailure: { stash.latestSemanticObservationFailureDiagnostic() },
            semanticObservation: { self.postActionObservation.semanticObservation(from: $0) },
            buildObservationWindow: { baseline, event in
                stash.semanticObservationStream.observationWindow(
                    from: baseline,
                    through: event
                )
            },
            presenceTimeoutMessage: { predicate, elapsed in
                stash.presenceWaitTimeoutMessage(for: predicate, elapsed: elapsed)
            },
            announcementCursor: { strategy in
                self.announcementCursor(for: strategy)
            },
            waitForAnnouncement: { cursor, predicate, timeout in
                await self.waitForAnnouncement(
                    after: cursor,
                    matching: predicate,
                    timeout: timeout
                )
            },
            settleVisible: { deadline in
                if !stash.latestSettledSemanticObservationInvalidated,
                   let current = stash.latestSettledSemanticObservationEvent {
                    return current
                }
                guard deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) else { return nil }
                guard let evidence = await stash.observeVisibleSemanticEvidence(
                    timeout: min(Self.defaultVisibleStateTimeout, deadline.remainingSeconds())
                ),
                let event = stash.latestSettledSemanticObservationEvent,
                event.sequence == evidence.settledObservationSequence
                else { return nil }
                return event
            },
            revealTarget: { target, deadline in
                guard target.isElementTarget,
                      stash.resolveTarget(target).resolved != nil
                else { return nil }
                if let deadline,
                   !deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) {
                    return nil
                }
                switch await self.navigation.elementInflation.inflate(
                    for: target,
                    method: .scrollToVisible,
                ) {
                case .inflated:
                    return stash.latestSettledSemanticObservationEvent
                case .failed:
                    return nil
                }
            },
            discover: { target, deadline, observer in
                if let deadline,
                   !deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) {
                    return nil
                }
                let baseline = Navigation.ExplorationBaseline.currentViewport(
                    stash.visibleExplorationBaseline(from: stash.latestObservation)
                )
                guard let exploration = await self.navigation.exploreScreen(
                    target: target,
                    baseline: baseline,
                    exitPosition: .origin,
                    deadline: deadline,
                    onObservation: { event in
                        observer(event) ? .finish : .continue
                    },
                ) else { return nil }
                return exploration.event
            },
            latestObservationCursor: {
                stash.semanticObservationStream.latestObservationCursor(scope: .visible)
            },
            observationEntries: { cursor in
                if let cursor {
                    return stash.semanticObservationStream.observationEntries(
                        after: cursor,
                        scope: .visible
                    )
                }
                return stash.semanticObservationStream.observationEntries(scope: .visible)
            }
        )
    }

    private func announcementCursor(
        for strategy: AnnouncementWaitCursorStrategy
    ) -> AccessibilityNotificationCursor {
        switch strategy {
        case .futureOnly:
            stash.accessibilityNotifications.cursor()
        case .heistScoped:
            heistAnnouncementCursor
        }
    }

    private func waitForAnnouncement(
        after cursor: AccessibilityNotificationCursor,
        matching predicate: ResolvedAnnouncementPredicate,
        timeout: Double
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

    func resetAnnouncementWaitCursorForHeist(to cursor: AccessibilityNotificationCursor) {
        heistAnnouncementCursor = cursor
    }

    func prepareBeforeState(
        scope: SemanticObservationScope = .visible,
        timeout: Double? = InteractionObservation.defaultVisibleStateTimeout
    ) async -> PostActionObservation.BeforeState? {
        switch scope {
        case .visible:
            return await observeVisibleState(timeout: timeout)
        case .discovery:
            return await observeSemanticState(scope: .discovery, after: nil, timeout: timeout)?.state
        }
    }

    func captureSettledBaseline(
        scope: SemanticObservationScope?,
        timeout: Double = InteractionObservation.defaultVisibleStateTimeout
    ) async -> SettledCapture? {
        guard let scope else { return nil }
        return await stash.observeSettledSemanticObservation(
            scope: scope,
            after: nil,
            timeout: timeout
        )?.settledCapture
    }

    func observeVisibleState(timeout: Double? = InteractionObservation.defaultVisibleStateTimeout) async -> PostActionObservation.BeforeState? {
        baselineState(from: await stash.observeVisibleSemanticEvidence(timeout: timeout))
    }

    func baselineState(from evidence: VisibleSemanticObservationEvidence?) -> PostActionObservation.BeforeState? {
        guard let evidence else { return nil }
        return postActionObservation.captureSemanticState(from: evidence)
    }

    func observeSemanticState(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> HeistSemanticObservation? {
        let event = await stash.observeSettledSemanticObservation(
            scope: scope,
            after: sequence,
            timeout: timeout ?? SemanticObservationTiming.defaultTimeout
        )

        guard let event else { return nil }
        return postActionObservation.semanticObservation(from: event)
    }

    func finishAfterAction(
        outcome: TheSafecracker.ActionDispatchOutcome,
        afterStatePayload: ((PostActionPayloadContext) -> ActionResultPayload?)? = nil,
        before: PostActionObservation.BeforeState,
        postActionCommitScope: SemanticObservationScope = .visible,
        settleOutcome: SettleSession.Outcome? = nil,
        notificationWindow: AccessibilityNotificationActionWindow? = nil
    ) async -> ActionResult {
        let settledObservation = await postActionObservation.settleObservation(
            before: before,
            commitScope: postActionCommitScope,
            outcome: settleOutcome,
            notificationWindow: notificationWindow
        )
        let finalEvidenceStart = CFAbsoluteTimeGetCurrent()
        let settledResult = postActionObservation.settledObservationResult(
            before: before,
            observation: settledObservation
        )
        let finalSemanticEvidenceMs = elapsedMilliseconds(since: finalEvidenceStart)

        let receiptStart = CFAbsoluteTimeGetCurrent()
        let result = ActionResult(
            outcome: outcome,
            afterStatePayload: afterStatePayload,
            settledObservation: settledResult
        )
        return result.withTiming(ActionPerformanceTiming(
            finalSemanticEvidenceMs: finalSemanticEvidenceMs,
            receiptGenerationMs: elapsedMilliseconds(since: receiptStart)
        ))
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }

    func waitForPredicate(
        _ step: ResolvedWaitRuntimeInput,
        initialTrace: AccessibilityTrace? = nil,
        baselineSequence: SettledObservationSequence? = nil,
        changeBaseline: PredicateChangeBaselineSource = .establishFromFirstObservation,
        announcementCursorStrategy: AnnouncementWaitCursorStrategy = .futureOnly,
        onReadyToPoll: PredicateWait.ReadyToPoll? = nil,
    ) async -> HeistWaitReceipt {
        let baselineSource: PredicateChangeBaselineSource
        switch (changeBaseline, baselineSequence) {
        case (.establishFromFirstObservation, .some(let sequence)):
            baselineSource = .supplied(stash.semanticObservationStream.settledCapture(
                scope: .visible,
                at: sequence
            ))
        case (.establishFromFirstObservation, .none), (.supplied, _):
            baselineSource = changeBaseline
        }
        return await makePredicateWait().wait(
            for: step,
            initialTrace: initialTrace,
            changeBaseline: baselineSource,
            announcementCursorStrategy: announcementCursorStrategy,
            onReadyToPoll: onReadyToPoll
        )
    }

    func waitForPredicateCases(
        _ cases: [ResolvedPredicateCaseRuntimeInput],
        timeout rawTimeout: Double
    ) async -> HeistCaseSelectionResult {
        await makePredicateWait().selectPredicateCase(cases, timeout: rawTimeout)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
