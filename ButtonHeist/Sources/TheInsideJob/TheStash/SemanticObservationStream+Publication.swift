#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

@MainActor
extension SemanticObservationStream {
    internal func visibleEvidence(timeout: Double?) async -> ViewportObservationEvidence? {
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
        return ViewportObservationEvidence(
            viewportObservation: event.settledObservation.observation,
            settledObservationSequence: event.sequence,
            settleOutcome: outcome.outcome
        )
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
        _ = stash.reduceInterfaceGraph(
            with: proof.observation,
            scope: scope,
            continuity: continuity,
            discoveryCommitPolicy: proof.discoveryCommitPolicy
        )
        return publishCurrentSettledObservation(
            scope: scope,
            stash: stash,
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
        guard let stash else {
            let notificationBatch = notificationWindow?.capture()
            notificationWindow?.cancel()
            return ObservationSettlement(
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
        notificationIdentityObservation: InterfaceObservation? = nil
    ) -> SettledObservationEvent {
        let settledObservation: InterfaceObservation
        do {
            settledObservation = try InterfaceObservation.build(tree: stash.interfaceTree)
        } catch {
            preconditionFailure("Published semantic observation failed validation: \(error)")
        }
        let publication = SemanticObservationPublication.make(
            sourceScope: scope,
            sequence: runtimeState.sequence + 1,
            notificationBatch: notificationBatch,
            observation: settledObservation,
            semanticSignal: tripwire.tripwireSignal().semanticValue,
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
        observation: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch,
        notificationIdentityObservation: InterfaceObservation?,
        stash: TheStash
    ) -> [SemanticObservationScope: SemanticObservationPublication.Evidence] {
        Dictionary(uniqueKeysWithValues: sourceScope.fulfilledScopes.map { fulfilledScope in
            let referenceObservation = observation
            return (fulfilledScope, SemanticObservationPublication.Evidence(
                interface: stash.semanticInterfaceWithHash(for: referenceObservation).interface,
                accessibilityNotifications: stash.resolveAccessibilityNotificationEvidence(
                    notificationBatch.events,
                    identityObservation: notificationIdentityObservation ?? referenceObservation,
                    referenceObservation: referenceObservation
                ),
                firstResponder: stash.firstResponderTarget(in: referenceObservation.tree)
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
        stash: TheStash
    ) {
        runtimeState.recordSettleFailure(diagnostic)
        let observation = tree.map { tree in
            do {
                return try InterfaceObservation.build(tree: tree)
            } catch {
                preconditionFailure("Failed settle diagnostic observation failed validation: \(error)")
            }
        }
        stash.recordFailedSettleDiagnosticEvidence(observation)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
