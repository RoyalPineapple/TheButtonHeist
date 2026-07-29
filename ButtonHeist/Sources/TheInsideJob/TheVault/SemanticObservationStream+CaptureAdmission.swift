#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

// MARK: - Capture

@MainActor
extension Observation.Stream {
    internal func admittedVisibleObservation(timeout: Double?) async -> TheVault.State.Current? {
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
            let outcome = await refreshVisibleObservation()
            if case .committed(let current) = outcome {
                return current
            }
        }
        return nil
    }

    /// Produces a fresh sample before admitting the visible baseline.
    /// Use this at an execution boundary where work may have started before the
    /// caller opened its notification or animation wait scopes.
    internal func refreshedVisibleObservation(
        timeout: Double?
    ) async -> VisibleObservationOutcome {
        let subscription = subscribe(scope: .visible)
        defer { _ = subscription }

        let deadline = SemanticObservationDeadline(
            start: RuntimeElapsed.now,
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )
        var outcome = await refreshVisibleObservation()
        while deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            switch outcome {
            case .committed,
                 .unavailable(.runtimeUnavailable),
                 .unavailable(.cancelled):
                return outcome
            case .unavailable:
                outcome = await refreshVisibleObservation()
            }
        }
        return outcome
    }

    internal func admittedObservation(
        scope: SemanticObservationScope,
        after historyIndex: Int?
    ) async -> TheVault.State.Current? {
        await discardIfScreenChangedSinceRead()
        await invalidateAdmissionIfSignalChanged(to: currentTripwireSignal())
        guard case .success(let current) = await stateOwner.admittedObservation(
            scope: scope,
            after: historyIndex
        ) else { return nil }
        return current
    }

    @discardableResult
    internal func commitVisibleObservation(
        _ committableObservation: CommittableInterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> Observation.Publication {
        await publishCommittedObservation(
            committableObservation,
            scope: .visible,
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    internal func commitDiscoveryObservation(
        _ committableObservation: CommittableInterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> Observation.Publication {
        await publishCommittedObservation(
            committableObservation,
            scope: .discovery,
            notificationBatch: notificationBatch
        )
    }

    @discardableResult
    internal func commitDiscoveryObservation(
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> Observation.Publication? {
        guard let vault else {
            preconditionFailure("Observation.Stream cannot admit after TheVault is released")
        }
        let admission = await admitCurrentObservation(
            vault: vault,
            tripwireSignal: currentTripwireSignal(),
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineage: captureLineage
        )
        switch admission {
        case .success(let committableObservation):
            return await commitDiscoveryObservation(
                committableObservation,
                notificationBatch: notificationBatch
            )
        case .failure:
            return nil
        }
    }

    @discardableResult
    private func publishCommittedObservation(
        _ committableObservation: CommittableInterfaceObservation,
        scope: SemanticObservationScope,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> Observation.Publication {
        guard let vault else {
            preconditionFailure("Observation.Stream cannot commit after TheVault is released")
        }
        let resolvedNotificationBatch = notificationBatch
            ?? vault.accessibilityNotifications.checkpoint(
                after: .origin,
                selection: .unclaimedScoped
            )
        let sourceObservation = committableObservation.observation
        let notificationSnapshot = Observation.NotificationSnapshot(
            admittedNotifications: vault.admitNotifications(
                resolvedNotificationBatch.events
            ),
            through: resolvedNotificationBatch.through,
            scopedScreenChangedThrough: resolvedNotificationBatch.scopedScreenChangedThrough
        )
        let notificationAdmission: Observation.NotificationAdmission = notificationBatch == nil
            ? .passive(notificationSnapshot)
            : .action(notificationSnapshot)
        let admission = Observation.Admission(
            tree: sourceObservation.tree,
            tripwireSignal: committableObservation.tripwireSignal,
            discoveryCommitPolicy: committableObservation.discoveryCommitPolicy,
            lineage: committableObservation.lineage,
            scope: scope,
            notificationAdmission: notificationAdmission,
            keyboardVisible: vault.keyboardVisible,
            timestamp: Date(),
            viewportFrames: sourceObservation.tree.viewportFrames,
            geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
        )
        let publication = await stateOwner.commitAdmission(admission)
        if let reattached = try? sourceObservation.replacingTreeWithCurrentCapture(
            stateOwner.interfaceTree
        ) {
            vault.recordCommittedObservation(
                reattached,
                sourceObservation: sourceObservation
            )
        }
        publish(publication)
        await completeObservationWaiters()
        return publication
    }

    internal func refreshVisibleObservation(
        baselineTripwireSignal: TheTripwire.TripwireSignal? = nil
    ) async -> VisibleObservationOutcome {
        guard !Task.isCancelled else {
            return .unavailable(.cancelled)
        }
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
    ) async -> VisibleObservationOutcome {
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
    ) async -> VisibleObservationOutcome {
        await invalidateAdmissionIfSignalChanged(to: tripwireSignal)
        let task = Task { @MainActor in
            await self.captureVisibleObservation(tripwireSignal: tripwireSignal)
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
    ) async -> VisibleObservationOutcome {
        let completion = await refresh.task.value
        if visibleRefreshPhase.task?.token == refresh.token {
            visibleRefreshPhase = .idle
        }
        guard !Task.isCancelled else {
            return .unavailable(.cancelled)
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
    /// `.noChange` event that answer produces, drained like any other predicate.
    private func captureVisibleObservation(
        tripwireSignal: TheTripwire.TripwireSignal
    ) async -> VisibleObservationOutcome {
        await beforeVisibleReading()
        guard !Task.isCancelled else {
            return .unavailable(.cancelled)
        }
        guard let vault else {
            return .unavailable(.runtimeUnavailable)
        }
        guard let captured = vault.captureVisibleObservation() else {
            return .unavailable(.sourceTreeUnavailable)
        }
        let admission = await admitCurrentObservation(
            captured,
            vault: vault,
            tripwireSignal: tripwireSignal,
            lineage: captureLineage
        )
        let committableObservation: CommittableInterfaceObservation
        switch admission {
        case .success(let admitted):
            committableObservation = admitted
        case .failure(let failure):
            return .unavailable(failure)
        }
        let notificationIndex = await stateOwner.notificationIndex()
        let notificationBatch = vault.accessibilityNotifications.checkpoint(
            after: notificationIndex
        )
        guard !Task.isCancelled else {
            return .unavailable(.cancelled)
        }
        let publication = await commitVisibleObservation(
            committableObservation,
            notificationBatch: notificationBatch
        )
        return .committed(publication.current)
    }

    /// Throws away the Vault's current semantic truth.
    ///
    /// The reading after this one opens a new screen, because it has nothing to
    /// continue from.
    internal func discardCurrentObservation() async {
        await stateOwner.discardCurrentObservation()
    }

    /// Throws the tree away when a screen change landed after the last reading.
    ///
    /// The notification is the world saying the screen went; what the vault
    /// holds describes the one before it.
    func discardIfScreenChangedSinceRead() async {
        guard let vault,
              await stateOwner.current() != nil,
              vault.accessibilityNotifications.latestScopedScreenChangedSequence
              > (await stateOwner.scopedScreenChangedSequence())
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
    ) async -> Result<CommittableInterfaceObservation, Observation.CaptureFailure> {
        let reading = observation ?? vault.latestObservation
        guard currentTripwireSignal().hierarchy == tripwireSignal.hierarchy else {
            return .failure(.hierarchyChangedDuringCapture)
        }
        return .success(CommittableInterfaceObservation.admitCaptured(
            reading,
            tripwireSignal: tripwireSignal,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineage: lineage
        ))
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
