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
        observationLog.invalidateIfSignalChanged(to: currentTripwireSignal())
        return observationLog.cleanObservation(scope: scope, after: sequence)
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
                after: runtimeState.notificationCursor
            )
        let previousTree = vault.interfaceTree
        let candidateTree = switch scope {
        case .visible:
            previousTree.updatingViewport(with: proof.observation)
        case .discovery:
            proof.discoveryCommitPolicy == .replaceInterface
                ? proof.observation.tree
                : previousTree.merging(proof.observation.tree)
        }
        let classifiedContinuity = ScreenClassifier.classify(
            from: previousTree == .empty ? nil : previousTree,
            to: candidateTree,
            notifications: resolvedNotificationBatch.events.map(\.kind),
            lineageEvidence: proof.lineageEvidence
        )
        let continuity = runtimeState.lineage.admitting(classifiedContinuity)
        if continuity.isReplacement {
            observationLog.beginScreenReplacement()
        }
        _ = vault.reduceInterfaceGraph(
            with: proof.observation,
            scope: scope,
            continuity: continuity,
            discoveryCommitPolicy: proof.discoveryCommitPolicy
        )
        return publishCurrentSettledObservation(
            scope: scope,
            vault: vault,
            tripwireSignal: proof.tripwireSignal,
            notificationBatch: resolvedNotificationBatch,
            continuity: continuity,
            notificationIdentityObservation: notificationIdentityObservation
        )
    }

    internal func settlePostActionObservation(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        commitScope: SemanticObservationScope = .visible,
        settleOutcome providedOutcome: SettleSession.Outcome? = nil,
        notificationWindow: AccessibilityNotificationActionWindow? = nil
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
            invalidatingCurrentPublication: true
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
            invalidatingCurrentPublication: false
        )
    }

    private func startVisibleRefresh(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        timeoutMs: Int,
        commitScope: SemanticObservationScope,
        providedOutcome: SettleSession.Outcome?,
        notificationWindow: AccessibilityNotificationActionWindow?,
        invalidatingCurrentPublication: Bool
    ) async -> ObservationSettlement {
        if invalidatingCurrentPublication {
            observationLog.invalidateCurrentPublication()
        } else {
            observationLog.invalidateIfSignalChanged(to: baselineTripwireSignal)
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
        providedOutcome: SettleSession.Outcome?,
        notificationWindow: AccessibilityNotificationActionWindow?
    ) async -> ObservationSettlement {
        guard let vault else {
            let notificationBatch = notificationWindow?.capture()
            notificationWindow?.cancel()
            return ObservationSettlement(
                settle: SettleSession.Outcome(
                    outcome: .cancelled(timeMs: 0),
                    events: [],
                    finalObservation: nil,
                    elementsByKey: [:],
                    tripwireSignal: baselineTripwireSignal
                ),
                result: .unavailable(notificationBatch: notificationBatch)
            )
        }
        let outcome: SettleSession.Outcome
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
                    after: runtimeState.notificationCursor
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
        observationLog.beginScreenReplacement()
        runtimeState.requireReplacement()
    }

    internal func invalidateLatestSettledObservation() {
        observationLog.invalidateCurrentPublication()
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
              > runtimeState.scopedScreenChangedSequence
        else { return }
        observationLog.invalidateCurrentPublication()
    }

    private func publishCurrentSettledObservation(
        scope: SemanticObservationScope = .visible,
        vault: TheVault,
        tripwireSignal: TheTripwire.TripwireSignal,
        notificationBatch: AccessibilityNotificationBatch,
        continuity: ScreenContinuity,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) -> SettledObservationEvent {
        let settledObservation: InterfaceObservation
        do {
            settledObservation = try InterfaceObservation.build(tree: vault.interfaceTree)
        } catch {
            preconditionFailure("Published semantic observation failed validation: \(error)")
        }
        let publication = SemanticObservationPublication.make(
            sourceScope: scope,
            sequence: runtimeState.sequence + 1,
            notificationBatch: notificationBatch,
            observation: settledObservation,
            semanticSignal: tripwireSignal.semanticValue,
            context: SemanticObservationPublication.Context(
                continuity: continuity,
                generation: runtimeState.lineage.generation,
                previousEvents: observationLog.latestEventsByScope
            ),
            evidenceByScope: publicationEvidence(
                sourceScope: scope,
                observation: settledObservation,
                notificationBatch: notificationBatch,
                notificationIdentityObservation: notificationIdentityObservation,
                vault: vault
            )
        )
        for fallbackReason in scope.fulfilledScopes.compactMap({ fulfilledScope in
            publication.events[fulfilledScope]?.trace.captures.last?.transition.fallbackReason
        }) {
            AccessibilityObservationFallbackLog.record(
                fallbackReason,
                source: .settledObservation
            )
        }
        do {
            try observationLog.publish(
                publication,
                tripwireSignal: tripwireSignal
            )
        } catch {
            preconditionFailure("Semantic observation log rejected publication: \(error)")
        }
        completeObservationWaiters()
        runtimeState.commit(
            publication,
            notificationBatch: notificationBatch
        )
        return publication.sourceEvent
    }

    private func publicationEvidence(
        sourceScope: SemanticObservationScope,
        observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch,
        notificationIdentityObservation: InterfaceObservation?,
        vault: TheVault
    ) -> [SemanticObservationScope: SemanticObservationPublication.Evidence] {
        Dictionary(uniqueKeysWithValues: sourceScope.fulfilledScopes.map { fulfilledScope in
            let referenceObservation = observation
            return (fulfilledScope, SemanticObservationPublication.Evidence(
                interface: vault.semanticInterfaceWithHash(for: referenceObservation).interface,
                accessibilityNotifications: vault.resolveAccessibilityNotificationEvidence(
                    notificationBatch.events,
                    identityObservation: notificationIdentityObservation ?? referenceObservation,
                    referenceObservation: referenceObservation
                ),
                firstResponder: vault.firstResponderTarget(in: referenceObservation.tree)
            ))
        })
    }

    func admitSettledProof(
        _ outcome: SettleSession.Outcome,
        vault: TheVault,
        layerGateWasClear: Bool? = nil
    ) -> InterfaceObservationProof? {
        guard outcome.tripwireSignal == currentTripwireSignal(),
              let proof = InterfaceObservationProof.settled(outcome, vault: vault) else {
            recordFailedSettle(
                SettleFailureDiagnostic.message(for: outcome, layerGateWasClear: layerGateWasClear),
                tree: outcome.finalObservation?.tree,
                vault: vault
            )
            return nil
        }
        return proof
    }

    private func postActionFailureResult(
        _ outcome: SettleSession.Outcome,
        notificationBatch: AccessibilityNotificationBatch?
    ) -> ObservationSettlement.Result {
        guard !outcome.outcome.didSettleCleanly,
              case .timedOut = outcome.outcome,
              let tree = outcome.finalObservation?.tree else {
            return .unavailable(notificationBatch: notificationBatch)
        }
        return .observedUnsettled(tree, notificationBatch: notificationBatch)
    }

    private func recordFailedSettle(
        _ diagnostic: String?,
        tree: InterfaceTree?,
        vault: TheVault
    ) {
        runtimeState.recordSettleFailure(diagnostic)
        let observation = tree.map { tree in
            do {
                return try InterfaceObservation.build(tree: tree)
            } catch {
                preconditionFailure("Failed settle diagnostic observation failed validation: \(error)")
            }
        }
        vault.recordFailedSettleDiagnosticEvidence(observation)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
