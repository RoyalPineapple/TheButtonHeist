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
    ) async -> TheVault.State.Current? {
        let subscription = subscribe(scope: .visible)
        defer { _ = subscription }

        let deadline = SemanticObservationDeadline(
            start: RuntimeElapsed.now,
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )
        while deadline.hasTimeRemaining(at: RuntimeElapsed.now) {
            let outcome = await refreshVisibleObservation()
            if case .committed(let current) = outcome {
                return current
            }
        }
        return nil
    }

    internal func admittedObservation(
        scope: SemanticObservationScope,
        after historyIndex: Int?
    ) async -> TheVault.State.Current? {
        await discardIfScreenChangedSinceRead()
        await discardIfSignalChanged(to: currentTripwireSignal())
        guard case .success(let current) = await stateOwner.admittedObservation(
            scope: scope,
            after: historyIndex
        ) else { return nil }
        return current
    }

    @discardableResult
    internal func commitSettledVisibleObservation(
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
    internal func commitSettledDiscoveryObservation(
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
    internal func commitSettledDiscoveryObservation(
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy,
        afterViewportMovement: Bool,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) async -> Observation.Publication? {
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
        let publication = await stateOwner.readAdmission(admission)
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
        await discardIfSignalChanged(to: tripwireSignal)
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
        guard let vault, !Task.isCancelled else {
            return .unavailable
        }
        guard let captured = vault.captureVisibleObservation() else {
            await recordFailedCapture(
                "the accessibility tree could not be read",
                observation: nil,
                vault: vault
            )
            return .unavailable
        }
        guard let committableObservation = await admitCurrentObservation(
            captured,
            vault: vault,
            tripwireSignal: tripwireSignal,
            lineage: isMovingViewport ? .viewportMovement : .resting
        ) else {
            return .unavailable
        }
        let notificationIndex = await stateOwner.notificationIndex()
        let notificationBatch = vault.accessibilityNotifications.checkpoint(
            after: notificationIndex
        )
        let publication = await commitSettledVisibleObservation(
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
    ) async -> CommittableInterfaceObservation? {
        let reading = observation ?? vault.latestObservation
        guard currentTripwireSignal().hierarchy == tripwireSignal.hierarchy else {
            await recordFailedCapture(
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

    private func recordFailedCapture(
        _ diagnostic: String?,
        observation: InterfaceObservation?,
        vault: TheVault
    ) async {
        await stateOwner.recordSettleFailure(diagnostic)
        await vault.recordFailedSettleDiagnosticEvidence(observation)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
