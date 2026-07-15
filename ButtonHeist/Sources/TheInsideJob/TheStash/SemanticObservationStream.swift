#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

/// Coordinates semantic observation scheduling, settlement, and publication.
@MainActor
internal final class SemanticObservationStream {
    /// An active stream is an observation lease. Baseline cycles observe the
    /// visible world; subscribers can widen demand to discovery.
    internal typealias DiscoveryObservation = @MainActor () async -> Navigation.ExploredScreen?

    private weak var stash: TheStash?
    private let tripwire: TheTripwire
    // MARK: - Observation Bookkeeping

    private var scopePressure = SemanticObservationScopePressure()
    private let cycles = SemanticObservationCycles()
    private let observationLog = SemanticObservationLog()

    // MARK: - Subscriber-Facing Settled Observation History

    private var runtimeState = SemanticObservationRuntimeState()
    internal var latestEvent: SettledSemanticObservationEvent? {
        observationLog.latestSourceEvent
    }
    /// Invalidates only latest fulfilled events as clean waiter results.
    /// Settled semantic truth remains in `TheStash` until the next explicit
    /// commit.
    internal var latestSettledObservationInvalidated: Bool {
        observationLog.latestSettledObservationInvalidated
    }
    internal var latestSettleFailureDiagnostic: String? {
        runtimeState.settleFailureDiagnostic
    }

    internal var latestObservation: SettledSemanticObservation? {
        observationLog.latestObservation
    }

    internal var isActive: Bool {
        runtimeState.isRunning
    }

    internal var observationReplayWaiterCount: Int {
        observationLog.waiterCount
    }

    internal var cycleWaiterCount: Int {
        cycles.waiterCount
    }

    internal var activeObservationDemandCount: Int {
        scopePressure.activeDemandCount
    }

    internal var activeObservationDemandState: SemanticObservationDemandState {
        scopePressure.demandState
    }

    internal var hasActiveObservationDemand: Bool {
        scopePressure.hasActiveDemand
    }

    internal init(stash: TheStash, tripwire: TheTripwire) {
        self.stash = stash
        self.tripwire = tripwire
    }

    internal func start(discovery: @escaping DiscoveryObservation) {
        guard !runtimeState.replaceDiscoveryIfRunning(discovery) else { return }
        if let stash {
            AccessibilityNotificationObserver.shared.subscribe(stash.accessibilityNotifications)
        }
        observationLog.invalidateCurrentPublication()
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runPassiveObservationCycle()
            }
        }
        runtimeState.start(task: task, discovery: discovery)
    }

    internal func stop() {
        runtimeState.stop()?.cancel()
        cycles.cancelRunningCycle()
        cycles.completeAllWaiters()
        observationLog.cancelAllWaiters()
        if let stash {
            AccessibilityNotificationObserver.shared.unsubscribe(stash.accessibilityNotifications)
        }
    }

    internal func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = scopePressure.addSubscription(scope: scope)
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    internal func removeSubscription(_ id: UInt64) {
        scopePressure.removeSubscription(id)
    }

    internal func beginActiveObservationDemand(scope: SemanticObservationScope) -> SemanticObservationDemand {
        let id = scopePressure.addActiveDemand(scope: scope)
        return SemanticObservationDemand(id: id, scope: scope, stream: self)
    }

    internal func removeActiveObservationDemand(_ id: UInt64) {
        scopePressure.removeActiveDemand(id)
    }

    internal func subscribedObservationScope() -> SemanticObservationScope {
        scopePressure.subscribedObservationScope()
    }

    internal func observationEntries(
        after cursor: ObservationCursor,
        scope: SemanticObservationScope
    ) -> ObservationEntrySequence {
        observationLog.entries(after: cursor, scope: scope)
    }

    internal func observationEntries(
        scope: SemanticObservationScope
    ) -> ObservationEntrySequence {
        observationLog.entries(scope: scope)
    }

    internal func latestObservationCursor(
        scope: SemanticObservationScope
    ) -> ObservationCursor? {
        observationLog.latestCursor(scope: scope)
    }

    internal func retainedObservationEntries(
        scope: SemanticObservationScope
    ) -> [ObservationEntry] {
        observationLog.retainedEntries(scope: scope)
    }

    internal func settledCapture(
        scope: SemanticObservationScope,
        at sequence: SettledObservationSequence
    ) -> SettledCapture? {
        observationLog.settledCapture(scope: scope, at: sequence)
    }

    internal func observationEvent(
        scope: SemanticObservationScope,
        at sequence: SettledObservationSequence
    ) -> SettledSemanticObservationEvent? {
        observationLog.event(scope: scope, sequence: sequence)
    }

    internal func settledEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        invalidateSettledObservationIfScreenChangedSinceCommit()
        let subscription = subscribe(scope: scope)
        defer { _ = subscription }

        let requiredSequence = baselineSequence(for: scope, after: sequence)

        if timeout == 0 {
            guard isActive else { return nil }
            if scope == .discovery {
                let fulfillment = await cycles.waitForNextCycle(
                    scope: scope,
                    after: cycles.cursor()
                )
                guard let fulfillment else { return nil }
                if let event = fulfilledEvent(
                    fulfillment,
                    scope: scope,
                    after: requiredSequence
                ) {
                    return event
                }
            }
            return observationLog.cleanEvent(scope: scope, after: requiredSequence)
        }

        let requiresFreshVisibleObservation = sequence == nil && scope == .visible && isActive
        if !requiresFreshVisibleObservation,
           let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        if isActive {
            let fulfillment = await cycles.waitForNextCycle(
                scope: scope,
                after: cycles.cursor()
            )
            guard let fulfillment else { return nil }
            if let event = fulfilledEvent(
                fulfillment,
                scope: scope,
                after: requiredSequence
            ) {
                return event
            }
            if let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
                return latest
            }
        }

        return await waitForNextSettledEvent(scope: scope, after: requiredSequence, timeout: timeout)
    }

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
            notifications: resolvedNotificationBatch.events.map(\.kind)
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
    private func invalidateSettledObservationIfScreenChangedSinceCommit() {
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

    internal func observationWindow(
        from baseline: SettledCapture,
        through currentEvent: SettledSemanticObservationEvent
    ) -> ObservationWindow? {
        let projectedCurrentEvent = observationLog.event(
            scope: baseline.cursor.scope,
            sequence: currentEvent.sequence
        ) ?? currentEvent
        guard let currentCursor = projectedCurrentEvent.cursor,
              let current = observationLog.event(at: currentCursor)?.settledCapture else { return nil }
        guard baseline.cursor.scope == current.cursor.scope else {
            return ObservationWindow.incomplete(
                baseline: baseline,
                current: current,
                retainedEntries: [],
                gap: ObservationGap(
                    reason: .scopeChanged,
                    baseline: baseline.cursor,
                    current: current.cursor
                )
            )
        }
        guard current.cursor.sequence > baseline.cursor.sequence else {
            return ObservationWindow.incomplete(
                baseline: baseline,
                current: current,
                retainedEntries: [],
                gap: ObservationGap(
                    reason: .noObservationAfterBaseline,
                    baseline: baseline.cursor,
                    current: current.cursor
                )
            )
        }

        let scopeEntries = observationLog.retainedEntries(scope: current.cursor.scope)
        let retainedEntries = scopeEntries.filter {
            $0.cursor.sequence > baseline.cursor.sequence
                && $0.cursor.sequence <= current.cursor.sequence
        }
        let baselineIsRetained = scopeEntries.contains { $0.cursor == baseline.cursor }
        let currentIsRetained = retainedEntries.last?.cursor == current.cursor
        let retainedLineageStartsAtBaseline = retainedEntries.first?.transition.previousCursor == baseline.cursor
        if currentIsRetained,
           baselineIsRetained || retainedLineageStartsAtBaseline {
            do {
                return try ObservationWindow(
                    baseline: baseline,
                    retainedEntries: retainedEntries
                )
            } catch {
                preconditionFailure("Observation log admitted discontinuous retained lineage: \(error)")
            }
        }

        let reason: ObservationGap.Reason = if let first = scopeEntries.first,
                                              baseline.cursor.sequence < first.cursor.sequence {
            .historyEvicted
        } else {
            .historyUnavailable
        }
        return ObservationWindow.incomplete(
            baseline: baseline,
            current: current,
            retainedEntries: retainedEntries,
            gap: ObservationGap(
                reason: reason,
                baseline: baseline.cursor,
                current: current.cursor
            )
        )
    }

    private func waitForNextSettledEvent(
        scope: SemanticObservationScope = .visible,
        after sequence: SettledObservationSequence?,
        timeout: Double?
    ) async -> SettledSemanticObservationEvent? {
        let requiredSequence = baselineSequence(for: scope, after: sequence)

        if let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        let deadline = timeout.map {
            SemanticObservationDeadline(
                start: CFAbsoluteTimeGetCurrent(),
                timeoutSeconds: $0
            )
        }
        var cursor = observationLog.latestCursor(scope: scope)
        while true {
            let now = CFAbsoluteTimeGetCurrent()
            guard deadline?.hasTimeRemaining(at: now) != false else { return nil }
            guard let entry = await nextObservationEntry(
                scope: scope,
                after: cursor,
                timeout: deadline?.remainingSeconds(at: now)
            ) else { return nil }
            if let latest = observationLog.cleanEvent(scope: scope, after: requiredSequence) {
                return latest
            }
            cursor = entry.cursor
        }
    }

    private func nextObservationEntry(
        scope: SemanticObservationScope,
        after cursor: ObservationCursor?,
        timeout: Double?
    ) async -> ObservationEntry? {
        let sequence = if let cursor {
            observationLog.entries(after: cursor, scope: scope)
        } else {
            observationLog.entries(scope: scope)
        }
        return await withTaskGroup(of: ObservationEntry?.self) { group in
            group.addTask {
                var iterator = sequence.makeAsyncIterator()
                return try? await iterator.next()
            }
            if let timeoutDuration = Self.observationWaitTimeout(timeout) {
                group.addTask {
                    guard await Task.cancellableSleep(for: timeoutDuration) else { return nil }
                    return nil
                }
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func observationWaitTimeout(_ timeout: Double?) -> Duration? {
        guard let timeout else { return nil }
        guard timeout > 0 else { return .zero }
        let nanoseconds = UInt64((timeout * 1_000_000_000).rounded(.up))
        return .nanoseconds(nanoseconds)
    }

    private static func timeoutMilliseconds(from timeout: Double?) -> Int {
        guard let timeout else { return SettleSession.defaultTimeoutMs }
        guard timeout > 0 else { return 0 }
        return max(1, Int((timeout * 1_000).rounded(.up)))
    }

    private func baselineSequence(
        for scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledObservationSequence? {
        if let sequence {
            return sequence
        }
        let currentSequence = latestEvent?.sequence
        if scope == .discovery {
            return currentSequence
        }
        if !isActive {
            return currentSequence
        }
        return nil
    }

    private func fulfilledEvent(
        _ fulfillment: SemanticObservationCycles.CycleFulfillment,
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledSemanticObservationEvent? {
        guard let settledSequence = fulfillment.settledSequence,
              settledSequence > (sequence ?? 0) else { return nil }
        return observationLog.event(scope: scope, sequence: settledSequence)
    }

    private func runPassiveObservationCycle() async {
        let scope = subscribedObservationScope()
        guard case .started(let cycle) = cycles.beginCycle(scope: scope) else {
            _ = await Task.cancellableSleep(for: .milliseconds(10))
            return
        }
        guard !Task.isCancelled else {
            cycles.finishCycle(token: cycle, result: .interrupted)
            return
        }
        let result = await performObservationCycle(scope: scope)
        guard !Task.isCancelled else {
            cycles.finishCycle(token: cycle, result: .interrupted)
            return
        }
        cycles.finishCycle(token: cycle, result: result)
        guard case .completed = result else { return }
        await Task.yield()
    }

    private func performObservationCycle(
        scope: SemanticObservationScope
    ) async -> SemanticObservationCycles.CycleResult {
        guard let stash else {
            stop()
            return .interrupted
        }
        switch scope {
        case .visible:
            return await observeVisibleSemanticState(stash: stash)
        case .discovery:
            guard let discovery = runtimeState.discovery else {
                invalidateLatestSettledObservation()
                return .completed(settledSequence: nil)
            }
            guard let exploration = await discovery() else {
                invalidateLatestSettledObservation()
                return .completed(settledSequence: nil)
            }
            guard !Task.isCancelled else { return .interrupted }
            return .completed(settledSequence: exploration.event.sequence)
        }
    }

    private func observeVisibleSemanticState(
        stash: TheStash
    ) async -> SemanticObservationCycles.CycleResult {
        let baselineSignal = tripwire.tripwireSignal()
        let settle: SettleSession.Outcome
        let layerGateWasClear: Bool?
        switch activeObservationDemandState {
        case .active:
            settle = await SemanticObservationSettleCadence.settleVisibleObservationAtActiveCadence(
                stash: stash,
                tripwire: tripwire,
                baselineTripwireSignal: baselineSignal,
                timeoutMs: SemanticObservationSettleCadence.activePassiveSettleTimeoutMs
            )
            layerGateWasClear = nil
        case .idle:
            if let reading = tripwire.latestReading,
               !latestSettledObservationInvalidated,
               runtimeState.settledReading?.tick == reading.tick {
                _ = await Task.cancellableSleep(for: .milliseconds(100))
                return .completed(settledSequence: nil)
            }
            // Layer quiet is advisory. AX-tree stability is the commit proof.
            layerGateWasClear = tripwire.latestReading?.isSettled ?? tripwire.allClear()
            settle = await SettleSession.live(stash: stash, tripwire: tripwire, timeoutMs: 1_000).run(
                start: CFAbsoluteTimeGetCurrent(),
                baselineTripwireSignal: baselineSignal
            )
        }

        guard let proof = admitSettledProof(
            settle,
            stash: stash,
            layerGateWasClear: layerGateWasClear
        ) else { return .completed(settledSequence: nil) }
        guard !Task.isCancelled else { return .interrupted }
        let event = commitSettledVisibleObservation(proof)
        return .completed(settledSequence: event.sequence)
    }

    private func admitSettledProof(
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
