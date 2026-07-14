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

    private enum PassiveObservationState {
        case stopped
        case running(
            task: Task<Void, Never>,
            discovery: DiscoveryObservation,
            settledReading: TheTripwire.PulseReading?
        )

        fileprivate var isRunning: Bool {
            switch self {
            case .stopped:
                return false
            case .running:
                return true
            }
        }

        fileprivate var task: Task<Void, Never>? {
            switch self {
            case .stopped:
                return nil
            case .running(let task, _, _):
                return task
            }
        }

        fileprivate var discovery: DiscoveryObservation? {
            switch self {
            case .stopped:
                return nil
            case .running(_, let discovery, _):
                return discovery
            }
        }

        fileprivate var settledReading: TheTripwire.PulseReading? {
            switch self {
            case .stopped:
                return nil
            case .running(_, _, let settledReading):
                return settledReading
            }
        }

        fileprivate mutating func replaceDiscovery(_ discovery: @escaping DiscoveryObservation) {
            guard case .running(let task, _, let settledReading) = self else { return }
            self = .running(task: task, discovery: discovery, settledReading: settledReading)
        }

        fileprivate mutating func updateSettledReading(_ reading: TheTripwire.PulseReading?) {
            guard case .running(let task, let discovery, _) = self else { return }
            self = .running(task: task, discovery: discovery, settledReading: reading)
        }
    }

    private enum GenerationLineage {
        case continuous(ObservationGeneration)
        case replacementRequired(ObservationGeneration)

        fileprivate var generation: ObservationGeneration {
            switch self {
            case .continuous(let generation), .replacementRequired(let generation):
                generation
            }
        }

        fileprivate mutating func requireReplacement() {
            self = .replacementRequired(generation)
        }

        fileprivate func admitting(
            _ classification: ScreenClassifier.Classification
        ) -> ScreenClassifier.Classification {
            switch self {
            case .continuous:
                classification
            case .replacementRequired:
                .screenChangedNotification
            }
        }

        fileprivate mutating func committed(_ generation: ObservationGeneration) {
            self = .continuous(generation)
        }
    }

    private weak var stash: TheStash?
    private let tripwire: TheTripwire
    // MARK: - Observation Bookkeeping

    private var scopePressure = SemanticObservationScopePressure()
    private let cycles = SemanticObservationCycles()
    private let observationLog = SemanticObservationLog()

    // MARK: - Subscriber-Facing Settled Observation History

    private var settledSequence: SettledObservationSequence = 0
    private var generationLineage = GenerationLineage.continuous(.initial)
    private var lastCommittedNotificationCursor = AccessibilityNotificationCursor.origin
    /// Bus sequence of the most recent scoped `screenChanged` at the latest
    /// settled commit; a later scoped `screenChanged` marks that commit as
    /// replaced.
    private var lastCommittedScopedScreenChangedSequence: UInt64 = 0
    internal var latestEvent: SettledSemanticObservationEvent? {
        observationLog.latestSourceEvent
    }
    /// Invalidates only latest fulfilled events as clean waiter results.
    /// Settled semantic truth remains in `TheStash` until the next explicit
    /// commit.
    internal var latestSettledObservationInvalidated: Bool {
        observationLog.latestSettledObservationInvalidated
    }
    internal private(set) var latestSettleFailureDiagnostic: String?

    // MARK: - Passive Observation Scheduling

    private var passiveObservationState: PassiveObservationState = .stopped

    internal var latestObservation: SettledSemanticObservation? {
        observationLog.latestObservation
    }

    internal var isActive: Bool {
        passiveObservationState.isRunning
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
        guard !passiveObservationState.isRunning else {
            passiveObservationState.replaceDiscovery(discovery)
            return
        }
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
        passiveObservationState = .running(task: task, discovery: discovery, settledReading: nil)
    }

    internal func stop() {
        passiveObservationState.task?.cancel()
        passiveObservationState = .stopped
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
                await cycles.waitForNextCycle(scope: scope, after: cycles.cursor())
            }
            return cleanEvent(scope: scope, after: requiredSequence)
        }

        let requiresFreshVisibleObservation = sequence == nil && scope == .visible && isActive
        if !requiresFreshVisibleObservation,
           let latest = cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        if isActive {
            await cycles.waitForNextCycle(scope: scope, after: cycles.cursor())
            if let latest = cleanEvent(scope: scope, after: requiredSequence) {
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
        if case .cancelled = outcome.outcome {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            recordNonActionFailedSettleDiagnosticEvidence(
                outcome.finalObservation?.tree,
                stash: stash
            )
            return nil
        }

        guard outcome.finalObservation != nil else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            recordNonActionFailedSettleDiagnosticEvidence(nil, stash: stash)
            return nil
        }

        if let proof = InterfaceObservationProof.settled(outcome, stash: stash) {
            let event = commitSettledVisibleObservation(proof)
            return VisibleSemanticObservationEvidence(
                screen: event.observation.screen,
                settledObservationSequence: event.sequence,
                settleOutcome: outcome.outcome
            )
        }

        latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
        recordNonActionFailedSettleDiagnosticEvidence(
            outcome.finalObservation?.tree,
            stash: stash
        )
        return nil
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
    internal func commitExploredDiscoveryObservation(
        _ exploration: Navigation.ExploredScreen,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledSemanticObservationEvent? {
        guard let stash,
              let proof = InterfaceObservationProof.explored(exploration, stash: stash) else {
            return nil
        }
        return commitSettledDiscoveryObservation(proof, notificationBatch: notificationBatch)
    }

    @discardableResult
    internal func commitVisibleObservationForTesting(
        _ screen: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> SettledSemanticObservationEvent {
        commitSettledVisibleObservation(
            .testing(screen),
            notificationBatch: notificationBatch,
            notificationIdentityScreen: notificationIdentityScreen
        )
    }

    @discardableResult
    internal func commitDiscoveryObservationForTesting(
        _ screen: InterfaceObservation,
        notificationBatch: AccessibilityNotificationBatch? = nil
    ) -> SettledSemanticObservationEvent {
        commitSettledDiscoveryObservation(.testing(screen), notificationBatch: notificationBatch)
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
            ?? stash.accessibilityNotifications.checkpoint(after: lastCommittedNotificationCursor)
        let candidateScreen = proof.screen.semanticObservationProjection(for: scope)
        let classifiedSource = SemanticObservationGenerationClassifier.classify(
            currentGeneration: generationLineage.generation,
            previousInScope: observationLog.previousEvent(for: scope),
            latestSource: observationLog.latestSourceEvent,
            candidate: candidateScreen,
            scope: scope,
            notifications: resolvedNotificationBatch.events.map(\.kind)
        )
        let sourceClassification = proof.authoritativeReplacementClassification
            ?? classifiedSource
        switch scope {
        case .visible:
            stash.commitVisibleInterface(proof, classification: sourceClassification)
        case .discovery:
            stash.commitDiscoveryInterface(proof, classification: sourceClassification)
        }
        return publishCurrentSettledObservation(
            scope: scope,
            stash: stash,
            notificationBatch: resolvedNotificationBatch,
            sourceClassification: sourceClassification,
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

        if case .cancelled = outcome.outcome {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            recordPostActionFailedSettleDiagnosticEvidence(
                outcome.finalObservation?.tree,
                stash: stash
            )
            return PostActionSettleObservation(
                settle: outcome,
                result: .unavailable(notificationBatch: terminalActionNotificationBatch)
            )
        }

        guard let finalObservation = outcome.finalObservation else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
            recordPostActionFailedSettleDiagnosticEvidence(
                nil,
                stash: stash
            )
            return PostActionSettleObservation(
                settle: outcome,
                result: .unavailable(notificationBatch: terminalActionNotificationBatch)
            )
        }
        if let proof = InterfaceObservationProof.settled(outcome, stash: stash) {
            let notificationBatch = terminalActionNotificationBatch
                ?? stash.accessibilityNotifications.checkpoint(after: lastCommittedNotificationCursor)
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

        latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: outcome)
        recordPostActionFailedSettleDiagnosticEvidence(
            finalObservation.tree,
            stash: stash
        )
        guard !outcome.outcome.didSettleCleanly else {
            return PostActionSettleObservation(
                settle: outcome,
                result: .unavailable(notificationBatch: terminalActionNotificationBatch)
            )
        }
        return PostActionSettleObservation(
            settle: outcome,
            result: .observedUnsettled(
                finalObservation.tree,
                notificationBatch: terminalActionNotificationBatch
            )
        )
    }

    internal func requireScreenReplacement() {
        observationLog.beginScreenReplacement()
        generationLineage.requireReplacement()
        passiveObservationState.updateSettledReading(nil)
        latestSettleFailureDiagnostic = nil
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
              > lastCommittedScopedScreenChangedSequence
        else { return }
        observationLog.invalidateCurrentPublication()
    }

    private func publishCurrentSettledObservation(
        scope: SemanticObservationScope = .visible,
        stash: TheStash,
        notificationBatch: AccessibilityNotificationBatch,
        sourceClassification: ScreenClassifier.Classification,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> SettledSemanticObservationEvent {
        settledSequence += 1
        let settledScreen: InterfaceObservation
        do {
            settledScreen = try InterfaceObservation.build(tree: stash.interfaceTree)
        } catch {
            preconditionFailure("Published semantic observation failed validation: \(error)")
        }
        let admittedClassification = generationLineage.admitting(sourceClassification)
        let publication = SemanticObservationPublication.make(
            sourceScope: scope,
            sequence: settledSequence,
            notificationBatch: notificationBatch,
            screen: settledScreen,
            semanticSignal: tripwire.tripwireSignal().semanticValue,
            context: SemanticObservationPublication.Context(
                generationClassification: admittedClassification,
                generation: generationLineage.generation,
                previousEvents: observationLog.latestEventsByScope
            ),
            stash: stash,
            notificationIdentityScreen: notificationIdentityScreen
        )
        do {
            try observationLog.publish(publication)
        } catch {
            preconditionFailure("Semantic observation log rejected publication: \(error)")
        }
        generationLineage.committed(publication.generation)
        lastCommittedScopedScreenChangedSequence = notificationBatch.scopedScreenChangedThrough
        lastCommittedNotificationCursor = notificationBatch.through
        latestSettleFailureDiagnostic = nil
        passiveObservationState.updateSettledReading(tripwire.latestReading)
        return publication.sourceEvent
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

        if let latest = cleanEvent(scope: scope, after: requiredSequence) {
            return latest
        }

        let deadline = timeout.map {
            SemanticObservationDeadline(
                start: CFAbsoluteTimeGetCurrent(),
                timeoutSeconds: $0
            )
        }
        var cursor = observationLog.latestCursor(scope: scope)
        while deadline?.hasTimeRemaining(at: CFAbsoluteTimeGetCurrent()) != false {
            let remainingTimeout = deadline?.remainingSeconds()
            guard let entry = await nextObservationEntry(
                scope: scope,
                after: cursor,
                timeout: remainingTimeout
            ) else { return nil }
            if let latest = cleanEvent(scope: scope, after: requiredSequence) {
                return latest
            }
            cursor = entry.cursor
        }
        return nil
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

    private func cleanEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledSemanticObservationEvent? {
        observationLog.cleanEvent(scope: scope, after: sequence)
    }

    private func runPassiveObservationCycle() async {
        let scope = subscribedObservationScope()
        guard case .started(let cycle) = cycles.beginCycle(scope: scope) else {
            _ = await Task.cancellableSleep(for: .milliseconds(10))
            return
        }
        guard !Task.isCancelled else {
            cycles.finishCycle(token: cycle, didObserve: false)
            return
        }
        let didObserve = await performObservationCycle(scope: scope)
        guard !Task.isCancelled else {
            cycles.finishCycle(token: cycle, didObserve: false)
            return
        }
        cycles.finishCycle(token: cycle, didObserve: didObserve)
        guard didObserve else { return }
        await Task.yield()
    }

    private func performObservationCycle(scope: SemanticObservationScope) async -> Bool {
        guard let stash else {
            stop()
            return false
        }
        switch scope {
        case .visible:
            return await observeVisibleSemanticState(stash: stash)
        case .discovery:
            guard let discovery = passiveObservationState.discovery else {
                invalidateLatestSettledObservation()
                await Task.yield()
                return true
            }
            guard let exploration = await discovery() else {
                invalidateLatestSettledObservation()
                await Task.yield()
                return true
            }
            guard !Task.isCancelled else { return false }
            guard commitExploredDiscoveryObservation(exploration) != nil else {
                invalidateLatestSettledObservation()
                await Task.yield()
                return true
            }
            await Task.yield()
            return true
        }
    }

    private func observeVisibleSemanticState(stash: TheStash) async -> Bool {
        switch activeObservationDemandState {
        case .active:
            return await observeVisibleSemanticStateAtActiveCadence(stash: stash)
        case .idle:
            break
        }

        if let reading = tripwire.latestReading,
           !latestSettledObservationInvalidated,
           passiveObservationState.settledReading?.tick == reading.tick {
            _ = await Task.cancellableSleep(for: .milliseconds(100))
            return true
        }

        // Layer quiet is only advisory for passive semantic observation. Complex
        // apps can have unrelated CALayer motion forever; the AX-tree settle
        // loop below is the correctness signal for accessibility actions.
        let layerGateWasClear = tripwire.latestReading?.isSettled ?? tripwire.allClear()

        let baselineSignal = tripwire.tripwireSignal()
        let settleSession = SettleSession.live(stash: stash, tripwire: tripwire, timeoutMs: 1_000)
        let settle = await settleSession.run(
            start: CFAbsoluteTimeGetCurrent(),
            baselineTripwireSignal: baselineSignal
        )

        guard let proof = InterfaceObservationProof.settled(settle, stash: stash) else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(
                for: settle,
                layerGateWasClear: layerGateWasClear
            )
            recordNonActionFailedSettleDiagnosticEvidence(
                settle.finalObservation?.tree,
                stash: stash
            )
            await Task.yield()
            return true
        }

        guard !Task.isCancelled else { return false }
        _ = commitSettledVisibleObservation(proof)
        await Task.yield()
        return true
    }

    private func observeVisibleSemanticStateAtActiveCadence(stash: TheStash) async -> Bool {
        let baselineSignal = tripwire.tripwireSignal()
        let settle = await SemanticObservationSettleCadence.settleVisibleObservationAtActiveCadence(
            stash: stash,
            tripwire: tripwire,
            baselineTripwireSignal: baselineSignal,
            timeoutMs: SemanticObservationSettleCadence.activePassiveSettleTimeoutMs
        )

        guard let proof = InterfaceObservationProof.settled(settle, stash: stash) else {
            latestSettleFailureDiagnostic = SettleFailureDiagnostic.message(for: settle)
            recordNonActionFailedSettleDiagnosticEvidence(
                settle.finalObservation?.tree,
                stash: stash
            )
            await Task.yield()
            return true
        }

        guard !Task.isCancelled else { return false }
        _ = commitSettledVisibleObservation(proof)
        await Task.yield()
        return true
    }

    private func recordNonActionFailedSettleDiagnosticEvidence(
        _ tree: InterfaceTree?,
        stash: TheStash
    ) {
        recordFailedSettleDiagnosticEvidence(tree, stash: stash)
    }

    private func recordPostActionFailedSettleDiagnosticEvidence(
        _ tree: InterfaceTree?,
        stash: TheStash
    ) {
        recordFailedSettleDiagnosticEvidence(tree, stash: stash)
    }

    private func recordFailedSettleDiagnosticEvidence(
        _ tree: InterfaceTree?,
        stash: TheStash
    ) {
        let screen = tree.map { tree in
            do {
                return try InterfaceObservation.build(tree: tree)
            } catch {
                preconditionFailure("Failed settle diagnostic observation failed validation: \(error)")
            }
        }
        stash.recordFailedSettleDiagnosticEvidence(screen)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
