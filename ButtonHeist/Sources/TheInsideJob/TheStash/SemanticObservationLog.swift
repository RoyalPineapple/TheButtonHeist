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

private struct ObservationLogPosition: Sendable, Equatable {
    let rawValue: UInt64
}

private struct RetainedObservationRecord: Sendable, Equatable {
    let position: ObservationLogPosition
    let entry: ObservationEntry
}

private struct ObservationRecordReference: Sendable, Equatable {
    let position: ObservationLogPosition
    let entry: ObservationEntry

    var cursor: ObservationCursor {
        entry.cursor
    }
}

private struct ObservationCursorReference: Sendable, Equatable {
    let position: ObservationLogPosition
    let cursor: ObservationCursor
}

private enum SemanticObservationPublicationState: Sendable, Equatable {
    case empty
    case observing(sourceScope: SemanticObservationScope)
    case invalidated(sourceScope: SemanticObservationScope?)
}

private struct SemanticObservationLogState {
    let retentionLimit: Int
    var records: [RetainedObservationRecord] = []
    var latestByScope: [SemanticObservationScope: ObservationRecordReference] = [:]
    var evictedThrough: [SemanticObservationScope: ObservationCursorReference] = [:]
    var publicationState = SemanticObservationPublicationState.empty
    var nextPosition: UInt64 = 0

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

        let record = RetainedObservationRecord(
            position: ObservationLogPosition(rawValue: nextPosition),
            entry: entry
        )
        nextPosition += 1
        records.append(record)
        latestByScope[scope] = ObservationRecordReference(
            position: record.position,
            entry: entry
        )
        evictIfNeeded(scope: scope)
    }

    func read(
        after cursor: ObservationCursor?,
        scope: SemanticObservationScope
    ) -> ObservationLogRead {
        guard let cursor else {
            return records.first(where: { $0.entry.cursor.scope == scope })
                .map { .entry($0.entry) } ?? .pending
        }
        guard cursor.scope == scope else {
            return .failure(.scopeMismatch(cursor: cursor.scope, requested: scope))
        }
        if let gap = historyGap(after: cursor, scope: scope) {
            return .failure(.historyEvicted(gap))
        }
        guard let position = position(of: cursor, scope: scope) else {
            return .failure(.cursorUnavailable(cursor))
        }
        return records.first(where: {
            $0.position.rawValue > position.rawValue && $0.entry.cursor.scope == scope
        }).map { .entry($0.entry) } ?? .pending
    }

    private func position(
        of cursor: ObservationCursor,
        scope: SemanticObservationScope
    ) -> ObservationLogPosition? {
        if let retained = records.first(where: { $0.entry.cursor == cursor }) {
            return retained.position
        }
        if let latest = latestByScope[scope], latest.cursor == cursor {
            return latest.position
        }
        if let evicted = evictedThrough[scope], evicted.cursor == cursor {
            return evicted.position
        }
        return nil
    }

    private func historyGap(
        after cursor: ObservationCursor,
        scope: SemanticObservationScope
    ) -> ObservationGap? {
        guard let evicted = evictedThrough[scope],
              evicted.cursor.sequence > cursor.sequence else { return nil }
        return ObservationGap(
            reason: .historyEvicted,
            baseline: cursor,
            current: latestByScope[scope]?.cursor ?? evicted.cursor
        )
    }

    private mutating func evictIfNeeded(scope: SemanticObservationScope) {
        guard records.lazy.filter({
            $0.entry.cursor.scope == scope
        }).count > retentionLimit else { return }
        guard let index = records.firstIndex(where: {
            $0.entry.cursor.scope == scope
        }) else {
            preconditionFailure("Observation scope retention count lost its matching record")
        }
        let evicted = records.remove(at: index)
        evictedThrough[scope] = ObservationCursorReference(
            position: evicted.position,
            cursor: evicted.entry.cursor
        )
    }
}

@MainActor
internal final class SemanticObservationLog {
    internal nonisolated static let defaultRetentionLimit = 256

    private var state: SemanticObservationLogState

    internal var latestSourceEvent: SettledSemanticObservationEvent? {
        switch state.publicationState {
        case .observing(let sourceScope), .invalidated(.some(let sourceScope)):
            state.latestByScope[sourceScope]?.entry.event
        case .empty, .invalidated(.none):
            nil
        }
    }

    internal var latestObservation: SettledSemanticObservation? {
        latestSourceEvent?.observation
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
            (scope, reference.entry.event)
        })
    }

    internal init(retentionLimit: Int = defaultRetentionLimit) {
        state = SemanticObservationLogState(retentionLimit: retentionLimit)
    }

    internal func publish(_ publication: SemanticObservationPublication) throws {
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
        candidate.publicationState = .observing(sourceScope: publication.sourceScope)
        state = candidate
    }

    internal func beginScreenReplacement() {
        state.publicationState = .empty
    }

    internal func invalidateCurrentPublication() {
        switch state.publicationState {
        case .empty:
            state.publicationState = .invalidated(sourceScope: nil)
        case .observing(let sourceScope):
            state.publicationState = .invalidated(sourceScope: sourceScope)
        case .invalidated:
            break
        }
    }

    internal func previousEvent(
        for scope: SemanticObservationScope
    ) -> SettledSemanticObservationEvent? {
        state.latestByScope[scope]?.entry.event
    }

    internal func cleanEvent(
        scope: SemanticObservationScope,
        after sequence: SettledObservationSequence?
    ) -> SettledSemanticObservationEvent? {
        guard case .observing(let sourceScope) = state.publicationState,
              let currentGeneration = state.latestByScope[sourceScope]?.cursor.generation,
              let latest = state.latestByScope[scope]?.entry.event,
              latest.generation == currentGeneration,
              latest.sequence > (sequence ?? 0) else {
            return nil
        }
        return latest
    }

    internal func read(
        after cursor: ObservationCursor?,
        scope: SemanticObservationScope
    ) -> ObservationLogRead {
        state.read(after: cursor, scope: scope)
    }

    internal func retainedEntries(scope: SemanticObservationScope) -> [ObservationEntry] {
        state.records.compactMap { record in
            record.entry.cursor.scope == scope ? record.entry : nil
        }
    }

    internal func latestCursor(scope: SemanticObservationScope) -> ObservationCursor? {
        state.latestByScope[scope]?.cursor
    }

    internal func event(at cursor: ObservationCursor) -> SettledSemanticObservationEvent? {
        if let latest = state.latestByScope[cursor.scope], latest.cursor == cursor {
            return latest.entry.event
        }
        return state.records.first(where: { $0.entry.cursor == cursor })?.entry.event
    }

    internal func event(
        scope: SemanticObservationScope,
        sequence: SettledObservationSequence
    ) -> SettledSemanticObservationEvent? {
        if let latest = state.latestByScope[scope], latest.entry.event.sequence == sequence {
            return latest.entry.event
        }
        return state.records.first(where: {
            $0.entry.event.scope == scope && $0.entry.event.sequence == sequence
        })?.entry.event
    }

    internal func settledCapture(
        scope: SemanticObservationScope,
        at sequence: SettledObservationSequence
    ) -> SettledCapture? {
        event(scope: scope, sequence: sequence)?.settledCapture
    }

    internal func observationWindow(
        from baseline: SettledCapture,
        through currentEvent: SettledSemanticObservationEvent
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
        for event: SettledSemanticObservationEvent,
        after latest: ObservationRecordReference?
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
