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
        await discardIfScreenChangedSinceRead()
        await discardIfSignalChanged(to: currentTripwireSignal())
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
            lineage: afterViewportMovement ? .viewportMovement : .resting
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
            lineage: committableObservation.lineage,
            scope: scope,
            notificationAdmission: notificationAdmission,
            keyboardVisible: vault.keyboardVisible,
            timestamp: Date(),
            viewportFrames: sourceObservation.tree.viewportFrames,
            placementTolerance: CoarseFrameComparison.currentTolerance
        )
        let read: Observation.Store.ReadObservation
        do {
            read = try await storeOwner.readAdmission(admission)
        } catch {
            preconditionFailure("Interface observation failed validation: \(error)")
        }
        precondition(
            read.captureID == sourceObservation.captureID,
            "A reading must preserve its source capture identity"
        )
        if let reattached = try? sourceObservation.replacingTreeWithCurrentCapture(read.tree) {
            vault.recordCommittedObservation(
                reattached,
                sourceObservation: sourceObservation
            )
        }
        // One at a time, in the order the vault minted them: a boundary's
        // departure, identity and arrival are three moments, and each one is a
        // pass through the machine of its own.
        for event in read.events {
            publishImmediately(event)
        }
        await completeObservationWaiters()
        return .delivered(read)
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
        await discardIfSignalChanged(to: tripwireSignal)
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

    /// Reads the tree once and emits what it read.
    ///
    /// A reading is never held back until something agrees the tree stopped
    /// moving. Whether it moved is the vault's own answer; stillness is the
    /// `.noChange` tick that answer produces, drained like any other predicate.
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
            tripwireSignal: tripwireSignal,
            lineage: isMovingViewport ? .viewportMovement : .resting
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
        case .delivered(let read):
            return ObservationSettlement(commitOutcome: .committed(read.event))
        case .superseded:
            return ObservationSettlement(commitOutcome: .unavailable)
        }
    }

    /// Throws away what the vault holds, here and in the mirror.
    ///
    /// The reading after this one opens a new screen, because it has nothing to
    /// continue from.
    internal func discardCurrentObservation() async {
        await storeOwner.discardCurrentObservation()
        forgetReadState()
    }

    /// Throws the tree away when a screen change landed after the last reading.
    ///
    /// The notification is the world saying the screen went; what the vault
    /// holds describes the one before it.
    func discardIfScreenChangedSinceRead() async {
        guard let vault,
              await storeOwner.latestReadEvent() != nil,
              vault.accessibilityNotifications.latestScopedScreenChangedSequence
              > (await storeOwner.scopedScreenChangedSequence())
        else { return }
        await discardCurrentObservation()
    }

    /// Admits the tree as it stands right now.
    ///
    /// The only question left is identity: a reading belongs to the screen it
    /// was taken on, so structural UIKit state moving underneath it means the
    /// reading describes a screen we are no longer looking at. Accessibility
    /// notifications are movement on the same screen — UIKit posts them
    /// throughout a transition — so they let the reading through.
    func admitCurrentObservation(
        _ observation: InterfaceObservation? = nil,
        vault: TheVault,
        tripwireSignal: TheTripwire.TripwireSignal,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineage: ScreenLineage
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
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineage: lineage
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
