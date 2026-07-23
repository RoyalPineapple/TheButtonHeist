#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

private struct ObservationLogEntry: Sendable, Equatable {
    let index: Observation.Log.Index
    let event: Observation.Event
}

extension Observation {
    internal enum LogReadError: Error, Sendable, Equatable {
        case momentUnavailable(Moment)
        case historyEvicted(Gap)
    }

    internal enum SnapshotRead: Sendable, Equatable {
        case event(SnapshotEvent)
        case pending
        case failure(LogReadError)
    }

    internal enum EventsSince: Sendable, Equatable {
        case events([Event])
        case expired(Gap)
        case unavailable(LogReadError)
    }

    internal struct Moment: Sendable, Equatable {
        internal let snapshot: Snapshot
        fileprivate let logIndex: Log.Index

        fileprivate init(snapshot: Snapshot, logIndex: Log.Index) {
            self.snapshot = snapshot
            self.logIndex = logIndex
        }

        internal var capture: AccessibilityTrace.Capture {
            guard let capture = snapshot.trace.captures.last else {
                preconditionFailure("Committed observation snapshot has no trace capture")
            }
            return capture
        }

        internal func isSameOrAfter(_ earlier: Moment) -> Bool {
            logIndex.belongs(toSameLogAs: earlier.logIndex) && logIndex >= earlier.logIndex
        }

        internal var sequence: SettledObservationSequence {
            snapshot.sequence
        }
    }

    internal struct SnapshotEvent: Sendable, Equatable {
        internal let moment: Moment
        internal let continuity: ScreenContinuity
        internal let previous: Snapshot?
        internal let transition: Transition

        internal var snapshot: Snapshot { moment.snapshot }
        internal var generation: ScreenGeneration { snapshot.generation }
        internal var scope: SemanticObservationScope { snapshot.sourceScope }
        internal var sequence: SettledObservationSequence { snapshot.sequence }
        internal var notificationSequence: UInt64 { snapshot.notificationSequence }
        internal var trace: AccessibilityTrace { snapshot.trace }
        internal var previousMoment: Moment? { transition.previousMoment }

        internal var latestCaptureRef: AccessibilityTrace.CaptureRef? {
            trace.captures.last.map(AccessibilityTrace.CaptureRef.init(capture:))
        }
    }

    internal struct AnnouncementEvent: Sendable, Equatable {
        internal let announcement: CapturedAnnouncement
    }

    internal enum Event: Sendable, Equatable {
        case snapshot(SnapshotEvent)
        case announcement(AnnouncementEvent)
    }

    internal struct Log: Sendable, Equatable, RandomAccessCollection {
        internal let retentionLimit: Int
        private var retainedEntries: [ObservationLogEntry] = []
        private var evictedThrough: Index?
        private var nextPosition: UInt64 = 1
        private let id = UUID()

        internal init(retentionLimit: Int) {
            precondition(retentionLimit > 0, "Observation log retention must be positive")
            self.retentionLimit = retentionLimit
        }

        internal var latestSnapshotEvent: SnapshotEvent? {
            retainedEntries.reversed().lazy.compactMap(\.event.snapshot).first
        }

        internal mutating func record(
            snapshot: Snapshot,
            continuity: ScreenContinuity,
            protectedBy activeBoundary: Moment? = nil
        ) throws(TransitionValidationError) -> SnapshotEvent {
            let previous = latestSnapshotEvent
            let index = reserveIndex()
            let moment = Moment(snapshot: snapshot, logIndex: endIndex)
            let transition = try Observation.transition(
                from: previous,
                to: moment,
                generation: snapshot.generation
            )
            let event = SnapshotEvent(
                moment: moment,
                continuity: continuity,
                previous: previous?.snapshot,
                transition: transition
            )
            append(.snapshot(event), at: index, protectedBy: activeBoundary)
            return event
        }

        internal mutating func record(
            announcement: CapturedAnnouncement
        ) -> AnnouncementEvent {
            let index = reserveIndex()
            let event = AnnouncementEvent(announcement: announcement)
            append(.announcement(event), at: index, protectedBy: nil)
            return event
        }

        internal mutating func prune(protectedBy activeBoundary: Moment?) {
            evictOverflow(protectedBy: activeBoundary)
        }

        internal var startIndex: Index {
            retainedEntries.first?.index ?? endIndex
        }

        internal var endIndex: Index {
            Index(logID: id, position: nextPosition)
        }

        internal subscript(index: Index) -> Event {
            precondition(index.belongs(to: id), "Observation log index belongs to a different log")
            precondition(index >= startIndex && index < endIndex, "Observation log index is out of bounds")
            return retainedEntries[Int(index.position - startIndex.position)].event
        }

        internal func index(after index: Index) -> Index {
            precondition(index.belongs(to: id), "Observation log index belongs to a different log")
            return Index(logID: id, position: index.position + 1)
        }

        internal func index(before index: Index) -> Index {
            precondition(index.belongs(to: id), "Observation log index belongs to a different log")
            return Index(logID: id, position: index.position - 1)
        }

        internal func index(_ index: Index, offsetBy distance: Int) -> Index {
            precondition(index.belongs(to: id), "Observation log index belongs to a different log")
            return Index(logID: id, position: UInt64(Int64(index.position) + Int64(distance)))
        }

        internal func distance(from start: Index, to end: Index) -> Int {
            precondition(
                start.belongs(to: id) && end.belongs(to: id),
                "Observation log indices belong to a different log"
            )
            return Int(Int64(end.position) - Int64(start.position))
        }

        internal func events(since moment: Moment) -> EventsSince {
            guard moment.logIndex.belongs(to: id) else {
                return .unavailable(.momentUnavailable(moment))
            }
            guard moment.logIndex >= startIndex else {
                return .expired(expiredGap(from: moment))
            }
            return .events(Array(self[moment.logIndex..<endIndex]))
        }

        internal func readSnapshot(
            after moment: Moment?,
            fulfilling scope: SemanticObservationScope
        ) -> SnapshotRead {
            guard let moment else {
                return snapshotEvents(fulfilling: scope).first
                    .map(SnapshotRead.event) ?? .pending
            }
            guard moment.logIndex.belongs(to: id) else {
                return .failure(.momentUnavailable(moment))
            }
            if let gap = historyGap(since: moment) {
                return .failure(.historyEvicted(gap))
            }
            let momentIsKnown = moment.logIndex >= startIndex && moment.logIndex <= endIndex
            guard momentIsKnown else {
                return .failure(.momentUnavailable(moment))
            }
            return snapshotEntries(fulfilling: scope).first(where: {
                $0.index >= moment.logIndex
            }).flatMap(\.event.snapshot).map(SnapshotRead.event) ?? .pending
        }

        internal func snapshotEvents(
            fulfilling scope: SemanticObservationScope
        ) -> [SnapshotEvent] {
            snapshotEntries(fulfilling: scope).compactMap(\.event.snapshot)
        }

        internal func latestSnapshot(
            fulfilling scope: SemanticObservationScope
        ) -> SnapshotEvent? {
            snapshotEvents(fulfilling: scope).last
        }

        internal func snapshotEvent(at moment: Moment) -> SnapshotEvent? {
            retainedEntries.lazy.compactMap(\.event.snapshot).first(where: {
                $0.moment == moment
            })
        }

        internal func snapshotEvent(
            fulfilling scope: SemanticObservationScope,
            sequence: SettledObservationSequence
        ) -> SnapshotEvent? {
            snapshotEvents(fulfilling: scope).first {
                $0.sequence == sequence
            }
        }

        private mutating func reserveIndex() -> Index {
            defer { nextPosition += 1 }
            return Index(logID: id, position: nextPosition)
        }

        private func snapshotEntries(
            fulfilling scope: SemanticObservationScope
        ) -> [ObservationLogEntry] {
            retainedEntries.filter {
                $0.event.snapshot?.scope.canFulfill(scope) == true
            }
        }

        private mutating func append(
            _ event: Event,
            at index: Index,
            protectedBy activeBoundary: Moment?
        ) {
            precondition(
                retainedEntries.last.map { $0.index < index } ?? true,
                "Observation log index must advance"
            )
            retainedEntries.append(ObservationLogEntry(index: index, event: event))
            evictOverflow(protectedBy: activeBoundary)
        }

        private mutating func evictOverflow(protectedBy activeBoundary: Moment?) {
            guard retainedEntries.count > retentionLimit else { return }
            let overflow = retainedEntries.count - retentionLimit
            let evictionCount: Int
            if let activeBoundary {
                guard activeBoundary.logIndex.belongs(to: id) else {
                    preconditionFailure("Active observation boundary belongs to a different log")
                }
                let entriesBeforeBoundary = retainedEntries.prefix {
                    $0.index < activeBoundary.logIndex
                }.count
                evictionCount = Swift.min(overflow, entriesBeforeBoundary)
            } else {
                evictionCount = overflow
            }
            guard evictionCount > 0 else { return }
            evictedThrough = retainedEntries[evictionCount - 1].index
            retainedEntries.removeFirst(evictionCount)
        }

        private func historyGap(since moment: Moment) -> Gap? {
            guard evictedThrough != nil,
                  moment.logIndex < startIndex else { return nil }
            return expiredGap(from: moment)
        }

        private func expiredGap(from moment: Moment) -> Gap {
            guard let current = latestSnapshotEvent?.moment else {
                preconditionFailure("Observation evidence cannot expire without a retained current snapshot")
            }
            return Gap(reason: .historyEvicted, baseline: moment, current: current)
        }
    }

    fileprivate static func transition(
        from previous: SnapshotEvent?,
        to current: Moment,
        generation: ScreenGeneration
    ) throws(TransitionValidationError) -> Transition {
        guard let previous else { return .initial }
        guard current.logIndex > previous.moment.logIndex else {
            throw .logIndexDidNotAdvance
        }
        if generation == previous.generation {
            return .sameGeneration(previous: previous.moment)
        }
        guard generation.rawValue > previous.generation.rawValue else {
            throw .replacementGenerationDidNotAdvance(
                from: previous.generation,
                to: generation
            )
        }
        return .screenBoundary(previous: previous.moment)
    }
}

extension Observation.Log {
    internal typealias Element = Observation.Event

    internal struct Index: Sendable, Equatable, Hashable, Comparable {
        fileprivate let logID: UUID
        fileprivate let position: UInt64

        internal static func < (lhs: Index, rhs: Index) -> Bool {
            precondition(lhs.logID == rhs.logID, "Observation log indices belong to different logs")
            return lhs.position < rhs.position
        }

        fileprivate func belongs(to logID: UUID) -> Bool {
            self.logID == logID
        }

        fileprivate func belongs(toSameLogAs other: Index) -> Bool {
            logID == other.logID
        }
    }
}

private extension Observation.Event {
    var snapshot: Observation.SnapshotEvent? {
        guard case .snapshot(let event) = self else { return nil }
        return event
    }

    var announcement: Observation.AnnouncementEvent? {
        guard case .announcement(let event) = self else { return nil }
        return event
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
