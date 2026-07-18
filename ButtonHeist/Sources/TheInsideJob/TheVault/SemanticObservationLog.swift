#if canImport(UIKit)
#if DEBUG

internal enum SemanticObservationLogAppendError: Error, Sendable, Equatable {
    case initialEntryAlreadyExists(scope: SemanticObservationScope)
    case missingInitialEntry(scope: SemanticObservationScope)
    case discontinuousLineage(expected: ObservationCursor, actual: ObservationCursor)
    case eventLineageMismatch(
        scope: SemanticObservationScope,
        expected: ObservationCursor?,
        actual: ObservationCursor?
    )
    case scopeKeyMismatch(key: SemanticObservationScope, event: SemanticObservationScope)
}

internal enum ObservationLogReadError: Error, Sendable, Equatable {
    case scopeMismatch(cursor: SemanticObservationScope, requested: SemanticObservationScope)
    case cursorUnavailable(ObservationCursor)
    case historyEvicted(ObservationGap)
}

internal enum ObservationLogRead: Sendable, Equatable {
    case entry(ObservationEntry)
    case pending
    case failure(ObservationLogReadError)
}

internal struct CleanSettledObservation: Sendable, Equatable {
    internal let event: SettledObservationEvent
    internal let tripwireSignal: TheTripwire.TripwireSignal
}

private enum SemanticObservationPublicationState: Sendable, Equatable {
    case empty
    case observing(sourceScope: SemanticObservationScope, tripwireSignal: TheTripwire.TripwireSignal)
    case invalidated(sourceScope: SemanticObservationScope?)
}

private struct SemanticObservationLogState {
    let retentionLimit: Int
    var entries: [ObservationEntry] = []
    var latestByScope: [SemanticObservationScope: ObservationEntry] = [:]
    var evictedThrough: [SemanticObservationScope: ObservationCursor] = [:]
    var publicationState = SemanticObservationPublicationState.empty

    init(retentionLimit: Int) {
        precondition(retentionLimit > 0, "Observation history retention must be positive")
        self.retentionLimit = retentionLimit
    }

    mutating func append(_ entry: ObservationEntry) throws {
        let scope = entry.cursor.scope
        switch (latestByScope[scope], entry.transition) {
        case (.none, .initial):
            break
        case (.some, .initial):
            throw SemanticObservationLogAppendError.initialEntryAlreadyExists(scope: scope)
        case (.none, .sameGeneration), (.none, .screenBoundary):
            throw SemanticObservationLogAppendError.missingInitialEntry(scope: scope)
        case (.some(let latest), .sameGeneration(let transition)):
            guard transition.previousCursor == latest.cursor else {
                throw SemanticObservationLogAppendError.discontinuousLineage(
                    expected: latest.cursor,
                    actual: transition.previousCursor
                )
            }
        case (.some(let latest), .screenBoundary(let transition)):
            guard transition.previousCursor == latest.cursor else {
                throw SemanticObservationLogAppendError.discontinuousLineage(
                    expected: latest.cursor,
                    actual: transition.previousCursor
                )
            }
        }

        entries.append(entry)
        latestByScope[scope] = entry
        evictIfNeeded(scope: scope)
    }

    func read(
        after cursor: ObservationCursor?,
        scope: SemanticObservationScope
    ) -> ObservationLogRead {
        guard let cursor else {
            return entries.first(where: { $0.cursor.scope == scope })
                .map(ObservationLogRead.entry) ?? .pending
        }
        guard cursor.scope == scope else {
            return .failure(.scopeMismatch(cursor: cursor.scope, requested: scope))
        }
        if let gap = historyGap(after: cursor, scope: scope) {
            return .failure(.historyEvicted(gap))
        }
        let cursorIsKnown = entries.contains { $0.cursor == cursor }
            || latestByScope[scope]?.cursor == cursor
            || evictedThrough[scope] == cursor
        guard cursorIsKnown else {
            return .failure(.cursorUnavailable(cursor))
        }
        return entries.first(where: {
            $0.cursor.scope == scope && $0.cursor.sequence > cursor.sequence
        }).map(ObservationLogRead.entry) ?? .pending
    }

    private func historyGap(
        after cursor: ObservationCursor,
        scope: SemanticObservationScope
    ) -> ObservationGap? {
        guard let evicted = evictedThrough[scope],
              evicted.sequence > cursor.sequence else { return nil }
        return ObservationGap(
            reason: .historyEvicted,
            baseline: cursor,
            current: latestByScope[scope]?.cursor ?? evicted
        )
    }

    private mutating func evictIfNeeded(scope: SemanticObservationScope) {
        guard entries.lazy.filter({
            $0.cursor.scope == scope
        }).count > retentionLimit else { return }
        guard let index = entries.firstIndex(where: {
            $0.cursor.scope == scope
        }) else {
            preconditionFailure("Observation scope retention count lost its matching record")
        }
        evictedThrough[scope] = entries.remove(at: index).cursor
    }
}

@MainActor
internal final class SemanticObservationLog {
    internal nonisolated static let defaultRetentionLimit = 256

    private var state: SemanticObservationLogState

    internal var latestSourceEvent: SettledObservationEvent? {
        switch state.publicationState {
        case .observing(let sourceScope, _), .invalidated(.some(let sourceScope)):
            state.latestByScope[sourceScope]?.event
        case .empty, .invalidated(.none):
            nil
        }
    }

    internal var latestObservation: SettledObservation? {
        latestSourceEvent?.settledObservation
    }

    internal var latestSettledObservationInvalidated: Bool {
        switch state.publicationState {
        case .empty, .invalidated:
            true
        case .observing:
            false
        }
    }

    internal var latestEventsByScope: SemanticObservationPublication.EventsByScope {
        Dictionary(uniqueKeysWithValues: state.latestByScope.map { scope, reference in
            (scope, reference.event)
        })
    }

    internal init(retentionLimit: Int = defaultRetentionLimit) {
        state = SemanticObservationLogState(retentionLimit: retentionLimit)
    }

    internal func publish(
        _ publication: SemanticObservationPublication,
        tripwireSignal: TheTripwire.TripwireSignal
    ) throws {
        var candidate = state
        for (scope, event) in publication.events.sorted(by: { $0.key < $1.key }) {
            guard scope == event.scope else {
                throw SemanticObservationLogAppendError.scopeKeyMismatch(
                    key: scope,
                    event: event.scope
                )
            }
            try candidate.append(Self.entry(
                for: event,
                after: candidate.latestByScope[scope]
            ))
        }
        candidate.publicationState = .observing(
            sourceScope: publication.sourceScope,
            tripwireSignal: tripwireSignal
        )
        state = candidate
    }

    internal func beginScreenReplacement() {
        state.publicationState = .empty
    }

    internal func invalidateCurrentPublication() {
        switch state.publicationState {
        case .empty:
            state.publicationState = .invalidated(sourceScope: nil)
        case .observing(let sourceScope, _):
            state.publicationState = .invalidated(sourceScope: sourceScope)
        case .invalidated:
            break
        }
    }

    @discardableResult
    internal func invalidateIfSignalChanged(
        to tripwireSignal: TheTripwire.TripwireSignal
    ) -> Bool {
        guard case .observing(let sourceScope, let admittedSignal) = state.publicationState,
              admittedSignal != tripwireSignal else { return false }
        state.publicationState = .invalidated(sourceScope: sourceScope)
        return true
    }

    internal func previousEvent(
        for scope: SemanticObservationScope
    ) -> SettledObservationEvent? {
        state.latestByScope[scope]?.event
    }

    internal func cleanObservation(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> CleanSettledObservation? {
        guard case .observing(let sourceScope, let tripwireSignal) = state.publicationState,
              let currentGeneration = state.latestByScope[sourceScope]?.cursor.generation,
              let latest = state.latestByScope[scope]?.event,
              latest.generation == currentGeneration,
              latest.sequence > (sequence ?? 0) else {
            return nil
        }
        return CleanSettledObservation(event: latest, tripwireSignal: tripwireSignal)
    }

    internal func read(
        after cursor: ObservationCursor?,
        scope: SemanticObservationScope
    ) -> ObservationLogRead {
        state.read(after: cursor, scope: scope)
    }

    internal func retainedEntries(scope: SemanticObservationScope) -> [ObservationEntry] {
        state.entries.filter { $0.cursor.scope == scope }
    }

    internal func latestCursor(scope: SemanticObservationScope) -> ObservationCursor? {
        state.latestByScope[scope]?.cursor
    }

    internal func event(at cursor: ObservationCursor) -> SettledObservationEvent? {
        if let latest = state.latestByScope[cursor.scope], latest.cursor == cursor {
            return latest.event
        }
        return state.entries.first(where: { $0.cursor == cursor })?.event
    }

    internal func event(
        scope: SemanticObservationScope,
        sequence: SettledObservationSequence
    ) -> SettledObservationEvent? {
        if let latest = state.latestByScope[scope], latest.event.sequence == sequence {
            return latest.event
        }
        return state.entries.first(where: {
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

    private static func entry(
        for event: SettledObservationEvent,
        after latest: ObservationEntry?
    ) throws -> ObservationEntry {
        if event.previousCursor != latest?.cursor {
            throw SemanticObservationLogAppendError.eventLineageMismatch(
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
