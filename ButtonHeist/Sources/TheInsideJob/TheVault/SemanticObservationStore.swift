#if canImport(UIKit)
#if DEBUG
import TheScore
import ThePlans

internal struct CleanSettledObservation: Sendable, Equatable {
    internal let event: SettledObservationEvent
    internal let tripwireSignal: TheTripwire.TripwireSignal
}

internal enum SemanticObservationLineage: Equatable {
    case continuous(ScreenGeneration)
    case replacementRequired(ScreenGeneration)

    internal var generation: ScreenGeneration {
        switch self {
        case .continuous(let value), .replacementRequired(let value): value
        }
    }

    internal func admitting(_ continuity: ScreenContinuity) -> ScreenContinuity {
        switch self {
        case .continuous: continuity
        case .replacementRequired: .replacement(.screenChangedNotification)
        }
    }
}

@MainActor
internal struct SemanticObservationStore {
    internal nonisolated static let defaultRetentionLimit = 256

    private typealias EventsByScope = [SemanticObservationScope: SettledObservationEvent]

    internal struct Evidence {
        internal let interface: Interface
        internal let accessibilityNotifications: [AccessibilityNotificationEvidence]
        internal let firstResponder: AccessibilityTarget?
    }

    private enum Availability: Sendable, Equatable {
        case empty
        case observing(sourceScope: SemanticObservationScope, tripwireSignal: TheTripwire.TripwireSignal)
        case invalidated(sourceScope: SemanticObservationScope?)
    }

    private var history: SemanticObservationHistory
    private var availability = Availability.empty
    internal private(set) var interfaceTree: InterfaceTree = .empty
    internal private(set) var sequence: SettledObservationSequence = 0
    internal private(set) var lineage: SemanticObservationLineage = .continuous(.initial)
    internal private(set) var notificationCursor = AccessibilityNotificationCursor.origin
    internal private(set) var scopedScreenChangedSequence: UInt64 = 0
    internal private(set) var settleFailureDiagnostic: String?

    internal struct Commit {
        internal let observation: InterfaceObservation
        internal let sourceEvent: SettledObservationEvent
        internal let fallbackReasons: [AccessibilityObservationFallbackReason]
    }

    internal var latestSourceEvent: SettledObservationEvent? {
        switch availability {
        case .observing(let sourceScope, _), .invalidated(.some(let sourceScope)):
            history.latestByScope[sourceScope]?.event
        case .empty, .invalidated(.none):
            nil
        }
    }

    internal var latestObservation: SettledObservation? {
        latestSourceEvent?.settledObservation
    }

    internal var latestSettledObservationInvalidated: Bool {
        switch availability {
        case .empty, .invalidated:
            true
        case .observing:
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
    ) throws {
        precondition(events[sourceScope] != nil, "Semantic observation scope did not fulfill itself")
        var candidate = history
        for (scope, event) in events.sorted(by: { $0.key < $1.key }) {
            guard scope == event.scope else {
                throw SemanticObservationHistoryAppendError.scopeKeyMismatch(
                    key: scope,
                    event: event.scope
                )
            }
            try candidate.append(Self.entry(
                for: event,
                after: candidate.latestByScope[scope]
            ))
        }
        history = candidate
        availability = .observing(sourceScope: sourceScope, tripwireSignal: tripwireSignal)
    }

    internal mutating func beginScreenReplacement() {
        availability = .empty
    }

    internal mutating func invalidateCurrentObservation() {
        switch availability {
        case .empty:
            availability = .invalidated(sourceScope: nil)
        case .observing(let sourceScope, _):
            availability = .invalidated(sourceScope: sourceScope)
        case .invalidated:
            break
        }
    }

    @discardableResult
    internal mutating func invalidateIfSignalChanged(
        to tripwireSignal: TheTripwire.TripwireSignal
    ) -> Bool {
        guard case .observing(let sourceScope, let admittedSignal) = availability,
              admittedSignal != tripwireSignal else { return false }
        availability = .invalidated(sourceScope: sourceScope)
        return true
    }

    internal func cleanObservation(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> CleanSettledObservation? {
        guard case .observing(let sourceScope, let tripwireSignal) = availability,
              let currentGeneration = history.latestByScope[sourceScope]?.cursor.generation,
              let latest = history.latestByScope[scope]?.event,
              latest.generation == currentGeneration,
              latest.sequence > (sequence ?? 0) else {
            return nil
        }
        return CleanSettledObservation(event: latest, tripwireSignal: tripwireSignal)
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
        _ proof: InterfaceObservationProof,
        scope: SemanticObservationScope,
        notificationBatch: AccessibilityNotificationBatch,
        evidence: (InterfaceObservation) -> Evidence
    ) throws -> Commit {
        let previousTree = interfaceTree
        let candidateTree = switch scope {
        case .visible:
            previousTree.updatingViewport(with: proof.observation)
        case .discovery:
            proof.discoveryCommitPolicy == .replaceInterface
                ? proof.observation.tree
                : previousTree.merging(proof.observation.tree)
        }
        let continuity = lineage.admitting(ScreenClassifier.classify(
            from: previousTree == .empty ? nil : previousTree,
            to: candidateTree,
            notifications: notificationBatch.events.map(\.kind),
            lineageEvidence: proof.lineageEvidence
        ))
        let nextTree = continuity.isReplacement ? proof.observation.tree : candidateTree
        let committedObservation = try proof.observation.replacingTreeWithCurrentCapture(nextTree)
        let events = eventsForCommit(
            sourceScope: scope,
            notificationBatch: notificationBatch,
            observation: committedObservation,
            semanticSignal: proof.tripwireSignal.semanticValue,
            continuity: continuity,
            evidence: evidence(committedObservation)
        )
        guard let sourceEvent = events[scope] else {
            preconditionFailure("Semantic observation scope did not fulfill itself")
        }

        var next = self
        if continuity.isReplacement {
            next.beginScreenReplacement()
        }
        try next.record(events, sourceScope: scope, tripwireSignal: proof.tripwireSignal)
        next.interfaceTree = nextTree
        next.sequence = sourceEvent.sequence
        next.lineage = .continuous(sourceEvent.generation)
        next.notificationCursor = notificationBatch.through
        next.scopedScreenChangedSequence = notificationBatch.scopedScreenChangedThrough
        next.settleFailureDiagnostic = nil
        self = next
        return Commit(
            observation: committedObservation,
            sourceEvent: sourceEvent,
            fallbackReasons: events.values.compactMap {
                $0.trace.captures.last?.transition.fallbackReason
            }
        )
    }

    internal mutating func requireReplacement() {
        beginScreenReplacement()
        lineage = .replacementRequired(lineage.generation)
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
        let eventGeneration = continuity.isReplacement
            ? lineage.generation.advanced()
            : lineage.generation
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

    private static func entry(
        for event: SettledObservationEvent,
        after latest: ObservationEntry?
    ) throws -> ObservationEntry {
        if event.previousCursor != latest?.cursor {
            throw SemanticObservationHistoryAppendError.eventLineageMismatch(
                scope: event.scope,
                expected: latest?.cursor,
                actual: event.previousCursor
            )
        }
        guard let latest else {
            return .initial(event)
        }
        if latest.cursor.generation == event.generation {
            return try .sameGeneration(event, after: latest.cursor)
        }
        return try .screenBoundary(event, replacing: latest.cursor)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
