#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

struct PostActionPayloadContext {
    let baseline: PostActionObservation.ObservationBaseline
    let resolvedElementId: HeistId?
}

@MainActor
final class InteractionObservation {
    private static let defaultVisibleStateTimeout = Double(SettleSession.defaultTimeoutMs) / 1_000

    private let stash: TheStash
    private let postActionObservation: PostActionObservation
    private let predicateWait: PredicateWait

    init(
        stash: TheStash,
        navigation: Navigation,
        postActionObservation: PostActionObservation
    ) {
        self.stash = stash
        self.postActionObservation = postActionObservation
        self.predicateWait = PredicateWait(
            stash: stash,
            navigation: navigation,
            postActionObservation: postActionObservation
        )
    }

    func resetAnnouncementWaitCursorForHeist(to cursor: AccessibilityNotificationCursor) {
        predicateWait.resetAnnouncementWaitCursorForHeist(to: cursor)
    }

    func prepareBeforeState(
        scope: SemanticObservationScope = .visible,
        timeout: Double? = InteractionObservation.defaultVisibleStateTimeout
    ) async -> PostActionObservation.ObservationBaseline? {
        switch scope {
        case .visible:
            return await observeVisibleState(timeout: timeout)
        case .discovery:
            return await observeSemanticState(scope: .discovery, after: nil, timeout: timeout)?.baseline
        }
    }

    func captureSettledBaseline(
        scope: SemanticObservationScope?,
        timeout: Double = InteractionObservation.defaultVisibleStateTimeout
    ) async -> SettledCapture? {
        guard let scope else { return nil }
        return await stash.semanticObservationStream.settledEvent(
            scope: scope,
            after: nil,
            timeout: timeout
        )?.settledCapture
    }

    func observeVisibleState(timeout: Double? = InteractionObservation.defaultVisibleStateTimeout) async -> PostActionObservation.ObservationBaseline? {
        baselineState(from: await stash.semanticObservationStream.visibleEvidence(timeout: timeout))
    }

    func baselineState(from evidence: ViewportObservationEvidence?) -> PostActionObservation.ObservationBaseline? {
        guard let evidence else { return nil }
        return postActionObservation.captureSemanticState(from: evidence)
    }

    func observeSemanticState(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledObservationEvidence? {
        let event = await stash.semanticObservationStream.settledEvent(
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
        before: PostActionObservation.ObservationBaseline,
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
        return await predicateWait.wait(
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
        await predicateWait.selectPredicateCase(cases, timeout: rawTimeout)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
