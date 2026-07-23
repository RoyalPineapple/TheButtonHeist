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

    func refreshedVisibleBaseline(
        timeout: Double? = InteractionCoordinator.defaultVisibleStateTimeout
    ) async -> ActionEvidenceProjector.Baseline? {
        guard let observation = await vault.semanticObservationStream.refreshedVisibleObservation(
            timeout: timeout
        ) else { return nil }
        return actionEvidenceProjector.projectBaseline(from: observation)
    }

    func moment(
        scope: SemanticObservationScope?,
        timeout: Double = InteractionCoordinator.defaultVisibleStateTimeout
    ) async -> Observation.Moment? {
        guard let scope else { return nil }
        return await vault.semanticObservationStream.settledEvent(
            scope: scope,
            after: nil,
            timeout: timeout
        )?.moment
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
        timing initialTiming: ActionTiming = ActionTiming(),
        afterStateValue: ((ActionPayloadEvidence) -> String?)? = nil,
        before: ActionEvidenceProjector.Baseline,
        postActionCommitScope: SemanticObservationScope = .visible,
        settleResult: SettleSession.Result? = nil,
        notificationWindow: AccessibilityNotificationScopeLease? = nil
    ) async -> ActionResult {
        var timing = initialTiming
        let observationSettlement = await vault.semanticObservationStream.settleActionObservation(
            baselineTripwireSignal: before.tripwireSignal,
            commitScope: postActionCommitScope,
            settleResult: settleResult,
            notificationWindow: notificationWindow
        )
        let finalEvidenceStart = RuntimeElapsed.now
        let actionEvidence = actionEvidenceProjector.projectResult(
            before: before,
            observation: observationSettlement
        )
        timing.record(.finalSemanticEvidence, since: finalEvidenceStart)

        return ActionResult(
            dispatchResult: dispatchResult,
            afterStateValue: afterStateValue,
            snapshot: actionEvidence,
            timing: timing
        )
    }

    /// Evaluates internal replay and supplied-baseline waits.
    /// Public standalone waits execute through `Settlement.Executor`.
    func waitForPredicate(
        _ step: ResolvedWaitRuntimeInput,
        initialTrace: AccessibilityTrace? = nil,
        baselineSequence: SettledObservationSequence? = nil,
        changeBaseline: PredicateChangeBaselineSource = .establishFromFirstObservation,
        actionExpectationContext: ActionExpectationContext? = nil,
        onReadyToPoll: PredicateWait.ReadyToPoll? = nil,
        startedAt: RuntimeElapsed.Instant? = nil
    ) async -> HeistWaitResult {
        let baselineSource: PredicateChangeBaselineSource
        switch (changeBaseline, baselineSequence) {
        case (.establishFromFirstObservation, .some(let sequence)):
            baselineSource = .supplied(await vault.semanticObservationStream.moment(
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
            actionExpectationContext: actionExpectationContext,
            onReadyToPoll: onReadyToPoll,
            startedAt: startedAt
        )
    }

    internal func observePredicateWaitScheduledEffects(
        _ observer: @escaping @MainActor (PredicateWait.ScheduledEffect) -> Void
    ) {
        predicateWait.observeScheduledEffect = observer
    }

    /// Publishes navigation observations while standalone settlement owns evaluation.
    func publishStandaloneWaitDiscovery(
        target: ResolvedAccessibilityTarget?,
        deadline: SemanticObservationDeadline,
        control: Settlement.ObservationEffectControl
    ) async {
        await predicateWait.publishStandaloneWaitDiscovery(
            target: target,
            deadline: deadline,
            control: control
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
