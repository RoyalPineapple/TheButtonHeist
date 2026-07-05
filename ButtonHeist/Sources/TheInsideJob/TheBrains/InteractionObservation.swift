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
    private let predicateWait: PredicateWait

    init(stash: TheStash, postActionObservation: PostActionObservation) {
        self.stash = stash
        self.postActionObservation = postActionObservation
        self.predicateWait = PredicateWait(
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
            presenceTimeoutMessage: { predicate, elapsed in
                stash.presenceWaitTimeoutMessage(for: predicate, elapsed: elapsed)
            }
        )
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
        let settleEvidence = await postActionObservation.settleEvidence(
            before: before,
            commitScope: postActionCommitScope,
            outcome: settleOutcome,
            notificationWindow: notificationWindow
        )
        let finalEvidenceStart = CFAbsoluteTimeGetCurrent()
        let observationOutcome = await postActionObservation.observationOutcome(
            before: before,
            settleEvidence: settleEvidence
        )
        let finalSemanticEvidenceMs = elapsedMilliseconds(since: finalEvidenceStart)

        let receiptStart = CFAbsoluteTimeGetCurrent()
        let result = ActionResult(
            postActionMethod: method,
            outcome: outcome,
            message: message,
            before: before,
            settleEvidence: settleEvidence,
            observationOutcome: observationOutcome
        )
        return result.withTiming(ActionPerformanceTiming(
            settleMs: settleEvidence.timeMs,
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
        allowsTransitionFinalStateWarning: Bool = true
    ) async -> HeistWaitReceipt {
        await predicateWait.wait(
            for: step,
            initialTrace: initialTrace,
            after: sequence,
            allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning
        )
    }

    func waitForPredicate(
        _ step: ResolvedWaitStep,
        initialTrace: AccessibilityTrace? = nil,
        after sequence: SettledObservationSequence? = nil,
        allowsTransitionFinalStateWarning: Bool = true
    ) async -> HeistWaitReceipt {
        await predicateWait.wait(
            for: step,
            initialTrace: initialTrace,
            after: sequence,
            allowsTransitionFinalStateWarning: allowsTransitionFinalStateWarning
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
