#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

@MainActor
extension SemanticObservationStream {
    internal func visibleEvidence(timeout: Double?) async -> VisibleSemanticObservationEvidence? {
        let subscription = subscribe(scope: .visible)
        defer { _ = subscription }

        guard let stash else { return nil }

        let outcome = await SemanticObservationSettleCadence.settleVisibleObservationForCurrentDemand(
            demandState: activeObservationDemandState,
            stash: stash,
            tripwire: tripwire,
            baselineTripwireSignal: tripwire.tripwireSignal(),
            timeoutMs: Self.timeoutMilliseconds(from: timeout)
        )
        guard let proof = admitSettledProof(outcome, stash: stash) else { return nil }
        let event = commitSettledVisibleObservation(proof)
        return VisibleSemanticObservationEvidence(
            screen: event.observation.screen,
            settledObservationSequence: event.sequence,
            settleOutcome: outcome.outcome
        )
    }

    @discardableResult
    internal func commitSettledVisibleObservation(
        _ proof: InterfaceObservationProof,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> SettledSemanticObservationEvent {
        publishCommittedObservation(
            proof,
            scope: .visible,
            notificationBatch: notificationBatch,
            notificationIdentityScreen: notificationIdentityScreen
        )
    }

    @discardableResult
    internal func commitSettledDiscoveryObservation(
        _ proof: InterfaceObservationProof,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledSemanticObservationEvent {
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
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> SettledSemanticObservationEvent {
        guard let stash else {
            preconditionFailure("SemanticObservationStream cannot commit after TheStash is released")
        }
        let resolvedNotificationBatch = notificationBatch
            ?? stash.accessibilityNotifications.checkpoint(
                after: runtimeState.notificationCursor
            )
        let previousTree = stash.interfaceTree
        let candidateTree = switch scope {
        case .visible:
            previousTree.updatingViewport(with: proof.screen)
        case .discovery:
            proof.discoveryCommitPolicy == .replaceInterface
                ? proof.screen.tree
                : previousTree.merging(proof.screen.tree)
        }
        let previous = committedInterfaceObservation(from: previousTree)
        let candidate = committedInterfaceObservation(from: candidateTree) ?? .empty
        let classifiedContinuity = SemanticObservationGenerationClassifier.continuity(
            from: previous,
            to: candidate,
            notifications: resolvedNotificationBatch.events.map(\.kind),
            lineageEvidence: proof.lineageEvidence
        )
        let continuity = runtimeState.lineage.admitting(classifiedContinuity)
        if continuity.isReplacement {
            observationLog.beginScreenReplacement()
        }
        _ = stash.reduceInterfaceGraph(
            with: proof.screen,
            scope: scope,
            continuity: continuity,
            discoveryCommitPolicy: proof.discoveryCommitPolicy
        )
        return publishCurrentSettledObservation(
            scope: scope,
            stash: stash,
            notificationBatch: resolvedNotificationBatch,
            continuity: continuity,
            notificationIdentityScreen: notificationIdentityScreen
        )
    }

    internal func settlePostActionObservation(
        baselineTripwireSignal: TheTripwire.TripwireSignal,
        commitScope: SemanticObservationScope = .visible,
        settleOutcome providedOutcome: SettleSession.Outcome? = nil,
        notificationWindow: AccessibilityNotificationActionWindow? = nil
    ) async -> PostActionSettleObservation {
        guard let stash else {
            let notificationBatch = notificationWindow?.capture()
            notificationWindow?.cancel()
            return PostActionSettleObservation(
                settle: SettleSession.Outcome(
                    outcome: .cancelled(timeMs: 0),
                    events: [],
                    finalObservation: nil,
                    elementsByKey: [:]
                ),
                result: .unavailable(notificationBatch: notificationBatch)
            )
        }
        let outcome: SettleSession.Outcome
        if let providedOutcome {
            outcome = providedOutcome
        } else {
            outcome = await SemanticObservationSettleCadence.settleVisibleObservationForCurrentDemand(
                demandState: activeObservationDemandState,
                stash: stash,
                tripwire: tripwire,
                baselineTripwireSignal: baselineTripwireSignal,
                timeoutMs: SettleSession.defaultTimeoutMs
            )
        }

        let terminalActionNotificationBatch = notificationWindow?.capture()
        notificationWindow?.cancel()

        if let proof = admitSettledProof(outcome, stash: stash) {
            let notificationBatch = terminalActionNotificationBatch
                ?? stash.accessibilityNotifications.checkpoint(
                    after: runtimeState.notificationCursor
                )
            let event: SettledSemanticObservationEvent
            switch commitScope {
            case .visible:
                event = commitSettledVisibleObservation(
                    proof,
                    notificationBatch: notificationBatch,
                    notificationIdentityScreen: proof.screen
                )
            case .discovery:
                event = commitSettledDiscoveryObservation(
                    proof,
                    notificationBatch: notificationBatch
                )
            }
            return PostActionSettleObservation(settle: outcome, result: .committed(event))
        }
        return PostActionSettleObservation(
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
        guard let stash,
              !latestSettledObservationInvalidated,
              latestEvent != nil,
              stash.accessibilityNotifications.latestScopedScreenChangedSequence
              > runtimeState.scopedScreenChangedSequence
        else { return }
        observationLog.invalidateCurrentPublication()
    }

    private func publishCurrentSettledObservation(
        scope: SemanticObservationScope = .visible,
        stash: TheStash,
        notificationBatch: AccessibilityNotificationBatch,
        continuity: ScreenContinuity,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> SettledSemanticObservationEvent {
        let settledScreen: InterfaceObservation
        do {
            settledScreen = try InterfaceObservation.build(tree: stash.interfaceTree)
        } catch {
            preconditionFailure("Published semantic observation failed validation: \(error)")
        }
        let publication = SemanticObservationPublication.make(
            sourceScope: scope,
            sequence: runtimeState.sequence + 1,
            notificationBatch: notificationBatch,
            screen: settledScreen,
            semanticSignal: tripwire.tripwireSignal().semanticValue,
            context: SemanticObservationPublication.Context(
                continuity: continuity,
                generation: runtimeState.lineage.generation,
                previousEvents: observationLog.latestEventsByScope
            ),
            evidenceByScope: publicationEvidence(
                sourceScope: scope,
                screen: settledScreen,
                notificationBatch: notificationBatch,
                notificationIdentityScreen: notificationIdentityScreen,
                stash: stash
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
            try observationLog.publish(publication)
        } catch {
            preconditionFailure("Semantic observation log rejected publication: \(error)")
        }
        completeObservationWaiters()
        runtimeState.commit(
            publication,
            notificationBatch: notificationBatch,
            settledReading: tripwire.latestReading
        )
        return publication.sourceEvent
    }

    private func publicationEvidence(
        sourceScope: SemanticObservationScope,
        screen: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch,
        notificationIdentityScreen: InterfaceObservation?,
        stash: TheStash
    ) -> [SemanticObservationScope: SemanticObservationPublication.Evidence] {
        Dictionary(uniqueKeysWithValues: sourceScope.fulfilledScopes.map { fulfilledScope in
            let referenceScreen = screen
            return (fulfilledScope, SemanticObservationPublication.Evidence(
                interface: stash.semanticInterfaceWithHash(for: referenceScreen).interface,
                accessibilityNotifications: stash.resolveAccessibilityNotificationEvidence(
                    notificationBatch.events,
                    identityScreen: notificationIdentityScreen ?? referenceScreen,
                    referenceScreen: referenceScreen
                ),
                firstResponder: stash.firstResponderTarget(in: referenceScreen.tree)
            ))
        })
    }

    func admitSettledProof(
        _ outcome: SettleSession.Outcome,
        stash: TheStash,
        layerGateWasClear: Bool? = nil
    ) -> InterfaceObservationProof? {
        guard let proof = InterfaceObservationProof.settled(outcome, stash: stash) else {
            recordFailedSettle(
                SettleFailureDiagnostic.message(for: outcome, layerGateWasClear: layerGateWasClear),
                tree: outcome.finalObservation?.tree,
                stash: stash
            )
            return nil
        }
        return proof
    }

    private func postActionFailureResult(
        _ outcome: SettleSession.Outcome,
        notificationBatch: AccessibilityNotificationBatch?
    ) -> PostActionSettleObservation.Result {
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
        stash: TheStash
    ) {
        runtimeState.recordSettleFailure(diagnostic)
        let screen = tree.map { tree in
            do {
                return try InterfaceObservation.build(tree: tree)
            } catch {
                preconditionFailure("Failed settle diagnostic observation failed validation: \(error)")
            }
        }
        stash.recordFailedSettleDiagnosticEvidence(screen)
    }

    private func committedInterfaceObservation(
        from tree: InterfaceTree
    ) -> InterfaceObservation? {
        guard tree != .empty else { return nil }
        do {
            return try InterfaceObservation.build(tree: tree)
        } catch {
            preconditionFailure("Committed interface observation failed validation: \(error)")
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
