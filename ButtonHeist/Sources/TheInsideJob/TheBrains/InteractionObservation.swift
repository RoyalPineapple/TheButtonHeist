#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

/// Owns the before/body/after observation contract for executable interactions.
///
/// It coordinates settled semantic evidence. It does not choose command
/// payloads, resolve element inflation, choose durable selectors, or format reports.
@MainActor
final class InteractionObservation {
    private static let defaultVisibleStateTimeout = Double(SettleSession.defaultTimeoutMs) / 1_000

    private let stash: TheStash
    private let postActionObservation: PostActionObservation
    private var heistAnnouncementCursor: AccessibilityNotificationCursor = .origin
    private var predicateWait: PredicateWait {
        makePredicateWait()
    }

    init(stash: TheStash, postActionObservation: PostActionObservation) {
        self.stash = stash
        self.postActionObservation = postActionObservation
    }

    private func makePredicateWait() -> PredicateWait {
        let stash = self.stash
        let postActionObservation = self.postActionObservation
        return PredicateWait(
            observeEvent: { scope, sequence, timeout in
                await stash.observeSettledSemanticObservation(
                    scope: scope,
                    after: sequence,
                    timeout: timeout
                )
            },
            latestEvent: {
                stash.latestSettledSemanticObservationEvent
            },
            latestSettleFailure: {
                stash.latestSemanticObservationFailureDiagnostic()
            },
            semanticObservation: { event in
                postActionObservation.semanticObservation(from: event)
            },
            buildObservationWindow: { baseline, event, projection in
                stash.semanticObservationStream.observationWindow(
                    from: baseline,
                    through: event,
                    projection: projection
                )
            },
            presenceTimeoutMessage: { predicate, elapsed in
                stash.presenceWaitTimeoutMessage(for: predicate, elapsed: elapsed)
            },
            announcementCursor: { [weak self] strategy in
                switch strategy {
                case .futureOnly:
                    return stash.accessibilityNotifications.announcementCursor()
                case .heistScoped:
                    return self?.heistAnnouncementCursor ?? .origin
                }
            },
            waitForAnnouncement: { [weak self] cursor, predicate, timeout in
                let announcement = await stash.accessibilityNotifications.waitForAnnouncement(
                    after: cursor,
                    matching: predicate,
                    timeout: timeout
                )
                if let announcement, let self {
                    self.heistAnnouncementCursor = AccessibilityNotificationCursor(
                        sequence: max(self.heistAnnouncementCursor.sequence, announcement.sequence)
                    )
                }
                return announcement
            }
        )
    }

    func resetAnnouncementWaitCursorForHeist() {
        heistAnnouncementCursor = .origin
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
        method: ActionMethod,
        outcome: PostActionObservation.ActionOutcome,
        message: String? = nil,
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
            postActionMethod: method,
            outcome: outcome,
            message: message,
            settledObservation: settledResult
        )
        return result.withTiming(ActionPerformanceTiming(
            settleMs: settledResult.settleTimeMs,
            finalSemanticEvidenceMs: finalSemanticEvidenceMs,
            receiptGenerationMs: elapsedMilliseconds(since: receiptStart)
        ))
    }

    private func elapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    }

    func waitForPredicate(
        _ step: WaitStep,
        initialTrace: AccessibilityTrace? = nil,
        after sequence: SettledObservationSequence? = nil,
        observationPlan: WaitObservationPlan? = nil,
        allowsTransitionFinalStateWarning: Bool = true,
        announcementCursorStrategy: AnnouncementWaitCursorStrategy = .futureOnly
    ) async -> HeistWaitReceipt {
        await predicateWait.wait(
            for: step,
            initialTrace: initialTrace,
            after: sequence,
            observationPlan: observationPlan,
            allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning,
            announcementCursorStrategy: announcementCursorStrategy
        )
    }

    func waitForPredicate(
        _ step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace? = nil,
        after sequence: SettledObservationSequence? = nil,
        observationPlan: WaitObservationPlan? = nil,
        allowsTransitionFinalStateWarning: Bool = true,
        announcementCursorStrategy: AnnouncementWaitCursorStrategy = .futureOnly
    ) async -> HeistWaitReceipt {
        await predicateWait.wait(
            for: step,
            initialTrace: initialTrace,
            after: sequence,
            observationPlan: observationPlan,
            allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning,
            announcementCursorStrategy: announcementCursorStrategy
        )
    }

    func waitForPredicateCases(
        _ cases: [ResolvedPredicateCase],
        timeout rawTimeout: Double
    ) async -> HeistCaseSelectionResult {
        await PredicateCaseSelection.waitFor(
            cases,
            timeout: rawTimeout,
            observeSemanticState: { scope, sequence, timeout in
                await self.observeSemanticState(
                    scope: scope,
                    after: sequence,
                    timeout: timeout
                )
            }
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
