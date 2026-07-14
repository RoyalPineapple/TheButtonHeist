#if canImport(UIKit)
#if DEBUG

/// A replayable view over retained observation entries.
///
/// Iterators share only the retained log. Each iterator owns and advances its
/// cursor and retained position independently.
internal struct ObservationEntrySequence: AsyncSequence, Sendable {
    internal typealias Element = ObservationEntry
    internal typealias Failure = ObservationEntrySequenceError

    private let log: SemanticObservationLog
    private let cursor: ObservationCursor?
    private let scope: SemanticObservationScope

    internal init(
        log: SemanticObservationLog,
        cursor: ObservationCursor?,
        scope: SemanticObservationScope
    ) {
        self.log = log
        self.cursor = cursor
        self.scope = scope
    }

    internal func makeAsyncIterator() -> Iterator {
        Iterator(log: log, cursor: cursor, scope: scope)
    }

    internal struct Iterator: AsyncIteratorProtocol, Sendable {
        private let log: SemanticObservationLog
        private let scope: SemanticObservationScope
        private var cursor: ObservationCursor?
        private var position: ObservationLogPosition?
        private var isFinished = false

        fileprivate init(
            log: SemanticObservationLog,
            cursor: ObservationCursor?,
            scope: SemanticObservationScope
        ) {
            self.log = log
            self.cursor = cursor
            self.scope = scope
        }

        internal mutating func next() async throws(ObservationEntrySequenceError) -> ObservationEntry? {
            guard !isFinished else { return nil }
            switch await log.next(after: cursor, scope: scope, position: position) {
            case .entry(let entry, let nextPosition):
                cursor = entry.cursor
                position = nextPosition
                return entry
            case .failure(let error):
                isFinished = true
                throw error
            case .cancelled:
                isFinished = true
                return nil
            }
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
