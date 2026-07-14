#if canImport(UIKit)
#if DEBUG

import ButtonHeistSupport

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

internal enum ObservationEntrySequenceError: Error, Sendable, Equatable {
    case scopeMismatch(cursor: SemanticObservationScope, requested: SemanticObservationScope)
    case cursorUnavailable(ObservationCursor)
    case historyEvicted(ObservationGap)
}

internal struct ObservationLogPosition: Sendable, Equatable {
    fileprivate let rawValue: UInt64
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

private struct ObservationLogWaiterID: Sendable, Equatable, Hashable {
    let rawValue: UInt64
}

private struct ObservationLogWaiter: Sendable, Equatable {
    let scope: SemanticObservationScope
    var position: ObservationLogPosition
}

private enum ObservationLogDelivery: Sendable, Equatable {
    case entry(RetainedObservationRecord)
    case failure(ObservationEntrySequenceError)
    case cancelled
}

private struct ObservationLogEffect: Sendable, Equatable {
    let waiterID: ObservationLogWaiterID
    let delivery: ObservationLogDelivery
}

private enum SemanticObservationLogReducer {
    struct State {
        let retentionLimit: Int
        var records: [RetainedObservationRecord] = []
        var latestByScope: [SemanticObservationScope: ObservationRecordReference] = [:]
        var evictedThrough: [SemanticObservationScope: ObservationCursorReference] = [:]
        var waiters: [ObservationLogWaiterID: ObservationLogWaiter] = [:]
        var publicationState = SemanticObservationPublicationState.empty
        var nextPosition: UInt64 = 0
        var nextWaiterID: UInt64 = 0

        var retainedRecords: ArraySlice<RetainedObservationRecord> {
            records[...]
        }

        var latestPosition: ObservationLogPosition? {
            records.last?.position
        }

        func retainedRecords(
            after position: ObservationLogPosition
        ) -> ArraySlice<RetainedObservationRecord> {
            let index = records.firstIndex {
                $0.position.rawValue > position.rawValue
            } ?? records.endIndex
            return records[index...]
        }

        init(retentionLimit: Int) {
            precondition(retentionLimit > 0, "Observation history retention must be positive")
            self.retentionLimit = retentionLimit
        }
    }

    enum Input {
        case append(ObservationEntry)
        case next(
            id: ObservationLogWaiterID,
            cursor: ObservationCursor?,
            scope: SemanticObservationScope,
            position: ObservationLogPosition?
        )
        case cancel(ObservationLogWaiterID)
        case cancelAll
    }

    enum Output {
        case accepted([ObservationLogEffect])
        case rejected(SemanticObservationLogAppendError)
    }

    static func reserveWaiterID(in state: inout State) -> ObservationLogWaiterID {
        let id = ObservationLogWaiterID(rawValue: state.nextWaiterID)
        state.nextWaiterID += 1
        return id
    }

    static func reduce(_ input: Input, state: inout State) -> Output {
        switch input {
        case .append(let entry):
            return append(entry, state: &state)
        case .next(let id, let cursor, let scope, let position):
            return .accepted(next(
                id: id,
                cursor: cursor,
                scope: scope,
                position: position,
                state: &state
            ))
        case .cancel(let id):
            guard state.waiters.removeValue(forKey: id) != nil else {
                return .accepted([])
            }
            return .accepted([ObservationLogEffect(waiterID: id, delivery: .cancelled)])
        case .cancelAll:
            let effects = state.waiters.keys.sorted {
                $0.rawValue < $1.rawValue
            }.map {
                ObservationLogEffect(waiterID: $0, delivery: .cancelled)
            }
            state.waiters.removeAll()
            return .accepted(effects)
        }
    }

    private static func append(_ entry: ObservationEntry, state: inout State) -> Output {
        let scope = entry.cursor.scope
        switch (state.latestByScope[scope], entry.transition) {
        case (.none, .initial):
            break
        case (.some, .initial):
            return .rejected(.initialEntryAlreadyExists(scope: scope))
        case (.none, .sameGeneration), (.none, .screenBoundary):
            return .rejected(.missingInitialEntry(scope: scope))
        case (.some(let latest), .sameGeneration(let transition)):
            guard transition.previousCursor == latest.cursor else {
                return .rejected(.discontinuousLineage(
                    expected: latest.cursor,
                    actual: transition.previousCursor
                ))
            }
        case (.some(let latest), .screenBoundary(let transition)):
            guard transition.previousCursor == latest.cursor else {
                return .rejected(.discontinuousLineage(
                    expected: latest.cursor,
                    actual: transition.previousCursor
                ))
            }
        }

        let record = RetainedObservationRecord(
            position: ObservationLogPosition(rawValue: state.nextPosition),
            entry: entry
        )
        state.nextPosition += 1
        state.records.append(record)
        state.latestByScope[scope] = ObservationRecordReference(
            position: record.position,
            entry: entry
        )
        evictIfNeeded(scope: scope, state: &state)

        var effects: [ObservationLogEffect] = []
        let waiterIDs = Array(state.waiters.keys)
        for id in waiterIDs {
            guard var waiter = state.waiters[id] else { continue }
            if waiter.scope == scope {
                state.waiters.removeValue(forKey: id)
                effects.append(ObservationLogEffect(waiterID: id, delivery: .entry(record)))
            } else {
                waiter.position = record.position
                state.waiters[id] = waiter
            }
        }
        return .accepted(effects)
    }

    private static func next(
        id: ObservationLogWaiterID,
        cursor: ObservationCursor?,
        scope: SemanticObservationScope,
        position startingPosition: ObservationLogPosition?,
        state: inout State
    ) -> [ObservationLogEffect] {
        if let cursor, cursor.scope != scope {
            return [ObservationLogEffect(
                waiterID: id,
                delivery: .failure(.scopeMismatch(cursor: cursor.scope, requested: scope))
            )]
        }
        if let cursor, let gap = historyGap(after: cursor, scope: scope, state: state) {
            return [ObservationLogEffect(
                waiterID: id,
                delivery: .failure(.historyEvicted(gap))
            )]
        }

        let resolvedPosition: ObservationLogPosition
        if let startingPosition {
            resolvedPosition = startingPosition
        } else if cursor == nil {
            if let record = state.retainedRecords.first(where: {
                $0.entry.cursor.scope == scope
            }) {
                return [ObservationLogEffect(waiterID: id, delivery: .entry(record))]
            }
            let suspendedPosition = state.latestPosition ?? ObservationLogPosition(rawValue: 0)
            state.waiters[id] = ObservationLogWaiter(
                scope: scope,
                position: suspendedPosition
            )
            return []
        } else {
            guard let cursor else {
                preconditionFailure("Observation cursor resolution requires a cursor")
            }
            switch position(of: cursor, scope: scope, state: state) {
            case .success(let position):
                resolvedPosition = position
            case .failure(let error):
                return [ObservationLogEffect(waiterID: id, delivery: .failure(error))]
            }
        }

        if let record = state.retainedRecords(after: resolvedPosition).first(where: {
            $0.entry.cursor.scope == scope
        }) {
            return [ObservationLogEffect(waiterID: id, delivery: .entry(record))]
        }

        let suspendedPosition = state.latestPosition ?? resolvedPosition
        state.waiters[id] = ObservationLogWaiter(
            scope: scope,
            position: suspendedPosition
        )
        return []
    }

    private static func position(
        of cursor: ObservationCursor,
        scope: SemanticObservationScope,
        state: State
    ) -> Result<ObservationLogPosition, ObservationEntrySequenceError> {
        if let retained = state.retainedRecords.first(where: { $0.entry.cursor == cursor }) {
            return .success(retained.position)
        }
        if let latest = state.latestByScope[scope], latest.cursor == cursor {
            return .success(latest.position)
        }
        if let evicted = state.evictedThrough[scope], evicted.cursor == cursor {
            return .success(evicted.position)
        }
        return .failure(.cursorUnavailable(cursor))
    }

    private static func historyGap(
        after cursor: ObservationCursor,
        scope: SemanticObservationScope,
        state: State
    ) -> ObservationGap? {
        guard let evicted = state.evictedThrough[scope],
              evicted.cursor.sequence > cursor.sequence else { return nil }
        let current = state.latestByScope[scope]?.cursor ?? evicted.cursor
        return ObservationGap(
            reason: .historyEvicted,
            baseline: cursor,
            current: current
        )
    }

    private static func evictIfNeeded(
        scope: SemanticObservationScope,
        state: inout State
    ) {
        guard state.records.lazy.filter({
            $0.entry.cursor.scope == scope
        }).count > state.retentionLimit else { return }
        guard let index = state.records.firstIndex(where: {
            $0.entry.cursor.scope == scope
        }) else {
            preconditionFailure("Observation scope retention count lost its matching record")
        }
        let evicted = state.records.remove(at: index)
        state.evictedThrough[evicted.entry.cursor.scope] = ObservationCursorReference(
            position: evicted.position,
            cursor: evicted.entry.cursor
        )
    }
}

@MainActor
internal final class SemanticObservationLog {
    internal nonisolated static let defaultRetentionLimit = 256

    internal enum IteratorDelivery: Sendable, Equatable {
        case entry(ObservationEntry, position: ObservationLogPosition)
        case failure(ObservationEntrySequenceError)
        case cancelled
    }

    private var state: SemanticObservationLogReducer.State
    private var continuations: [ObservationLogWaiterID: TimedOneShot<IteratorDelivery>] = [:]

    internal var waiterCount: Int {
        state.waiters.count
    }

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
        state = SemanticObservationLogReducer.State(retentionLimit: retentionLimit)
    }

    internal func publish(_ publication: SemanticObservationPublication) throws {
        var candidate = state
        var publicationEffects: [ObservationLogEffect] = []
        for (scope, event) in publication.events.sorted(by: { $0.key < $1.key }) {
            guard scope == event.scope else {
                throw SemanticObservationLogAppendError.scopeKeyMismatch(
                    key: scope,
                    event: event.scope
                )
            }
            let entry = try Self.entry(
                for: event,
                after: candidate.latestByScope[scope]
            )
            switch SemanticObservationLogReducer.reduce(.append(entry), state: &candidate) {
            case .accepted(let effects):
                publicationEffects.append(contentsOf: effects)
            case .rejected(let error):
                throw error
            }
        }
        candidate.publicationState = .observing(sourceScope: publication.sourceScope)
        state = candidate
        perform(publicationEffects)
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

    internal func entries(
        after cursor: ObservationCursor,
        scope: SemanticObservationScope
    ) -> ObservationEntrySequence {
        ObservationEntrySequence(log: self, cursor: cursor, scope: scope)
    }

    internal func entries(scope: SemanticObservationScope) -> ObservationEntrySequence {
        ObservationEntrySequence(log: self, cursor: nil, scope: scope)
    }

    internal func retainedEntries(scope: SemanticObservationScope) -> [ObservationEntry] {
        state.retainedRecords.compactMap { record in
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
        return state.retainedRecords.first(where: { $0.entry.cursor == cursor })?.entry.event
    }

    internal func event(
        scope: SemanticObservationScope,
        sequence: SettledObservationSequence
    ) -> SettledSemanticObservationEvent? {
        if let latest = state.latestByScope[scope], latest.entry.event.sequence == sequence {
            return latest.entry.event
        }
        return state.retainedRecords.first(where: {
            $0.entry.event.scope == scope && $0.entry.event.sequence == sequence
        })?.entry.event
    }

    internal func settledCapture(
        scope: SemanticObservationScope,
        at sequence: SettledObservationSequence
    ) -> SettledCapture? {
        event(scope: scope, sequence: sequence)?.settledCapture
    }

    internal func next(
        after cursor: ObservationCursor?,
        scope: SemanticObservationScope,
        position: ObservationLogPosition?
    ) async -> IteratorDelivery {
        let waiterID = SemanticObservationLogReducer.reserveWaiterID(in: &state)
        let oneShot = TimedOneShot<IteratorDelivery>()
        let delivery = await oneShot.wait(
            cancellationValue: .cancelled,
            onRegistered: { continuation in
                continuations[waiterID] = continuation
                let output = SemanticObservationLogReducer.reduce(
                    .next(id: waiterID, cursor: cursor, scope: scope, position: position),
                    state: &state
                )
                guard case .accepted(let effects) = output else {
                    preconditionFailure("Observation iterator request cannot reject an append")
                }
                perform(effects)
            }
        )
        if case .cancelled = delivery {
            cancel(waiterID)
        }
        return delivery
    }

    internal func cancelAllWaiters() {
        let output = SemanticObservationLogReducer.reduce(.cancelAll, state: &state)
        guard case .accepted(let effects) = output else {
            preconditionFailure("Observation iterator shutdown cannot reject")
        }
        perform(effects)
    }

    private func cancel(_ waiterID: ObservationLogWaiterID) {
        let output = SemanticObservationLogReducer.reduce(.cancel(waiterID), state: &state)
        guard case .accepted(let effects) = output else {
            preconditionFailure("Observation iterator cancellation cannot reject an append")
        }
        perform(effects)
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

    private func perform(_ effects: [ObservationLogEffect]) {
        for effect in effects {
            guard let continuation = continuations.removeValue(forKey: effect.waiterID) else {
                preconditionFailure("Observation waiter effect has no continuation")
            }
            let delivery: IteratorDelivery = switch effect.delivery {
            case .entry(let record):
                .entry(record.entry, position: record.position)
            case .failure(let error):
                .failure(error)
            case .cancelled:
                .cancelled
            }
            continuation.resolve(returning: delivery)
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
