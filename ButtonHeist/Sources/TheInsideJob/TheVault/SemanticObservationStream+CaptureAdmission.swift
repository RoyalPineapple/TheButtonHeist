#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

// MARK: - Capture

@MainActor
extension Observation.Stream {
    internal func admittedVisibleObservation(
        boundary: SemanticObservationWaitBoundary
    ) async -> TheVault.State.Current? {
        if let current = admittedObservation(scope: .visible, after: nil) {
            return current
        }
        let historyIndex = vault.state.history.endIndex
        switch await waitForObservation(
            after: historyIndex,
            scope: .visible,
            boundary: boundary
        ) {
        case .observation(let current):
            return current
        case .cycleCompletedWithoutObservation,
             .deadlineReached,
             .cancelled,
             .unavailable:
            return nil
        }
    }

    /// Produces a fresh sample before admitting the visible baseline.
    /// Use this at an execution boundary where work may have started before the
    /// caller opened its notification or animation wait scopes.
    internal func refreshedVisibleObservation(
        boundary: SemanticObservationWaitBoundary
    ) async -> VisibleObservationOutcome {
        let historyIndex = vault.state.history.endIndex
        switch await waitForObservation(
            after: historyIndex,
            scope: .visible,
            boundary: boundary
        ) {
        case .observation(let current):
            return .committed(current)
        case .cancelled:
            return .unavailable(.cancelled)
        case .cycleCompletedWithoutObservation, .deadlineReached, .unavailable:
            return .unavailable(.sourceTreeUnavailable)
        }
    }

    /// Waits until canonical visible truth covers one causal notification range.
    /// Sampling advances only when a display pulse says UIKit advanced;
    /// cancellation remains the business deadline owner.
    internal func visibleObservation(
        covering coverage: AccessibilityNotificationCoverage
    ) async -> TheVault.State.Current? {
        await visibleObservation(
            covering: coverage,
            boundary: .cancellation,
            continuesThroughEmptyCycles: true
        )
    }

    /// Performs exactly one pulse-driven capture attempt.
    ///
    /// Terminal failure capture uses one completed pulse cycle so unavailable
    /// live state becomes incomplete evidence without arming another timer.
    internal func visibleObservationAfterNextCycle(
        covering coverage: AccessibilityNotificationCoverage
    ) async -> TheVault.State.Current? {
        let historyIndex = vault.state.history.endIndex
        switch await waitForObservation(
            after: historyIndex,
            scope: .visible,
            boundary: .observationCycle
        ) {
        case .observation:
            return currentObservation(covering: coverage)
        case .cycleCompletedWithoutObservation:
            return nil
        case .deadlineReached, .cancelled, .unavailable:
            return nil
        }
    }

    /// Advances successful pulse cycles until canonical truth covers a sealed
    /// notification range. The cutoff is finite, so each committed cycle either
    /// satisfies it or acknowledges the earlier frozen claim that precedes it.
    internal func visibleObservationThroughCausalCycles(
        covering coverage: AccessibilityNotificationCoverage
    ) async -> TheVault.State.Current? {
        await visibleObservation(
            covering: coverage,
            boundary: .observationCycle,
            continuesThroughEmptyCycles: false
        )
    }

    private func visibleObservation(
        covering coverage: AccessibilityNotificationCoverage,
        boundary: SemanticObservationWaitBoundary,
        continuesThroughEmptyCycles: Bool
    ) async -> TheVault.State.Current? {
        var historyIndex = vault.state.history.endIndex
        while !Task.isCancelled {
            if let current = currentObservation(covering: coverage) {
                return current
            }
            switch await waitForObservation(
                after: historyIndex,
                scope: .visible,
                boundary: boundary
            ) {
            case .observation:
                historyIndex = vault.state.history.endIndex
            case .cycleCompletedWithoutObservation:
                guard continuesThroughEmptyCycles else { return nil }
            case .deadlineReached,
                 .cancelled,
                 .unavailable:
                return nil
            }
        }
        return nil
    }

    /// Returns current truth only when the cycle-owned notification cursor has
    /// reached the supplied causal cutoff.
    internal func currentObservation(
        covering coverage: AccessibilityNotificationCoverage
    ) -> TheVault.State.Current? {
        guard hasCommittedObservation(covering: coverage) else { return nil }
        return vault.state.current
    }

    internal func hasCommittedObservation(
        covering coverage: AccessibilityNotificationCoverage
    ) -> Bool {
        vault.state.notificationIndex.sequence >= coverage.through.sequence
            && vault.state.scopedScreenChangedSequence
                >= coverage.scopedScreenChangedThrough
    }

    internal func admittedObservation(
        scope: SemanticObservationScope,
        after historyIndex: Int?
    ) -> TheVault.State.Current? {
        discardIfScreenChangedSinceRead()
        invalidateAdmissionIfSignalChanged(to: currentTripwireSignal())
        guard case .success(let current) = vault.state.admittedObservation(
            scope: scope,
            after: historyIndex
        ) else { return nil }
        return current
    }

    @discardableResult
    internal func commitObservation(
        _ committableObservation: CommittableInterfaceObservation,
        scope: SemanticObservationScope,
        notificationBatch: AccessibilityNotificationBatch
    ) -> Result<Observation.Publication, Observation.CaptureFailure> {
        let beginsNewBaseline = notificationBatch.gap != nil
        let resolvedNotificationBatch = completeNotificationHistory(
            in: notificationBatch
        )
        let sourceObservation = committableObservation.observation
        guard let notificationSnapshot = Observation.NotificationSnapshot(
            admittedNotifications: vault.admitNotifications(
                resolvedNotificationBatch.events
            ),
            through: resolvedNotificationBatch.through,
            scopedScreenChangedThrough: resolvedNotificationBatch.scopedScreenChangedThrough,
            gap: resolvedNotificationBatch.gap
        ) else {
            preconditionFailure("Incomplete notification evidence cannot be committed")
        }
        let admission = Observation.Admission(
            tree: sourceObservation.tree,
            tripwireSignal: committableObservation.tripwireSignal,
            discoveryCommitPolicy: committableObservation.discoveryCommitPolicy,
            lineage: committableObservation.lineage,
            scope: scope,
            notifications: notificationSnapshot,
            keyboardVisible: vault.keyboardVisible,
            timestamp: Date(),
            viewportFrames: sourceObservation.tree.viewportFrames,
            geometryTolerance: CoarseFrameComparison.currentGeometryTolerance
        )
        switch vault.state.commitObservation(
            admission,
            sourceObservation: sourceObservation,
            beginningNewBaseline: beginsNewBaseline
        ) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let publication):
            publish(publication)
            completeObservationWaiters()
            return .success(publication)
        }
    }

    /// Reads the tree once and emits what it read.
    ///
    /// A reading is never held back until something agrees the tree stopped
    /// moving. Whether it moved is the vault's own answer; stillness is the
    /// `.noChange` event that answer produces, drained like any other predicate.
    internal func commitCurrentInterfaceObservation(
        tripwireSignal: TheTripwire.TripwireSignal,
        scope: SemanticObservationScope,
        notificationBatch: AccessibilityNotificationBatch
    ) async -> VisibleObservationOutcome {
        guard !Task.isCancelled else {
            return .unavailable(.cancelled)
        }
        guard let captured = vault.captureVisibleObservation() else {
            return .unavailable(.sourceTreeUnavailable)
        }
        let admission = admitCurrentObservation(
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
        guard !Task.isCancelled else {
            return .unavailable(.cancelled)
        }
        switch commitObservation(
            committableObservation,
            scope: scope,
            notificationBatch: notificationBatch
        ) {
        case .success(let publication):
            return .committed(publication.current)
        case .failure(let failure):
            return .unavailable(failure)
        }
    }

    /// Throws away the Vault's current semantic truth.
    ///
    /// The reading after this one opens a new screen, because it has nothing to
    /// continue from.
    internal func discardCurrentObservation() {
        vault.state.discardCurrentObservation()
    }

    private func completeNotificationHistory(
        in batch: AccessibilityNotificationBatch
    ) -> AccessibilityNotificationBatch {
        batch.gap == nil ? batch : batch.beginningNewBaseline
    }

    /// Throws the tree away when a screen change landed after the last reading.
    ///
    /// The notification is the world saying the screen went; what the vault
    /// holds describes the one before it.
    func discardIfScreenChangedSinceRead() {
        guard vault.state.current != nil,
              vault.accessibilityNotifications.latestScopedScreenChangedSequence
              > vault.state.scopedScreenChangedSequence
        else { return }
        vault.state.invalidateCurrentObservationForScreenChange()
    }

    /// Admits the tree as it stands right now.
    ///
    /// The only question left is identity: a reading belongs to the screen it
    /// was taken on, so structural UIKit state moving underneath it means the
    /// reading describes a screen we are no longer looking at. Accessibility
    /// notifications are movement on the same screen — UIKit posts them
    /// throughout a transition — so they let the reading through.
    func admitCurrentObservation(
        _ observation: InterfaceObservation,
        vault: TheVault,
        tripwireSignal: TheTripwire.TripwireSignal,
        discoveryCommitPolicy: Navigation.DiscoveryCommitPolicy = .mergeIntoInterface,
        lineage: ScreenLineage
    ) -> Result<CommittableInterfaceObservation, Observation.CaptureFailure> {
        guard currentTripwireSignal().hierarchy == tripwireSignal.hierarchy else {
            return .failure(.hierarchyChangedDuringCapture)
        }
        return .success(CommittableInterfaceObservation.admitCaptured(
            observation,
            tripwireSignal: tripwireSignal,
            discoveryCommitPolicy: discoveryCommitPolicy,
            lineage: lineage
        ))
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
