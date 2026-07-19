#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

@MainActor
extension SemanticObservationStream {
    internal func visibleEvidence(timeout: Double?) async -> CleanSettledObservation? {
        let subscription = subscribe(scope: .visible)
        defer { _ = subscription }

        let timeoutMs = Self.timeoutMilliseconds(from: timeout)
        let deadline = SemanticObservationDeadline(
            start: CFAbsoluteTimeGetCurrent(),
            timeoutMs: timeoutMs
        )
        while deadline.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) {
            if let observation = cleanObservation(scope: .visible, after: nil) {
                return observation
            }
            let settlement = await refreshVisibleObservation(
                timeoutMs: max(1, Int((deadline.remainingSeconds() * 1_000).rounded(.up)))
            )
            if case .committed(let event) = settlement.result,
               let observation = cleanObservation(scope: .visible, after: nil),
               observation.event.cursor == event.cursor {
                return observation
            }
        }
        return nil
    }

    internal func cleanObservation(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> CleanSettledObservation? {
        invalidateSettledObservationIfScreenChangedSinceCommit()
        observationStore.invalidateIfSignalChanged(to: currentTripwireSignal())
        return observationStore.cleanObservation(scope: scope, after: sequence)
    }

    @discardableResult
    internal func commitSettledVisibleObservation(
        _ proof: InterfaceObservationProof,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) -> SettledObservationEvent {
        publishCommittedObservation(
            proof,
            scope: .visible,
            notificationBatch: notificationBatch,
            notificationIdentityObservation: notificationIdentityObservation
        )
    }

    @discardableResult
    internal func commitSettledDiscoveryObservation(
        _ proof: InterfaceObservationProof,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledObservationEvent {
        publishCommittedObservation(
            proof,
            scope: .discovery,
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    internal func commitSettledDiscoveryObservation(
        _ outcome: SettleSession.Result,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy,
        afterViewportMovement: Bool,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledObservationEvent? {
        guard let vault else {
            preconditionFailure("SemanticObservationStream cannot admit after TheVault is released")
        }
        guard let proof = admitSettledProof(
            outcome,
            vault: vault,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineageEvidence: afterViewportMovement ? .viewportMovement : nil
        ) else { return nil }
        return commitSettledDiscoveryObservation(
            proof,
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    private func publishCommittedObservation(
        _ proof: InterfaceObservationProof,
        scope: SemanticObservationScope,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) -> SettledObservationEvent {
        guard let vault else {
            preconditionFailure("SemanticObservationStream cannot commit after TheVault is released")
        }
        let resolvedNotificationBatch = notificationBatch
            ?? vault.accessibilityNotifications.checkpoint(
                after: observationStore.notificationCursor
            )
        let commit: SemanticObservationStore.Commit
        do {
            commit = try observationStore.commitObservation(
                proof,
                scope: scope,
                notificationBatch: resolvedNotificationBatch
            ) { committedObservation in
                SemanticObservationStore.Evidence(
                    interface: vault.semanticInterface(for: committedObservation),
                    accessibilityNotifications: vault.resolveAccessibilityNotificationEvidence(
                        resolvedNotificationBatch.events,
                        identityObservation: notificationIdentityObservation ?? committedObservation,
                        referenceObservation: committedObservation
                    ),
                    firstResponder: vault.firstResponderTarget(in: committedObservation.tree)
                )
            }
        } catch {
            preconditionFailure("Committed interface observation failed validation: \(error)")
        }
        vault.recordCommittedObservation(commit.observation, sourceObservation: proof.observation)
        for fallbackReason in commit.fallbackReasons {
            AccessibilityObservationFallbackLog.record(
                fallbackReason,
                source: .settledObservation
            )
        }
        completeObservationWaiters()
        return commit.sourceEvent
    }

    internal func settlePostActionObservation(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        commitScope: SemanticObservationScope = .visible,
        settleOutcome providedOutcome: SettleSession.Result? = nil,
        notificationWindow: AccessibilityNotificationScopeLease? = nil
    ) async -> ObservationSettlement {
        if let session = visibleRefreshSession {
            _ = await finishVisibleRefresh(session)
        }
        return await startVisibleRefresh(
            baselineTripwireSignal: baselineTripwireSignal,
            timeoutMs: SettleSession.defaultTimeoutMs,
            commitScope: commitScope,
            providedOutcome: providedOutcome,
            notificationWindow: notificationWindow,
            invalidatingCurrentObservation: true
        )
    }

    internal func refreshVisibleObservation(timeoutMs: Int) async -> ObservationSettlement {
        if let session = visibleRefreshSession {
            return await finishVisibleRefresh(session).settlement
        }
        return await startVisibleRefresh(
            baselineTripwireSignal: currentTripwireSignal(),
            timeoutMs: timeoutMs,
            commitScope: .visible,
            providedOutcome: nil,
            notificationWindow: nil,
            invalidatingCurrentObservation: false
        )
    }

    private func startVisibleRefresh(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int,
        commitScope: SemanticObservationScope,
        providedOutcome: SettleSession.Result?,
        notificationWindow: AccessibilityNotificationScopeLease?,
        invalidatingCurrentObservation: Bool
    ) async -> ObservationSettlement {
        if invalidatingCurrentObservation {
            observationStore.invalidateCurrentObservation()
        } else {
            observationStore.invalidateIfSignalChanged(to: baselineTripwireSignal)
        }
        let task = Task { @MainActor in
            VisibleRefreshCompletion(await self.produceVisibleSettlement(
                baselineTripwireSignal: baselineTripwireSignal,
                timeoutMs: timeoutMs,
                commitScope: commitScope,
                providedOutcome: providedOutcome,
                notificationWindow: notificationWindow
            ))
        }
        let session = VisibleRefreshSession(task: task)
        visibleRefreshSession = session
        return await finishVisibleRefresh(session).settlement
    }

    private func finishVisibleRefresh(
        _ session: VisibleRefreshSession
    ) async -> VisibleRefreshCompletion {
        let completion = await session.task.value
        if visibleRefreshSession === session {
            visibleRefreshSession = nil
        }
        return completion
    }

    private func produceVisibleSettlement(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int,
        commitScope: SemanticObservationScope,
        providedOutcome: SettleSession.Result?,
        notificationWindow: AccessibilityNotificationScopeLease?
    ) async -> ObservationSettlement {
        guard let vault else {
            let notificationBatch = notificationWindow?.capture()
            notificationWindow?.cancel()
            return ObservationSettlement(
                settle: SettleSession.Result(
                    outcome: .cancelled(timeMs: 0),
                    events: [],
                    finalObservation: nil,
                    elementsByKey: [:],
                    tripwireSignal: baselineTripwireSignal
                ),
                result: .unavailable(notificationBatch: notificationBatch)
            )
        }
        let outcome: SettleSession.Result
        if let providedOutcome {
            outcome = providedOutcome
        } else {
            outcome = await settleVisibleObservation(
                vault,
                tripwire,
                activeObservationDemandState,
                baselineTripwireSignal,
                timeoutMs
            )
        }

        let terminalActionNotificationBatch = notificationWindow?.capture()
        notificationWindow?.cancel()

        if Task.isCancelled, providedOutcome == nil {
            return ObservationSettlement(
                settle: outcome,
                result: .unavailable(notificationBatch: terminalActionNotificationBatch)
            )
        }
        if let proof = admitSettledProof(outcome, vault: vault) {
            let notificationBatch = terminalActionNotificationBatch
                ?? vault.accessibilityNotifications.checkpoint(
                    after: observationStore.notificationCursor
                )
            let event: SettledObservationEvent
            switch commitScope {
            case .visible:
                event = commitSettledVisibleObservation(
                    proof,
                    notificationBatch: notificationBatch,
                    notificationIdentityObservation: proof.observation
                )
            case .discovery:
                event = commitSettledDiscoveryObservation(
                    proof,
                    notificationBatch: notificationBatch
                )
            }
            return ObservationSettlement(settle: outcome, result: .committed(event))
        }
        return ObservationSettlement(
            settle: outcome,
            result: postActionFailureResult(
                outcome,
                notificationBatch: terminalActionNotificationBatch
            )
        )
    }

    internal func requireScreenReplacement() {
        observationStore.requireReplacement()
    }

    internal func clearCurrentInterface() {
        observationStore.clearCurrentInterface()
    }

    internal func invalidateLatestSettledObservation() {
        observationStore.invalidateCurrentObservation()
    }

    /// A scoped `screenChanged` notification recorded after the latest settled
    /// commit means the settled screen has already been replaced — the
    /// notification is a completion signal, so the invalidation is definitive,
    /// not speculative. Serve-path reads then wait for a fresh cycle instead
    /// of returning the stale world.
    ///
    /// The notification bus records this as scoped at event time, so ambient
    /// host-app notifications outside command execution cannot later churn
    /// settled state. `layoutChanged` deliberately does not invalidate: it
    /// also fires for in-place updates and would starve reads on chatty
    /// screens.
    func invalidateSettledObservationIfScreenChangedSinceCommit() {
        guard let vault,
              !latestSettledObservationInvalidated,
              latestEvent != nil,
              vault.accessibilityNotifications.latestScopedScreenChangedSequence
              > observationStore.scopedScreenChangedSequence
        else { return }
        observationStore.invalidateCurrentObservation()
    }

    func admitSettledProof(
        _ outcome: SettleSession.Result,
        vault: TheVault,
        layerGateWasClear: Bool? = nil,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) -> InterfaceObservationProof? {
        guard outcome.tripwireSignal == currentTripwireSignal(),
              outcome.finalObservation?.observation.captureToken == vault.latestObservation.captureToken,
              let proof = InterfaceObservationProof.settled(
                  outcome,
                  discoveryCommitPolicy: discoveryCommitPolicy,
                  lineageEvidence: lineageEvidence
              ) else {
            recordFailedSettle(
                SettleFailureDiagnostic.message(for: outcome, layerGateWasClear: layerGateWasClear),
                observation: outcome.finalObservation?.observation,
                vault: vault
            )
            return nil
        }
        return proof
    }

    private func postActionFailureResult(
        _ outcome: SettleSession.Result,
        notificationBatch: AccessibilityNotificationBatch?
    ) -> ObservationSettlement.Result {
        guard !outcome.outcome.didSettleCleanly,
              case .timedOut = outcome.outcome,
              let observation = outcome.finalObservation?.observation else {
            return .unavailable(notificationBatch: notificationBatch)
        }
        return .observedUnsettled(observation, notificationBatch: notificationBatch)
    }

    private func recordFailedSettle(
        _ diagnostic: String?,
        observation: InterfaceObservation?,
        vault: TheVault
    ) {
        observationStore.recordSettleFailure(diagnostic)
        vault.recordFailedSettleDiagnosticEvidence(observation)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
