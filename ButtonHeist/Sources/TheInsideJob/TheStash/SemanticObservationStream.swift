#if canImport(UIKit)
#if DEBUG
import Foundation
import ButtonHeistSupport

import TheScore

struct SettledSemanticObservation: Sendable {
    let sequence: SettledObservationSequence
    let scope: SemanticObservationScope
    let semanticSignal: TheTripwire.SemanticSignal
    private let tree: InterfaceTree

    var screen: InterfaceObservation {
        do {
            return try InterfaceObservation.build(tree: tree)
        } catch {
            preconditionFailure("Settled semantic observation failed validation: \(error)")
        }
    }

    init(
        sequence: SettledObservationSequence,
        scope: SemanticObservationScope,
        screen: InterfaceObservation,
        semanticSignal: TheTripwire.SemanticSignal
    ) {
        self.sequence = sequence
        self.scope = scope
        self.semanticSignal = semanticSignal
        self.tree = screen.tree
    }
}

struct SettledSemanticObservationEvent: Sendable {
    let generation: ObservationGeneration
    let sequence: SettledObservationSequence
    let scope: SemanticObservationScope
    let observation: SettledSemanticObservation
    let previous: SettledSemanticObservation?
    let previousCursor: ObservationCursor?
    let notificationSequence: UInt64
    let trace: AccessibilityTrace

    init(
        generation: ObservationGeneration = .initial,
        sequence: SettledObservationSequence,
        scope: SemanticObservationScope,
        observation: SettledSemanticObservation,
        previous: SettledSemanticObservation?,
        previousCursor: ObservationCursor? = nil,
        notificationSequence: UInt64 = 0,
        trace: AccessibilityTrace
    ) {
        self.generation = generation
        self.sequence = sequence
        self.scope = scope
        self.observation = observation
        self.previous = previous
        self.previousCursor = previousCursor
        self.notificationSequence = notificationSequence
        self.trace = trace
    }

    var cursor: ObservationCursor? {
        trace.captures.last.map {
            ObservationCursor(
                generation: generation,
                scope: scope,
                sequence: sequence,
                captureHash: $0.hash,
                notificationSequence: notificationSequence
            )
        }
    }

    var settledCapture: SettledCapture? {
        guard let cursor, let capture = trace.captures.last else { return nil }
        return SettledCapture(cursor: cursor, capture: capture)
    }

    func replacingGeneration(_ generation: ObservationGeneration) -> SettledSemanticObservationEvent {
        SettledSemanticObservationEvent(
            generation: generation,
            sequence: sequence,
            scope: scope,
            observation: observation,
            previous: previous,
            previousCursor: previousCursor,
            notificationSequence: notificationSequence,
            trace: trace
        )
    }

    var latestCaptureRef: AccessibilityTrace.CaptureRef? {
        trace.captures.last.map(AccessibilityTrace.CaptureRef.init(capture:))
    }
}

struct VisibleSemanticObservationEvidence {
    let screen: InterfaceObservation
    let settledObservationSequence: SettledObservationSequence?
    let settleOutcome: SettleOutcome
}

struct InterfaceObservationProof {
    private enum GenerationAdmission {
        case classifyAtCommit
        case replace(reason: AccessibilityObservationFallbackReason)

        var authoritativeReplacementClassification: ScreenClassifier.Classification? {
            guard case .replace(let reason) = self else { return nil }
            return .inferredScreenChange(reason: reason)
        }
    }

    let screen: InterfaceObservation
    private let generationAdmission: GenerationAdmission

    private init(
        screen: InterfaceObservation,
        generationAdmission: GenerationAdmission = .classifyAtCommit
    ) {
        self.screen = screen
        self.generationAdmission = generationAdmission
    }

    var authoritativeReplacementClassification: ScreenClassifier.Classification? {
        generationAdmission.authoritativeReplacementClassification
    }

    @MainActor static func settled(
        _ outcome: SettleSession.Outcome,
        stash: TheStash
    ) -> InterfaceObservationProof? {
        guard outcome.outcome.didSettleCleanly,
              let finalObservation = outcome.finalObservation else { return nil }
        let screen = stash.latestObservation
        guard screen.captureToken == finalObservation.captureToken,
              screen.tree == finalObservation.tree,
              SettleTimeline.fingerprint(of: screen.liveCapture.hierarchy.sortedElements)
                == finalObservation.fingerprint else { return nil }
        return InterfaceObservationProof(screen: screen)
    }

    @MainActor static func explored(
        _ exploration: Navigation.ExploredScreen,
        stash: TheStash
    ) -> InterfaceObservationProof? {
        guard exploration.screen.captureToken == stash.latestObservation.captureToken else {
            return nil
        }
        let generationAdmission: GenerationAdmission
        switch exploration.generationDisposition {
        case .preservesGeneration:
            generationAdmission = .classifyAtCommit
        case .replacesGeneration(let reason):
            generationAdmission = .replace(reason: reason)
        }
        return InterfaceObservationProof(screen: exploration.screen, generationAdmission: generationAdmission)
    }

    static func testing(_ screen: InterfaceObservation) -> InterfaceObservationProof {
        InterfaceObservationProof(screen: screen)
    }

}

struct PostActionSettleObservation {
    enum Result {
        case committed(SettledSemanticObservationEvent)
        case observedUnsettled(InterfaceTree, notificationBatch: AccessibilityNotificationBatch?)
        case unavailable(notificationBatch: AccessibilityNotificationBatch?)
    }

    let settle: SettleSession.Outcome
    let result: Result
}

private struct SemanticObservationFulfillmentState {
    typealias EventsByFulfilledScope = [SemanticObservationScope: SettledSemanticObservationEvent]

    struct Publication {
        let events: EventsByFulfilledScope
        let generation: ObservationGeneration
        let startsNewGeneration: Bool
    }

    struct CurrentFulfillment {
        let sourceEvent: SettledSemanticObservationEvent
        var eventsByFulfilledScope: EventsByFulfilledScope
    }

    enum State {
        case empty
        case observing(CurrentFulfillment)
        case invalidated(CurrentFulfillment?)
    }

    private var state: State = .empty

    var latestSourceEvent: SettledSemanticObservationEvent? {
        currentFulfillment?.sourceEvent
    }

    func previousEvent(for scope: SemanticObservationScope) -> SettledSemanticObservationEvent? {
        currentFulfillment?.eventsByFulfilledScope[scope] ?? currentFulfillment?.sourceEvent
    }

    var latestSettledObservationInvalidated: Bool {
        switch state {
        case .empty, .invalidated:
            true
        case .observing:
            false
        }
    }

    var latestObservation: SettledSemanticObservation? {
        latestSourceEvent?.observation
    }

    mutating func clear() {
        state = .empty
    }

    mutating func invalidate() {
        switch state {
        case .empty:
            state = .invalidated(nil)
        case .observing(let fulfillment):
            state = .invalidated(fulfillment)
        case .invalidated(.some(let fulfillment)):
            state = .invalidated(fulfillment)
        case .invalidated(.none):
            break
        }
    }

    @MainActor
    mutating func publish(
        sourceScope: SemanticObservationScope,
        sourceClassification: ScreenClassifier.Classification,
        sequence: SettledObservationSequence,
        generation: ObservationGeneration,
        notificationBatch: AccessibilityNotificationBatch,
        screen: InterfaceObservation,
        semanticSignal: TheTripwire.SemanticSignal,
        stash: TheStash,
        notificationIdentityScreen: InterfaceObservation? = nil
    ) -> Publication {
        let pendingAccessibilityNotifications = notificationBatch.events
        let notificationKinds = pendingAccessibilityNotifications.map(\.kind)
        let previousEvents = currentFulfillment?.eventsByFulfilledScope ?? [:]
        let sourcePreviousEvent = previousEvent(for: sourceScope)
        let sourceObservation = SettledSemanticObservation(
            sequence: sequence,
            scope: sourceScope,
            screen: screen.semanticObservationProjection(for: sourceScope),
            semanticSignal: semanticSignal
        )
        let startsNewGeneration = sourceClassification.isScreenReplacement
        let eventGeneration = startsNewGeneration ? generation.advanced() : generation
        var currentEvents = startsNewGeneration ? [:] : previousEvents
        var events: EventsByFulfilledScope = [:]
        for fulfilledScope in sourceScope.fulfilledScopes {
            let previousEvent = previousEvents[fulfilledScope]
                ?? (fulfilledScope == sourceScope ? sourcePreviousEvent : nil)
            let observation = fulfilledScope == sourceScope
                ? sourceObservation
                : SettledSemanticObservation(
                    sequence: sequence,
                    scope: fulfilledScope,
                    screen: screen.semanticObservationProjection(for: fulfilledScope),
                    semanticSignal: semanticSignal
                )
            let classification = fulfilledScope == sourceScope
                ? sourceClassification
                : ScreenClassifier.classify(
                    before: previousEvent.map {
                        ScreenClassifier.snapshot(of: $0.observation.screen.tree)
                    },
                    after: ScreenClassifier.snapshot(of: observation.screen.tree),
                    notifications: notificationKinds,
                    notificationGap: notificationBatch.gap
                )
            let fallbackReason = classification.fallbackReason
            if let fallbackReason {
                AccessibilityObservationFallbackLog.record(
                    fallbackReason,
                    source: .settledObservation
                )
            }
            let event = SemanticObservationEventFactory.makeEvent(
                observation: observation,
                previous: previousEvent,
                generation: eventGeneration,
                notificationBatch: notificationBatch,
                stash: stash,
                notificationIdentityScreen: notificationIdentityScreen,
                fallbackReason: fallbackReason
            )
            currentEvents[fulfilledScope] = event
            events[fulfilledScope] = event
        }
        guard let publishedSourceEvent = events[sourceScope] else {
            preconditionFailure("Semantic observation scope did not fulfill itself")
        }
        state = .observing(CurrentFulfillment(
            sourceEvent: publishedSourceEvent,
            eventsByFulfilledScope: currentEvents
        ))
        return Publication(
            events: events,
            generation: eventGeneration,
            startsNewGeneration: startsNewGeneration
        )
    }

    func cleanEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledSemanticObservationEvent? {
        guard case .observing(let fulfillment) = state,
              let latest = fulfillment.eventsByFulfilledScope[scope],
              latest.sequence > (sequence ?? 0)
        else {
            return nil
        }
        return latest
    }

    private var currentFulfillment: CurrentFulfillment? {
        switch state {
        case .empty:
            return nil
        case .observing(let fulfillment):
            return fulfillment
        case .invalidated(let fulfillment):
            return fulfillment
        }
    }
}

@MainActor
final class SemanticObservationStream {
    /// An active stream is an observation lease. Baseline cycles observe the
    /// visible world; subscribers can widen demand to discovery.
    typealias DiscoveryObservation = @MainActor () async -> Navigation.ExploredScreen?

    private enum PassiveObservationState {
        case stopped
        case running(
            task: Task<Void, Never>,
            discovery: DiscoveryObservation,
            settledReading: TheTripwire.PulseReading?
        )

        var isRunning: Bool {
            switch self {
            case .stopped:
                return false
            case .running:
                return true
            }
        }

        var task: Task<Void, Never>? {
            switch self {
            case .stopped:
                return nil
            case .running(let task, _, _):
                return task
            }
        }

        var discovery: DiscoveryObservation? {
            switch self {
            case .stopped:
                return nil
            case .running(_, let discovery, _):
                return discovery
            }
        }

        var settledReading: TheTripwire.PulseReading? {
            switch self {
            case .stopped:
                return nil
            case .running(_, _, let settledReading):
                return settledReading
            }
        }

        mutating func replaceDiscovery(_ discovery: @escaping DiscoveryObservation) {
            guard case .running(let task, _, let settledReading) = self else { return }
            self = .running(task: task, discovery: discovery, settledReading: settledReading)
        }

        mutating func updateSettledReading(_ reading: TheTripwire.PulseReading?) {
            guard case .running(let task, let discovery, _) = self else { return }
            self = .running(task: task, discovery: discovery, settledReading: reading)
        }
    }

    private weak var stash: TheStash?
    private let tripwire: TheTripwire
    // MARK: - Observation Bookkeeping

    private var scopePressure = SemanticObservationScopePressure()
    private let settledWaiters = SemanticObservationSettledWaiters()
    private let cycles = SemanticObservationCycles()

    // MARK: - Subscriber-Facing Settled Observation History

    private var settledSequence: SettledObservationSequence = 0
    private var observationGeneration = ObservationGeneration.initial
    private var eventHistory: [SemanticObservationScope: [SettledSemanticObservationEvent]] = [:]
    private static let eventHistoryLimit = 256
    private var fulfillmentState = SemanticObservationFulfillmentState()
    private var lastCommittedNotificationCursor = AccessibilityNotificationCursor.origin
    /// Bus sequence of the most recent scoped `screenChanged` at the latest
    /// settled commit; a later scoped `screenChanged` marks that commit as
    /// replaced.
    private var lastCommittedScopedScreenChangedSequence: UInt64 = 0
    var latestEvent: SettledSemanticObservationEvent? {
        fulfillmentState.latestSourceEvent
    }
    /// Invalidates only latest fulfilled events as clean waiter results.
    /// Settled semantic truth remains in `TheStash` until the next explicit
    /// commit.
    var latestSettledObservationInvalidated: Bool {
        fulfillmentState.latestSettledObservationInvalidated
    }
    private(set) var latestSettleFailureDiagnostic: String?

    // MARK: - Passive Observation Scheduling

    private var passiveObservationState: PassiveObservationState = .stopped

    var latestObservation: SettledSemanticObservation? {
        fulfillmentState.latestObservation
    }

    var isActive: Bool {
        passiveObservationState.isRunning
    }

    var settledWaiterCount: Int {
        settledWaiters.count
    }

    var cycleWaiterCount: Int {
        cycles.waiterCount
    }

    var activeObservationDemandCount: Int {
        scopePressure.activeDemandCount
    }

    var activeObservationDemandState: SemanticObservationDemandState {
        scopePressure.demandState
    }

    var hasActiveObservationDemand: Bool {
        scopePressure.hasActiveDemand
    }

    init(stash: TheStash, tripwire: TheTripwire) {
        self.stash = stash
        self.tripwire = tripwire
    }

    func start(discovery: @escaping DiscoveryObservation) {
        guard !passiveObservationState.isRunning else {
            passiveObservationState.replaceDiscovery(discovery)
            return
        }
        if let stash {
            AccessibilityNotificationObserver.shared.subscribe(stash.accessibilityNotifications)
        }
        fulfillmentState.invalidate()
        let task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.runPassiveObservationCycle()
            }
        }
        passiveObservationState = .running(task: task, discovery: discovery, settledReading: nil)
    }

    func stop() {
        passiveObservationState.task?.cancel()
        passiveObservationState = .stopped
        cycles.cancelRunningCycle()
        settledWaiters.cancelAll()
        cycles.completeAllWaiters()
        if let stash {
            AccessibilityNotificationObserver.shared.unsubscribe(stash.accessibilityNotifications)
            stash.accessibilityNotifications.clearPendingEvents()
        }
    }

    func subscribe(scope: SemanticObservationScope) -> SemanticObservationSubscription {
        let id = scopePressure.addSubscription(scope: scope)
        return SemanticObservationSubscription(id: id, scope: scope, stream: self)
    }

    func removeSubscription(_ id: UInt64) {
        scopePressure.removeSubscription(id)
    }

    func beginActiveObservationDemand(scope: SemanticObservationScope) -> SemanticObservationDemand {
        let id = scopePressure.addActiveDemand(scope: scope)
        return SemanticObservationDemand(id: id, scope: scope, stream: self)
    }

    func removeActiveObservationDemand(_ id: UInt64) {
        scopePressure.removeActiveDemand(id)
    }

    func subscribedObservationScope() -> SemanticObservationScope {
        scopePressure.subscribedObservationScope()
    }

    func settledEvent(
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
            if scope == .visible {
                return cleanEvent(scope: scope, after: requiredSequence)
            }
            await cycles.waitForNextCycle(scope: scope, after: cycles.cursor())
            return cleanEvent(scope: scope, after: requiredSequence)
        }

        if sequence == nil, scope == .visible {
            if isActive {
                await cycles.waitForNextCycle(scope: scope, after: cycles.cursor())
            } else {
                return await waitForNextSettledEvent(
                    scope: scope,
                    after: latestObservation?.sequence,
                    timeout: timeout
                )
            }
        }

        if let latest = cleanEvent(scope: scope, after: requiredSequence) {
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

    func visibleEvidence(timeout: Double?) async -> VisibleSemanticObservationEvidence? {
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
    func commitSettledVisibleObservation(
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
    func commitSettledDiscoveryObservation(
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
    func commitExploredDiscoveryObservation(
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
    func commitVisibleObservationForTesting(
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
    func commitDiscoveryObservationForTesting(
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
        let classifiedSource = ScreenClassifier.classify(
            before: fulfillmentState.previousEvent(for: scope).map {
                ScreenClassifier.snapshot(
                    of: $0.observation.screen.semanticObservationProjection(for: scope).tree
                )
            },
            after: ScreenClassifier.snapshot(of: candidateScreen.tree),
            notifications: resolvedNotificationBatch.events.map(\.kind),
            notificationGap: resolvedNotificationBatch.gap
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

    func settlePostActionObservation(
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

    func clearSettledObservationHistory() {
        fulfillmentState.clear()
        observationGeneration = observationGeneration.advanced()
        eventHistory.removeAll()
        passiveObservationState.updateSettledReading(nil)
        latestSettleFailureDiagnostic = nil
        if let stash {
            lastCommittedNotificationCursor = stash.accessibilityNotifications.cursor()
        }
    }

    func invalidateLatestSettledObservation() {
        fulfillmentState.invalidate()
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
        fulfillmentState.invalidate()
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
        let publication = fulfillmentState.publish(
            sourceScope: scope,
            sourceClassification: sourceClassification,
            sequence: settledSequence,
            generation: observationGeneration,
            notificationBatch: notificationBatch,
            screen: settledScreen,
            semanticSignal: tripwire.tripwireSignal().semanticValue,
            stash: stash,
            notificationIdentityScreen: notificationIdentityScreen
        )
        guard let sourceEvent = publication.events[scope] else {
            preconditionFailure("Semantic observation scope did not fulfill itself")
        }
        observationGeneration = publication.generation
        if publication.startsNewGeneration {
            eventHistory.removeAll()
        }
        recordHistory(publication.events.values)
        lastCommittedScopedScreenChangedSequence = notificationBatch.scopedScreenChangedThrough
        lastCommittedNotificationCursor = notificationBatch.through
        latestSettleFailureDiagnostic = nil
        passiveObservationState.updateSettledReading(tripwire.latestReading)
        settledWaiters.completeWaiters(with: Array(publication.events.values))
        return sourceEvent
    }

    func observationWindow(
        from baseline: SettledCapture,
        through currentEvent: SettledSemanticObservationEvent
    ) -> ObservationWindow? {
        guard let current = currentEvent.settledCapture else { return nil }
        let gapReason: ObservationGap.Reason? = if baseline.cursor.scope != current.cursor.scope {
            .scopeChanged
        } else if current.cursor.sequence <= baseline.cursor.sequence {
            .noObservationAfterBaseline
        } else {
            nil
        }

        let history = eventHistory[current.cursor.scope] ?? []
        let baselineIsRetained = history.contains {
            $0.sequence == baseline.cursor.sequence && $0.cursor?.captureHash == baseline.cursor.captureHash
        }
        let directLineage = currentEvent.previousCursor?.sequence == baseline.cursor.sequence
            && currentEvent.previousCursor?.captureHash == baseline.cursor.captureHash
        let currentIsRetained = history.contains {
            $0.sequence == current.cursor.sequence && $0.cursor?.captureHash == current.cursor.captureHash
        }
        let completeness: Completeness
        if let gapReason {
            completeness = .incomplete(ObservationGap(
                reason: gapReason,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        } else if (baselineIsRetained || directLineage) && currentIsRetained {
            completeness = .complete
        } else {
            completeness = .incomplete(ObservationGap(
                reason: .historyUnavailable,
                baseline: baseline.cursor,
                current: current.cursor
            ))
        }

        let captures = [baseline] + history.lazy
            .filter {
                $0.scope == current.cursor.scope
                    && $0.sequence > baseline.cursor.sequence
                    && $0.sequence <= current.cursor.sequence
            }
            .compactMap(\.settledCapture)
        let windowCaptures = captures.count > 1 ? captures : [baseline, current]
        return ObservationWindow(
            baseline: baseline,
            current: current,
            captures: windowCaptures,
            completeness: completeness
        )
    }

    private func recordHistory(_ events: Dictionary<SemanticObservationScope, SettledSemanticObservationEvent>.Values) {
        for event in events {
            var history = eventHistory[event.scope] ?? []
            history.append(event)
            if history.count > Self.eventHistoryLimit {
                history.removeFirst(history.count - Self.eventHistoryLimit)
            }
            eventHistory[event.scope] = history
        }
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

        return await settledWaiters.wait(
            scope: scope,
            afterSequence: requiredSequence,
            timeout: timeout,
            currentEvent: {
                self.cleanEvent(scope: scope, after: requiredSequence)
            }
        )
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
        let currentSequence = latestEvent?.sequence
        if scope == .discovery {
            let baseline = sequence ?? currentSequence
            return max(baseline ?? 0, currentSequence ?? 0)
        }
        if sequence == nil, !isActive {
            return currentSequence
        }
        return sequence
    }

    private func cleanEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledSemanticObservationEvent? {
        fulfillmentState.cleanEvent(scope: scope, after: sequence)
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

private extension InterfaceObservation {
    func semanticObservationProjection(for scope: SemanticObservationScope) -> InterfaceObservation {
        switch scope {
        case .visible:
            return viewportOnly
        case .discovery:
            return self
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
