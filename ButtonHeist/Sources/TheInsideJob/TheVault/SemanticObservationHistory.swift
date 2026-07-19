#if canImport(UIKit)
#if DEBUG
import TheScore

internal enum SemanticObservationHistoryAppendError: Error, Sendable, Equatable {
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

internal enum ObservationHistoryReadError: Error, Sendable, Equatable {
    case scopeMismatch(cursor: SemanticObservationScope, requested: SemanticObservationScope)
    case cursorUnavailable(ObservationCursor)
    case historyEvicted(ObservationGap)
}

internal enum ObservationHistoryRead: Sendable, Equatable {
    case entry(ObservationEntry)
    case pending
    case failure(ObservationHistoryReadError)
}

internal struct SemanticObservationHistory {
    let retentionLimit: Int
    var entries: [ObservationEntry] = []
    var latestByScope: [SemanticObservationScope: ObservationEntry] = [:]
    var evictedThrough: [SemanticObservationScope: ObservationCursor] = [:]

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
            throw SemanticObservationHistoryAppendError.initialEntryAlreadyExists(scope: scope)
        case (.none, .sameGeneration), (.none, .screenBoundary):
            throw SemanticObservationHistoryAppendError.missingInitialEntry(scope: scope)
        case (.some(let latest), .sameGeneration(let transition)):
            guard transition.previousCursor == latest.cursor else {
                throw SemanticObservationHistoryAppendError.discontinuousLineage(
                    expected: latest.cursor,
                    actual: transition.previousCursor
                )
            }
        case (.some(let latest), .screenBoundary(let transition)):
            guard transition.previousCursor == latest.cursor else {
                throw SemanticObservationHistoryAppendError.discontinuousLineage(
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
    ) -> ObservationHistoryRead {
        guard let cursor else {
            return entries.first(where: { $0.cursor.scope == scope })
                .map(ObservationHistoryRead.entry) ?? .pending
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
        }).map(ObservationHistoryRead.entry) ?? .pending
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

#endif // DEBUG
#endif // canImport(UIKit)
