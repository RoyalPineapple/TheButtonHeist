#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans
import TheScore

struct ActionPayloadEvidence {
    let committedBaseline: ActionEvidenceProjector.Baseline
    let resolvedElementId: HeistId?
}

@MainActor
final class InteractionCoordinator {
    private static let defaultVisibleStateTimeout = Double(SettleSession.defaultTimeoutMs) / 1_000

    private let vault: TheVault
    private let actionEvidenceProjector: ActionEvidenceProjector
    private let predicateWait: PredicateWait

    init(
        vault: TheVault,
        navigation: Navigation,
        actionEvidenceProjector: ActionEvidenceProjector
    ) {
        self.vault = vault
        self.actionEvidenceProjector = actionEvidenceProjector
        self.predicateWait = PredicateWait(
            vault: vault,
            navigation: navigation,
            actionEvidenceProjector: actionEvidenceProjector
        )
    }

    func resetAnnouncementWaitCursorForHeist(to cursor: AccessibilityNotificationCursor) {
        predicateWait.resetAnnouncementWaitCursorForHeist(to: cursor)
    }

    func admittedBaseline(
        scope: SemanticObservationScope = .visible,
        timeout: Double? = InteractionCoordinator.defaultVisibleStateTimeout
    ) async -> ActionEvidenceProjector.Baseline? {
        switch scope {
        case .visible:
            return await admittedVisibleBaseline(timeout: timeout)
        case .discovery:
            return await settledEvidence(scope: .discovery, after: nil, timeout: timeout)?.baseline
        }
    }

    func settledCapture(
        scope: SemanticObservationScope?,
        timeout: Double = InteractionCoordinator.defaultVisibleStateTimeout
    ) async -> SettledCapture? {
        guard let scope else { return nil }
        return await vault.semanticObservationStream.settledEvent(
            scope: scope,
            after: nil,
            timeout: timeout
        )?.settledCapture
    }

    func admittedVisibleBaseline(timeout: Double? = InteractionCoordinator.defaultVisibleStateTimeout) async -> ActionEvidenceProjector.Baseline? {
        guard let admittedObservation = await vault.semanticObservationStream.admittedVisibleObservation(
            timeout: timeout
        ) else { return nil }
        return actionEvidenceProjector.projectBaseline(from: admittedObservation)
    }

    func settledEvidence(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledObservationEvidence? {
        let event = await vault.semanticObservationStream.settledEvent(
            scope: scope,
            after: sequence,
            timeout: timeout ?? SemanticObservationTiming.defaultTimeout
        )

        guard let event else { return nil }
        return actionEvidenceProjector.projectSettledEvidence(from: event)
    }

    func settleAfterAction(
        dispatchResult: TheSafecracker.ActionDispatchResult,
        afterStateValue: ((ActionPayloadEvidence) -> String?)? = nil,
        before: ActionEvidenceProjector.Baseline,
        postActionCommitScope: SemanticObservationScope = .visible,
        settleResult: SettleSession.Result? = nil,
        notificationWindow: AccessibilityNotificationScopeLease? = nil
    ) async -> ActionResult {
        let observationSettlement = await vault.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            commitScope: postActionCommitScope,
            settleResult: settleResult,
            notificationWindow: notificationWindow
        )
        let finalEvidenceStart = CFAbsoluteTimeGetCurrent()
        let actionEvidence = actionEvidenceProjector.projectResult(
            before: before,
            observation: observationSettlement
        )
        let finalSemanticEvidenceMs = elapsedMilliseconds(since: finalEvidenceStart)

        let resultAssemblyStart = CFAbsoluteTimeGetCurrent()
        let result = ActionResult(
            dispatchResult: dispatchResult,
            afterStateValue: afterStateValue,
            settledObservation: actionEvidence
        )
        return result.withTiming(ActionPerformanceTiming(
            finalSemanticEvidenceMs: finalSemanticEvidenceMs,
            resultAssemblyMs: elapsedMilliseconds(since: resultAssemblyStart)
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
        startedAt: CFAbsoluteTime? = nil
    ) async -> HeistWaitResult {
        let baselineSource: PredicateChangeBaselineSource
        switch (changeBaseline, baselineSequence) {
        case (.establishFromFirstObservation, .some(let sequence)):
            baselineSource = .supplied(vault.semanticObservationStream.settledCapture(
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
            onReadyToPoll: onReadyToPoll,
            startedAt: startedAt
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
