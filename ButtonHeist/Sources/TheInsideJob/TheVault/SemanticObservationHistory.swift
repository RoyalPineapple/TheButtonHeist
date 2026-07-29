#if canImport(UIKit)
#if DEBUG
import TheScore

extension Observation {
    /// The Vault-owned ordered event array.
    ///
    /// Position belongs to this collection. Events contain no cursor, index, or
    /// history bookkeeping.
    internal struct History: Sendable, Equatable, RandomAccessCollection {
        internal typealias Index = Int
        internal typealias Element = Observation.Event

        internal enum ReadError: Error, Sendable, Equatable {
            case rangeUnavailable
        }

        internal let retentionLimit: Int
        private var storage: [Observation.Event] = []
        private var firstRetainedIndex = 0
        private var screenChangesBeforeStorage = 0

        internal init(retentionLimit: Int) {
            precondition(retentionLimit > 0, "Observation history retention must be positive")
            self.retentionLimit = retentionLimit
        }

        internal var startIndex: Int { firstRetainedIndex }
        internal var endIndex: Int { firstRetainedIndex + storage.count }

        internal subscript(index: Int) -> Observation.Event {
            storage[index - firstRetainedIndex]
        }

        internal func index(after index: Int) -> Int {
            index + 1
        }

        internal func index(before index: Int) -> Int {
            index - 1
        }

        internal mutating func record(
            _ events: [Observation.Event],
            protectedBy protectedIndex: Int?
        ) -> Range<Int> {
            precondition(!events.isEmpty, "An observation must publish at least one event")
            let range = endIndex..<(endIndex + events.count)
            storage.append(contentsOf: events)
            prune(protectedBy: protectedIndex)
            return range
        }

        internal func events(in range: Range<Int>) throws(ReadError) -> ArraySlice<Observation.Event> {
            guard range.lowerBound >= startIndex,
                  range.upperBound <= endIndex
            else {
                throw .rangeUnavailable
            }
            let lowerBound = range.lowerBound - firstRetainedIndex
            let upperBound = range.upperBound - firstRetainedIndex
            return storage[lowerBound..<upperBound]
        }

        internal func events(after index: Int) throws(ReadError) -> ArraySlice<Observation.Event> {
            guard index <= endIndex else {
                throw .rangeUnavailable
            }
            return try events(in: index..<endIndex)
        }

        /// Screen generation at a position is the number of screen boundaries
        /// preceding it. The event and snapshot do not store this projection.
        internal func screenGeneration(at index: Int) -> Int {
            precondition(
                index >= startIndex && index <= endIndex,
                "Observation history index is unavailable"
            )
            return screenChangesBeforeStorage + storage
                .prefix(index - firstRetainedIndex)
                .reduce(into: 0) { count, event in
                    if case .screenChanged = event {
                        count += 1
                    }
                }
        }

        internal func evidence(
            in range: Range<Int>,
            baseline: Observation.Snapshot?,
            current: Observation.Snapshot?
        ) -> Observation.Evidence {
            do {
                return Observation.Evidence(
                    baseline: baseline,
                    current: current,
                    events: Array(try events(in: range)),
                    completeness: .complete
                )
            } catch {
                return Observation.Evidence(
                    baseline: baseline,
                    current: current,
                    events: [],
                    completeness: .incomplete
                )
            }
        }

        internal mutating func prune(protectedBy protectedIndex: Int?) {
            guard storage.count > retentionLimit else { return }
            let overflow = storage.count - retentionLimit
            let removableCount = protectedIndex.map {
                Swift.min(overflow, Swift.max(0, $0 - firstRetainedIndex))
            } ?? overflow
            guard removableCount > 0 else { return }
            screenChangesBeforeStorage += storage.prefix(removableCount).reduce(into: 0) { count, event in
                if case .screenChanged = event {
                    count += 1
                }
            }
            storage.removeFirst(removableCount)
            firstRetainedIndex += removableCount
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
