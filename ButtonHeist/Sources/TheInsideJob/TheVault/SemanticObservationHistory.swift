#if canImport(UIKit)
#if DEBUG
import TheScore

private struct ObservationHistoryEntry: Sendable, Equatable {
    let event: Observation.Event
    let notificationGap: Observation.NotificationSequenceGap?
}

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
        private var storage: [ObservationHistoryEntry] = []
        private var firstRetainedIndex = 0
        private var screenChangesBeforeStorage = 0

        internal init(retentionLimit: Int) {
            precondition(retentionLimit > 0, "Observation history retention must be positive")
            self.retentionLimit = retentionLimit
        }

        internal var startIndex: Int { firstRetainedIndex }
        internal var endIndex: Int { firstRetainedIndex + storage.count }

        internal subscript(index: Int) -> Observation.Event {
            storage[index - firstRetainedIndex].event
        }

        internal func index(after index: Int) -> Int {
            index + 1
        }

        internal func index(before index: Int) -> Int {
            index - 1
        }

        internal mutating func record(
            _ events: [Observation.Event],
            notificationGap: AccessibilityNotificationGap? = nil,
            afterNotificationSequence: UInt64 = 0,
            protectedBy protectedIndex: Int?
        ) -> Result {
            precondition(!events.isEmpty, "An observation must publish at least one event")
            let range = endIndex..<(endIndex + events.count)
            let gap = notificationGap.map {
                Observation.NotificationSequenceGap(
                    afterSequence: afterNotificationSequence,
                    throughSequence: $0.droppedThroughSequence
                )
            }
            storage.append(contentsOf: events.enumerated().map { index, event in
                ObservationHistoryEntry(
                    event: event,
                    notificationGap: index == 0 ? gap : nil
                )
            })
            prune(protectedBy: protectedIndex)
            return Result(
                range: range,
                coverage: Self.coverage(for: gap.map { [$0] } ?? [])
            )
        }

        internal func events(in range: Range<Int>) throws(ReadError) -> ArraySlice<Observation.Event> {
            ArraySlice(try entries(in: range).map(\.event))
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
                .reduce(into: 0) { count, entry in
                    if case .screenChanged = entry.event {
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
                let entries = try entries(in: range)
                let gaps = entries.compactMap(\.notificationGap)
                return Observation.Evidence(
                    baseline: baseline,
                    events: entries.map(\.event),
                    current: current,
                    coverage: Self.coverage(for: gaps)
                )
            } catch {
                return Observation.Evidence(
                    baseline: baseline,
                    events: [],
                    current: current,
                    coverage: .incomplete(.historyUnavailable)
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
            screenChangesBeforeStorage += storage.prefix(removableCount).reduce(into: 0) { count, entry in
                if case .screenChanged = entry.event {
                    count += 1
                }
            }
            storage.removeFirst(removableCount)
            firstRetainedIndex += removableCount
        }

        private func entries(
            in range: Range<Int>
        ) throws(ReadError) -> ArraySlice<ObservationHistoryEntry> {
            guard range.lowerBound >= startIndex,
                  range.upperBound <= endIndex
            else {
                throw .rangeUnavailable
            }
            let lowerBound = range.lowerBound - firstRetainedIndex
            let upperBound = range.upperBound - firstRetainedIndex
            return storage[lowerBound..<upperBound]
        }

        private static func coverage(
            for gaps: [Observation.NotificationSequenceGap]
        ) -> Observation.Coverage {
            guard let first = gaps.first else { return .complete }
            return .incomplete(.notificationIngress(
                first,
                additional: Array(gaps.dropFirst())
            ))
        }

        internal struct Result: Sendable, Equatable {
            internal let range: Range<Int>
            internal let coverage: Observation.Coverage
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
