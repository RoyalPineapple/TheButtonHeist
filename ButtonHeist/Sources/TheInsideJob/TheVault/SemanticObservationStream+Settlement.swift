#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

// MARK: - Settlement

@MainActor
extension SemanticObservationStream {
    internal func admittedVisibleObservation(timeout: Double?) async -> SemanticObservationStore.AdmittedObservation? {
        let subscription = subscribe(scope: .visible)
        defer { _ = subscription }

        let timeoutMs = Self.timeoutMilliseconds(from: timeout)
        let deadline = SemanticObservationDeadline(
            start: RuntimeElapsed.now,
            timeoutMs: timeoutMs
        )
        while deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            if let observation = admittedObservation(scope: .visible, after: nil) {
                return observation
            }
            let settlement = await refreshVisibleObservation(
                timeoutMs: max(1, Int((deadline.remainingSeconds() * 1_000).rounded(.up)))
            )
            if case .committed(let event) = settlement.commitOutcome,
               let observation = admittedObservation(scope: .visible, after: nil),
               observation.event.cursor == event.cursor {
                return observation
            }
        }
        return nil
    }

    /// Produces a new settled sample before admitting the visible baseline.
    /// Use this at an execution boundary where work may have started before the
    /// caller opened its notification or animation wait scopes.
    internal func refreshedVisibleObservation(
        timeout: Double?
    ) async -> SemanticObservationStore.AdmittedObservation? {
        let subscription = subscribe(scope: .visible)
        defer { _ = subscription }

        let deadline = SemanticObservationDeadline(
            start: RuntimeElapsed.now,
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )
        while deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            let settlement = await refreshVisibleObservation(
                timeoutMs: max(1, Int((deadline.remainingSeconds() * 1_000).rounded(.up)))
            )
            if case .committed(let event) = settlement.commitOutcome,
               let observation = admittedObservation(scope: .visible, after: nil),
               observation.event.cursor == event.cursor {
                return observation
            }
        }
        return nil
    }

    internal func admittedObservation(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SemanticObservationStore.AdmittedObservation? {
        invalidateSettledObservationIfScreenChangedSinceCommit()
        observationStore.invalidateIfSignalChanged(to: currentTripwireSignal())
        return observationStore.admittedObservation(scope: scope, after: sequence)
    }

    @discardableResult
    internal func commitSettledVisibleObservation(
        _ committableObservation: CommittableInterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) -> SettledObservationEvent {
        publishCommittedObservation(
            committableObservation,
            scope: .visible,
            notificationBatch: notificationBatch,
            notificationIdentityObservation: notificationIdentityObservation
        )
    }

    @discardableResult
    internal func commitSettledDiscoveryObservation(
        _ committableObservation: CommittableInterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledObservationEvent {
        publishCommittedObservation(
            committableObservation,
            scope: .discovery,
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    internal func commitSettledDiscoveryObservation(
        _ settleResult: SettleSession.Result,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy,
        afterViewportMovement: Bool,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledObservationEvent? {
        guard let vault else {
            preconditionFailure("SemanticObservationStream cannot admit after TheVault is released")
        }
        guard let committableObservation = admitSettledObservation(
            settleResult,
            vault: vault,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineageEvidence: afterViewportMovement ? .viewportMovement : nil
        ) else { return nil }
        return commitSettledDiscoveryObservation(
            committableObservation,
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    private func publishCommittedObservation(
        _ committableObservation: CommittableInterfaceObservation,
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
        let committed: SemanticObservationStore.CommittedObservation
        do {
            committed = try observationStore.commitObservation(
                committableObservation,
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
        vault.recordCommittedObservation(
            committed.interfaceObservation,
            sourceObservation: committableObservation.observation
        )
        for fallbackReason in committed.fallbackReasons {
            AccessibilityObservationFallbackLog.record(
                fallbackReason,
                source: .settledObservation
            )
        }
        completeObservationWaiters()
        return committed.event
    }

    internal func settleActionObservation(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        commitScope: SemanticObservationScope = .visible,
        settleResult providedResult: SettleSession.Result? = nil,
        notificationWindow: AccessibilityNotificationScopeLease? = nil
    ) async -> ObservationSettlement {
        if let refresh = visibleRefreshPhase.task {
            _ = await finishVisibleRefresh(refresh)
        }
        return await startVisibleRefresh(
            baselineTripwireSignal: baselineTripwireSignal,
            timeoutMs: SettleSession.defaultTimeoutMs,
            commitScope: commitScope,
            providedResult: providedResult,
            notificationWindow: notificationWindow,
            invalidatingCurrentObservation: true
        )
    }

    internal func refreshVisibleObservation(timeoutMs: Int) async -> ObservationSettlement {
        if let refresh = visibleRefreshPhase.task {
            return await finishVisibleRefresh(refresh)
        }
        return await startVisibleRefresh(
            baselineTripwireSignal: currentTripwireSignal(),
            timeoutMs: timeoutMs,
            commitScope: .visible,
            providedResult: nil,
            notificationWindow: nil,
            invalidatingCurrentObservation: false
        )
    }

    private func startVisibleRefresh(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int,
        commitScope: SemanticObservationScope,
        providedResult: SettleSession.Result?,
        notificationWindow: AccessibilityNotificationScopeLease?,
        invalidatingCurrentObservation: Bool
    ) async -> ObservationSettlement {
        if invalidatingCurrentObservation {
            observationStore.invalidateCurrentObservation()
        } else {
            observationStore.invalidateIfSignalChanged(to: baselineTripwireSignal)
        }
        let task = Task { @MainActor in
            await self.produceVisibleSettlement(
                baselineTripwireSignal: baselineTripwireSignal,
                timeoutMs: timeoutMs,
                commitScope: commitScope,
                providedResult: providedResult,
                notificationWindow: notificationWindow
            )
        }
        let refresh = VisibleRefreshTask(
            token: nextVisibleRefreshTokenValue(),
            task: task
        )
        visibleRefreshPhase = .refreshing(refresh)
        return await finishVisibleRefresh(refresh)
    }

    private func finishVisibleRefresh(
        _ refresh: VisibleRefreshTask
    ) async -> ObservationSettlement {
        let completion = await refresh.task.value
        if visibleRefreshPhase.task?.token == refresh.token {
            visibleRefreshPhase = .idle
        }
        return completion
    }

    private func nextVisibleRefreshTokenValue() -> VisibleRefreshToken {
        let token = VisibleRefreshToken(rawValue: nextVisibleRefreshToken)
        nextVisibleRefreshToken += 1
        return token
    }

    private func produceVisibleSettlement(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int,
        commitScope: SemanticObservationScope,
        providedResult: SettleSession.Result?,
        notificationWindow: AccessibilityNotificationScopeLease?
    ) async -> ObservationSettlement {
        guard let vault else {
            let notificationBatch = notificationWindow?.capture()
            notificationWindow?.cancel()
            return ObservationSettlement(
                settleResult: SettleSession.Result(
                    outcome: .cancelled(timeMs: 0),
                    events: [],
                    finalObservation: nil,
                    elementsByKey: [:],
                    tripwireSignal: baselineTripwireSignal
                ),
                commitOutcome: .unavailable(notificationBatch: notificationBatch)
            )
        }
        let settleResult: SettleSession.Result
        if let providedResult {
            settleResult = providedResult
        } else {
            settleResult = await settleVisibleObservation(
                vault,
                tripwire,
                activeObservationDemandState,
                baselineTripwireSignal,
                timeoutMs
            )
        }

        let terminalActionNotificationBatch = notificationWindow?.capture()
        notificationWindow?.cancel()

        if Task.isCancelled, providedResult == nil {
            return ObservationSettlement(
                settleResult: settleResult,
                commitOutcome: .unavailable(notificationBatch: terminalActionNotificationBatch)
            )
        }
        if let committableObservation = admitSettledObservation(settleResult, vault: vault) {
            let notificationBatch = terminalActionNotificationBatch
                ?? vault.accessibilityNotifications.checkpoint(
                    after: observationStore.notificationCursor
                )
            let event: SettledObservationEvent
            switch commitScope {
            case .visible:
                event = commitSettledVisibleObservation(
                    committableObservation,
                    notificationBatch: notificationBatch,
                    notificationIdentityObservation: committableObservation.observation
                )
            case .discovery:
                event = commitSettledDiscoveryObservation(
                    committableObservation,
                    notificationBatch: notificationBatch
                )
            }
            return ObservationSettlement(settleResult: settleResult, commitOutcome: .committed(event))
        }
        return ObservationSettlement(
            settleResult: settleResult,
            commitOutcome: postActionFailureResult(
                settleResult,
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
              latestCommittedEvent != nil,
              vault.accessibilityNotifications.latestScopedScreenChangedSequence
              > observationStore.scopedScreenChangedSequence
        else { return }
        observationStore.invalidateCurrentObservation()
    }

    func admitSettledObservation(
        _ settleResult: SettleSession.Result,
        vault: TheVault,
        layerGateWasClear: Bool? = nil,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) -> CommittableInterfaceObservation? {
        guard settleResult.tripwireSignal == currentTripwireSignal(),
              settleResult.finalObservation?.observation.captureID == vault.latestObservation.captureID,
              let committableObservation = CommittableInterfaceObservation.admit(
                  settleResult,
                  discoveryCommitPolicy: discoveryCommitPolicy,
                  lineageEvidence: lineageEvidence
              ) else {
            recordFailedSettle(
                SettleFailureDiagnostic.message(for: settleResult, layerGateWasClear: layerGateWasClear),
                observation: settleResult.finalObservation?.observation,
                vault: vault
            )
            return nil
        }
        return committableObservation
    }

    private func postActionFailureResult(
        _ settleResult: SettleSession.Result,
        notificationBatch: AccessibilityNotificationBatch?
    ) -> ObservationSettlement.CommitOutcome {
        guard !settleResult.outcome.didSettleCleanly,
              case .timedOut = settleResult.outcome,
              let observation = settleResult.finalObservation?.observation else {
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
