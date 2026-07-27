#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

// MARK: - Settlement

@MainActor
extension Observation.Stream {
    internal func admittedVisibleObservation(timeout: Double?) async -> Observation.Store.AdmittedObservation? {
        let subscription = subscribe(scope: .visible)
        defer { _ = subscription }

        let deadline = SemanticObservationDeadline(
            start: RuntimeElapsed.now,
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )
        while deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            if let observation = await admittedObservation(scope: .visible, after: nil) {
                return observation
            }
            let settlement = await refreshVisibleObservation()
            if case .committed(let event) = settlement.commitOutcome,
               let observation = await admittedObservation(scope: .visible, after: nil),
               observation.event.moment == event.moment {
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
    ) async -> Observation.Store.AdmittedObservation? {
        let subscription = subscribe(scope: .visible)
        defer { _ = subscription }

        let deadline = SemanticObservationDeadline(
            start: RuntimeElapsed.now,
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )
        while deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            let settlement = await refreshVisibleObservation()
            if case .committed(let event) = settlement.commitOutcome,
               let observation = await admittedObservation(scope: .visible, after: nil),
               observation.event.moment == event.moment {
                return observation
            }
        }
        return nil
    }

    internal func admittedObservation(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) async -> Observation.Store.AdmittedObservation? {
        await invalidateSettledObservationIfScreenChangedSinceCommit()
        await invalidateDeliveryIfSignalChanged(to: currentTripwireSignal())
        return await storeOwner.admittedObservation(scope: scope, after: sequence)
    }

    @discardableResult
    internal func commitSettledVisibleObservation(
        _ committableObservation: CommittableInterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityObservation: InterfaceObservation? = nil
    ) async -> Observation.PublicationOutcome {
        await publishCommittedObservation(
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
    ) async -> Observation.PublicationOutcome {
        await publishCommittedObservation(
            committableObservation,
            scope: .discovery,
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    internal func commitSettledDiscoveryObservation(
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy,
        afterViewportMovement: Bool,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> Observation.PublicationOutcome? {
        guard let vault else {
            preconditionFailure("Observation.Stream cannot admit after TheVault is released")
        }
        guard let committableObservation = await admitCurrentObservation(
            vault: vault,
            tripwireSignal: currentTripwireSignal(),
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineageEvidence: afterViewportMovement ? .viewportMovement : nil
        ) else { return nil }
        return await commitSettledDiscoveryObservation(
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
    ) async -> Observation.PublicationOutcome {
        guard let vault else {
            preconditionFailure("Observation.Stream cannot commit after TheVault is released")
        }
        let resolvedNotificationBatch = notificationBatch
            ?? vault.accessibilityNotifications.checkpoint(
                after: .origin,
                selection: .unclaimedScoped
            )
        let sourceObservation = committableObservation.observation
        deliveryState.observeSourceCapture(sourceObservation.captureID)
        let identityObservation = notificationIdentityObservation ?? sourceObservation
        let notificationSnapshot = Observation.NotificationSnapshot(
            evidence: vault.resolveAccessibilityNotificationEvidence(
                resolvedNotificationBatch.events,
                identityObservation: identityObservation,
                referenceObservation: sourceObservation
            ),
            through: resolvedNotificationBatch.through,
            scopedScreenChangedThrough: resolvedNotificationBatch.scopedScreenChangedThrough,
            gap: resolvedNotificationBatch.gap
        )
        let notificationAdmission: Observation.NotificationAdmission = notificationBatch == nil
            ? .passive(notificationSnapshot)
            : .action(notificationSnapshot)
        let admission = Observation.Admission(
            tree: sourceObservation.tree,
            captureID: sourceObservation.captureID,
            tripwireSignal: committableObservation.tripwireSignal,
            discoveryCommitPolicy: committableObservation.discoveryCommitPolicy,
            lineageEvidence: committableObservation.lineageEvidence,
            scope: scope,
            notificationAdmission: notificationAdmission,
            keyboardVisible: vault.keyboardVisible,
            timestamp: Date(),
            viewportFrames: sourceObservation.tree.viewportFrames,
            placementTolerance: CoarseFrameComparison.currentTolerance
        )
        var delivery: Observation.StoreOwner.CommittedDelivery
        do {
            delivery = try await storeOwner.commitAdmission(admission)
        } catch {
            preconditionFailure("Committed interface observation failed validation: \(error)")
        }
        var didReadmit = false
        while true {
            precondition(
                delivery.committed.captureID == sourceObservation.captureID,
                "Observation commit must preserve its source capture identity"
            )
            await beforeCommittedDelivery(delivery.token)
            let canReadmit = !didReadmit
                && deliveryState.isLatestSourceCapture(sourceObservation.captureID)
            let resolution: Observation.StoreOwner.DeliveryResolution
            do {
                resolution = try await storeOwner.resolveDelivery(
                    for: delivery.token,
                    readmitting: canReadmit ? admission : nil
                )
            } catch {
                preconditionFailure("Re-admitted interface observation failed validation: \(error)")
            }
            switch resolution {
            case .current(let deliveryAdmission):
                await beforeResolvedDeliveryEnqueue(delivery.token)
                if let outcome = enqueueValidatedDelivery(
                    delivery,
                    admission: deliveryAdmission,
                    sourceObservation: sourceObservation
                ) {
                    if outcome.event != nil {
                        await completeObservationWaiters()
                    }
                    return outcome
                }
                return await waitForPublication(of: delivery.token)
            case .readmitted(let readmittedDelivery):
                didReadmit = true
                delivery = readmittedDelivery
            case .superseded:
                return .superseded
            }
        }
    }

    private func enqueueValidatedDelivery(
        _ delivery: Observation.StoreOwner.CommittedDelivery,
        admission: Observation.StoreOwner.DeliveryAdmission,
        sourceObservation: InterfaceObservation
    ) -> Observation.PublicationOutcome? {
        guard let vault else { return .superseded }
        let enqueueResult = deliveryState.enqueue(
            PendingDelivery(
                delivery: delivery,
                sourceObservation: sourceObservation
            ),
            currentCommitOrder: admission.currentCommitOrder
        )
        guard case .ready(let ready) = enqueueResult else {
            completePublication(of: delivery.token, with: .superseded)
            return .superseded
        }
        var deliveredEvent: Observation.SnapshotEvent?
        for item in ready {
            let pending = item.pending
            if item.reattachesLiveCapture {
                let committedObservation: InterfaceObservation
                do {
                    committedObservation = try pending.sourceObservation.replacingTreeWithCurrentCapture(
                        pending.delivery.committed.tree
                    )
                } catch {
                    preconditionFailure("Committed live observation failed validation: \(error)")
                }
                vault.recordCommittedObservation(
                    committedObservation,
                    sourceObservation: pending.sourceObservation
                )
            }
            let event = pending.delivery.committed.event
            publishImmediately(.snapshot(event))
            completePublication(of: pending.delivery.token, with: .delivered(event))
            if pending.delivery.token == delivery.token {
                deliveredEvent = event
            }
        }
        return deliveredEvent.map(Observation.PublicationOutcome.delivered)
    }

    internal func refreshVisibleObservation(
        baselineTripwireSignal: TheTripwire.TripwireSignal? = nil
    ) async -> ObservationSettlement {
        if let refresh = visibleRefreshPhase.task {
            return await finishVisibleRefresh(refresh)
        }
        return await startVisibleRefresh(
            tripwireSignal: baselineTripwireSignal ?? currentTripwireSignal()
        )
    }

    internal func visibleRefreshBoundary() -> VisibleRefreshBoundary {
        VisibleRefreshBoundary(nextTokenRawValue: nextVisibleRefreshToken)
    }

    internal func refreshVisibleObservation(
        after boundary: VisibleRefreshBoundary,
        baselineTripwireSignal: TheTripwire.TripwireSignal
    ) async -> ObservationSettlement {
        if let refresh = visibleRefreshPhase.task,
           refresh.token.rawValue < boundary.nextTokenRawValue {
            _ = await finishVisibleRefresh(refresh)
        }
        return await refreshVisibleObservation(
            baselineTripwireSignal: baselineTripwireSignal
        )
    }

    private func startVisibleRefresh(
        tripwireSignal: TheTripwire.TripwireSignal
    ) async -> ObservationSettlement {
        await invalidateDeliveryIfSignalChanged(to: tripwireSignal)
        let task = Task { @MainActor in
            await self.produceVisibleSettlement(tripwireSignal: tripwireSignal)
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

    /// Reads the tree once and commits what it read.
    ///
    /// A reading is never held back until something agrees the tree stopped
    /// moving. Whether it moved is the store's own answer, carried on the event;
    /// stillness is the `.noChange` tick that answer produces, drained like any
    /// other predicate.
    private func produceVisibleSettlement(
        tripwireSignal: TheTripwire.TripwireSignal
    ) async -> ObservationSettlement {
        await beforeVisibleReading()
        guard let vault, !Task.isCancelled else {
            return ObservationSettlement(commitOutcome: .unavailable)
        }
        guard let captured = vault.captureVisibleObservation() else {
            await recordFailedSettle(
                "the accessibility tree could not be read",
                observation: nil,
                vault: vault
            )
            return ObservationSettlement(commitOutcome: .unavailable)
        }
        guard let committableObservation = await admitCurrentObservation(
            captured,
            vault: vault,
            tripwireSignal: tripwireSignal
        ) else {
            return ObservationSettlement(commitOutcome: .unavailable)
        }
        let notificationIndex = await storeOwner.notificationIndex()
        let notificationBatch = vault.accessibilityNotifications.checkpoint(
            after: notificationIndex
        )
        let outcome = await commitSettledVisibleObservation(
            committableObservation,
            notificationBatch: notificationBatch,
            notificationIdentityObservation: committableObservation.observation
        )
        switch outcome {
        case .delivered(let event):
            return ObservationSettlement(commitOutcome: .committed(event))
        case .superseded:
            return ObservationSettlement(commitOutcome: .unavailable)
        }
    }

    internal func requireScreenReplacement() async {
        let generation = await storeOwner.requireReplacement()
        synchronizeDeliveryGeneration(generation, clearingSource: true)
    }

    internal func clearCurrentInterface() async {
        let generation = await storeOwner.clearCurrentInterface()
        synchronizeDeliveryGeneration(
            generation,
            clearingProjection: true,
            clearingSource: true
        )
    }

    internal func invalidateLatestSettledObservation() async {
        let generation = await storeOwner.invalidateCurrentObservation()
        synchronizeDeliveryGeneration(generation)
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
    func invalidateSettledObservationIfScreenChangedSinceCommit() async {
        guard let vault,
              !(await storeOwner.latestSettledObservationInvalidated()),
              await storeOwner.latestCommittedEvent() != nil,
              vault.accessibilityNotifications.latestScopedScreenChangedSequence
              > (await storeOwner.scopedScreenChangedSequence())
        else { return }
        let generation = await storeOwner.invalidateCurrentObservation()
        synchronizeDeliveryGeneration(generation, clearingSource: true)
    }

    /// Admits the tree as it stands right now.
    ///
    /// The only question left is identity: a reading belongs to the screen it
    /// was taken on, so structural UIKit state moving underneath it means the
    /// reading describes a screen we are no longer looking at. Accessibility
    /// notifications are movement on the same screen — UIKit posts them
    /// throughout a transition — so they let the reading through. Whether the
    /// tree moved is the store's comparison, answered on commit.
    func admitCurrentObservation(
        _ observation: InterfaceObservation? = nil,
        vault: TheVault,
        tripwireSignal: TheTripwire.TripwireSignal,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineageEvidence: ScreenLineageEvidence? = nil
    ) async -> CommittableInterfaceObservation? {
        let reading = observation ?? vault.latestObservation
        guard currentTripwireSignal().hierarchy == tripwireSignal.hierarchy else {
            await recordFailedSettle(
                "the view hierarchy moved while the reading was taken",
                observation: reading,
                vault: vault
            )
            return nil
        }
        return CommittableInterfaceObservation.admitCaptured(
            reading,
            tripwireSignal: tripwireSignal,
            lineageEvidence: lineageEvidence
        )
    }

    private func recordFailedSettle(
        _ diagnostic: String?,
        observation: InterfaceObservation?,
        vault: TheVault
    ) async {
        await storeOwner.recordSettleFailure(diagnostic)
        await vault.recordFailedSettleDiagnosticEvidence(observation)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
