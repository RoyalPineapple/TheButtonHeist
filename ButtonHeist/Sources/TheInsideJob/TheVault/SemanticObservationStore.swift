#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

@MainActor
internal struct SemanticObservationStore {
    internal nonisolated static let defaultRetentionLimit = 256

    internal struct AdmittedObservation: Sendable, Equatable {
        internal let event: SettledObservationEvent
        internal let tripwireSignal: TheTripwire.TripwireSignal
    }

    private typealias EventsByScope = [SemanticObservationScope: SettledObservationEvent]

    internal struct Evidence {
        internal let interface: Interface
        internal let accessibilityNotifications: [AccessibilityNotificationEvidence]
        internal let firstResponder: AccessibilityTarget?
    }

    private enum Availability: Sendable, Equatable {
        case admitted(sourceScope: SemanticObservationScope, tripwireSignal: TheTripwire.TripwireSignal)
        case invalidated(sourceScope: SemanticObservationScope?)
    }

    private var history: SemanticObservationHistory
    private var availability = Availability.invalidated(sourceScope: nil)
    internal private(set) var interfaceTree: InterfaceTree = .empty
    internal private(set) var sequence: SettledObservationSequence = 0
    internal private(set) var notificationCursor = AccessibilityNotificationCursor.origin
    internal private(set) var scopedScreenChangedSequence: UInt64 = 0
    internal private(set) var settleFailureDiagnostic: String?
    private var replacementRequired = false

    internal struct CommittedObservation {
        internal let interfaceObservation: InterfaceObservation
        internal let event: SettledObservationEvent
        internal let fallbackReasons: [AccessibilityObservationFallbackReason]
    }

    internal var latestCommittedEvent: SettledObservationEvent? {
        switch availability {
        case .admitted(let sourceScope, _), .invalidated(.some(let sourceScope)):
            history.latestByScope[sourceScope]?.event
        case .invalidated(.none):
            nil
        }
    }

    internal var latestCommittedObservation: SettledObservation? {
        latestCommittedEvent?.settledObservation
    }

    internal var latestSettledObservationInvalidated: Bool {
        switch availability {
        case .invalidated:
            true
        case .admitted:
            false
        }
    }

    internal init(retentionLimit: Int = defaultRetentionLimit) {
        history = SemanticObservationHistory(retentionLimit: retentionLimit)
    }

    private mutating func record(
        _ events: EventsByScope,
        sourceScope: SemanticObservationScope,
        tripwireSignal: TheTripwire.TripwireSignal
    ) throws -> SettledObservationEvent {
        guard let committedEvent = events[sourceScope] else {
            preconditionFailure("Semantic observation scope did not fulfill itself")
        }
        var candidate = history
        for event in events.values.sorted(by: { $0.scope < $1.scope }) {
            try candidate.append(event)
        }
        history = candidate
        availability = .admitted(sourceScope: sourceScope, tripwireSignal: tripwireSignal)
        return committedEvent
    }

    internal mutating func invalidateCurrentObservation() {
        switch availability {
        case .admitted(let sourceScope, _):
            availability = .invalidated(sourceScope: sourceScope)
        case .invalidated:
            break
        }
    }

    @discardableResult
    internal mutating func invalidateIfSignalChanged(
        to tripwireSignal: TheTripwire.TripwireSignal
    ) -> Bool {
        guard case .admitted(let sourceScope, let admittedSignal) = availability,
              admittedSignal != tripwireSignal else { return false }
        availability = .invalidated(sourceScope: sourceScope)
        return true
    }

    internal func admittedObservation(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> AdmittedObservation? {
        guard case .admitted(let sourceScope, let tripwireSignal) = availability,
              let currentGeneration = history.latestByScope[sourceScope]?.cursor.generation,
              let latest = history.latestByScope[scope]?.event,
              latest.generation == currentGeneration,
              latest.sequence > (sequence ?? 0) else {
            return nil
        }
        return AdmittedObservation(event: latest, tripwireSignal: tripwireSignal)
    }

    internal func read(
        after cursor: ObservationCursor?,
        scope: SemanticObservationScope
    ) -> ObservationHistoryRead {
        history.read(after: cursor, scope: scope)
    }

    internal func retainedEntries(scope: SemanticObservationScope) -> [ObservationEntry] {
        history.entries.filter { $0.cursor.scope == scope }
    }

    internal func latestCursor(scope: SemanticObservationScope) -> ObservationCursor? {
        history.latestByScope[scope]?.cursor
    }

    internal func event(at cursor: ObservationCursor) -> SettledObservationEvent? {
        if let latest = history.latestByScope[cursor.scope], latest.cursor == cursor {
            return latest.event
        }
        return history.entries.first(where: { $0.cursor == cursor })?.event
    }

    internal func event(
        scope: SemanticObservationScope,
        sequence: SettledObservationSequence
    ) -> SettledObservationEvent? {
        if let latest = history.latestByScope[scope], latest.event.sequence == sequence {
            return latest.event
        }
        return history.entries.first(where: {
            $0.event.scope == scope && $0.event.sequence == sequence
        })?.event
    }

    internal func settledCapture(
        scope: SemanticObservationScope,
        at sequence: SettledObservationSequence
    ) -> SettledCapture? {
        event(scope: scope, sequence: sequence)?.settledCapture
    }

    internal func observationWindow(
        from baseline: SettledCapture,
        through currentEvent: SettledObservationEvent
    ) -> ObservationWindow? {
        let projectedCurrentEvent = event(
            scope: baseline.cursor.scope,
            sequence: currentEvent.sequence
        ) ?? currentEvent
        guard let currentCursor = projectedCurrentEvent.cursor,
              let current = event(at: currentCursor)?.settledCapture else { return nil }
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

        let scopeEntries = retainedEntries(scope: current.cursor.scope)
        let retainedEntries = scopeEntries.filter {
            $0.cursor.sequence > baseline.cursor.sequence
                && $0.cursor.sequence <= current.cursor.sequence
        }
        let baselineIsRetained = scopeEntries.contains { $0.cursor == baseline.cursor }
        let currentIsRetained = retainedEntries.last?.cursor == current.cursor
        let retainedLineageStartsAtBaseline =
            retainedEntries.first?.transition.previousCursor == baseline.cursor
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

    internal mutating func commitObservation(
        _ committableObservation: CommittableInterfaceObservation,
        scope: SemanticObservationScope,
        notificationBatch: AccessibilityNotificationBatch,
        evidence: (InterfaceObservation) -> Evidence
    ) throws -> CommittedObservation {
        let previousTree = interfaceTree
        let candidateTree = switch scope {
        case .visible:
            previousTree.updatingViewport(with: committableObservation.observation)
        case .discovery:
            committableObservation.discoveryCommitPolicy == .replaceInterface
                ? committableObservation.observation.tree
                : previousTree.merging(committableObservation.observation.tree)
        }
        let classifiedContinuity = ScreenClassifier.classify(
            from: previousTree == .empty ? nil : previousTree,
            to: candidateTree,
            notifications: notificationBatch.events.map(\.kind),
            lineageEvidence: committableObservation.lineageEvidence
        )
        let continuity = replacementRequired
            ? ScreenContinuity.replacement(.screenChangedNotification)
            : classifiedContinuity
        let nextTree = continuity.isReplacement ? committableObservation.observation.tree : candidateTree
        let committedObservation = try committableObservation.observation.replacingTreeWithCurrentCapture(nextTree)
        let events = eventsForCommit(
            sourceScope: scope,
            notificationBatch: notificationBatch,
            observation: committedObservation,
            semanticSignal: committableObservation.tripwireSignal.semanticValue,
            continuity: continuity,
            evidence: evidence(committedObservation)
        )
        var next = self
        let committedEvent = try next.record(
            events,
            sourceScope: scope,
            tripwireSignal: committableObservation.tripwireSignal
        )
        next.interfaceTree = nextTree
        next.sequence = committedEvent.sequence
        next.notificationCursor = notificationBatch.through
        next.scopedScreenChangedSequence = notificationBatch.scopedScreenChangedThrough
        next.settleFailureDiagnostic = nil
        next.replacementRequired = false
        self = next
        return CommittedObservation(
            interfaceObservation: committedObservation,
            event: committedEvent,
            fallbackReasons: events.values.compactMap {
                $0.trace.captures.last?.transition.fallbackReason
            }
        )
    }

    internal mutating func requireReplacement() {
        invalidateCurrentObservation()
        replacementRequired = true
        settleFailureDiagnostic = nil
    }

    internal mutating func clearCurrentInterface() {
        interfaceTree = .empty
        requireReplacement()
    }

    internal mutating func recordSettleFailure(_ diagnostic: String?) {
        settleFailureDiagnostic = diagnostic
    }

    private func eventsForCommit(
        sourceScope: SemanticObservationScope,
        notificationBatch: AccessibilityNotificationBatch,
        observation: InterfaceObservation,
        semanticSignal: TheTripwire.SemanticSignal,
        continuity: ScreenContinuity,
        evidence: Evidence
    ) -> EventsByScope {
        let currentGeneration = latestCommittedEvent?.generation ?? .initial
        let eventGeneration = continuity.isReplacement
            ? currentGeneration.advanced()
            : currentGeneration
        var events: EventsByScope = [:]
        for fulfilledScope in sourceScope.fulfilledScopes {
            let previousEvent = history.latestByScope[fulfilledScope]?.event
            let settledObservation = SettledObservation(
                sequence: sequence + 1,
                scope: fulfilledScope,
                observation: observation,
                semanticSignal: semanticSignal
            )
            let previousCapture = previousEvent?.trace.captures.last
            let currentCapture = Self.capture(
                settledObservation: settledObservation,
                sequence: (previousCapture?.sequence ?? 0) + 1,
                parentHash: previousCapture?.hash,
                generation: eventGeneration,
                notificationBatch: notificationBatch,
                evidence: evidence,
                fallbackReason: continuity.fallbackReason
            )
            let trace = previousCapture.map {
                AccessibilityTrace(captures: [$0, currentCapture])
            } ?? AccessibilityTrace(capture: currentCapture)
            events[fulfilledScope] = SettledObservationEvent(
                generation: eventGeneration,
                continuity: continuity,
                settledObservation: settledObservation,
                previous: previousEvent?.settledObservation,
                previousCursor: previousEvent?.cursor,
                notificationSequence: notificationBatch.through.sequence,
                trace: trace
            )
        }
        return events
    }

    private static func capture(
        settledObservation: SettledObservation,
        sequence: Int,
        parentHash: String?,
        generation: ScreenGeneration,
        notificationBatch: AccessibilityNotificationBatch,
        evidence: Evidence,
        fallbackReason: AccessibilityObservationFallbackReason?
    ) -> AccessibilityTrace.Capture {
        let windows = settledObservation.semanticSignal.windows.enumerated().map { index, window in
            AccessibilityTrace.WindowContext(
                index: index,
                level: window.level,
                isKeyWindow: window.isKeyWindow
            )
        }
        return AccessibilityTrace.Capture(
            sequence: sequence,
            interface: evidence.interface,
            parentHash: parentHash,
            context: AccessibilityTrace.Context(
                firstResponder: evidence.firstResponder,
                screenId: settledObservation.observation.tree.id,
                observationGeneration: generation.rawValue,
                windowStack: windows
            ),
            transition: AccessibilityTrace.Transition(
                fallbackReason: fallbackReason,
                accessibilityNotifications: evidence.accessibilityNotifications,
                accessibilityNotificationGap: notificationBatch.gap
            )
        )
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
