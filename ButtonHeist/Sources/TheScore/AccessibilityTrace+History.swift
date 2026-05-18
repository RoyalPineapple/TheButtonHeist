import Foundation

public enum AccessibilityTraceRetention: Sendable, Equatable {
    case dropAfterDelivery
    case persistForSession
}

private struct AccessibilityTracePendingTraceBounds: Sendable, Equatable {
    let first: AccessibilityTrace.CaptureRef
    let last: AccessibilityTrace.CaptureRef
}

public extension AccessibilityTrace {
    struct Cursor: Codable, Sendable, Equatable, Hashable {
        public let captureRefs: [AccessibilityTrace.CaptureRef]

        public init(captureRefs: [AccessibilityTrace.CaptureRef]) {
            self.captureRefs = captureRefs
        }

        public var first: AccessibilityTrace.CaptureRef? { captureRefs.first }
        public var last: AccessibilityTrace.CaptureRef? { captureRefs.last }

        public var endpointEdge: AccessibilityTrace.CaptureEdge? {
            guard let first, let last, first != last else { return nil }
            return AccessibilityTrace.CaptureEdge(before: first, after: last)
        }
    }

    struct PendingTrace: Sendable, Equatable {
        public let index: Int
        public let cursor: AccessibilityTrace.Cursor
        public let trace: AccessibilityTrace

        public var firstRef: AccessibilityTrace.CaptureRef? { cursor.first }
        public var lastRef: AccessibilityTrace.CaptureRef? { cursor.last }
        public var endpointEdge: AccessibilityTrace.CaptureEdge? { cursor.endpointEdge }
        public var delta: AccessibilityTrace.Delta? { trace.backgroundDelta }
    }

    /// Append-only accessibility capture history between explicit prune points.
    ///
    /// `captures` and explicit boundary refs are the only stored truth. Cursors,
    /// traces, deltas, and lookup maps are projections over retained captures
    /// and are rebuilt on demand.
    struct History: Sendable, Equatable {
        public private(set) var captures: [AccessibilityTrace.Capture]
        public var retention: AccessibilityTraceRetention {
            didSet {
                pruneToRetentionPolicy()
            }
        }
        private var pendingTraceBounds: [AccessibilityTracePendingTraceBounds]
        private var deliveredRef: AccessibilityTrace.CaptureRef?

        public init(
            retention: AccessibilityTraceRetention = .dropAfterDelivery,
            captures: [AccessibilityTrace.Capture] = []
        ) {
            self.captures = []
            self.retention = retention
            self.pendingTraceBounds = []
            self.deliveredRef = nil
            for capture in captures {
                append(capture)
            }
        }

        public static func == (lhs: History, rhs: History) -> Bool {
            lhs.captures == rhs.captures &&
                lhs.retention == rhs.retention &&
                lhs.pendingTraceBounds == rhs.pendingTraceBounds &&
                lhs.deliveredRef == rhs.deliveredRef
        }

        public var latestCapture: AccessibilityTrace.Capture? {
            captures.last
        }

        public var latestRef: AccessibilityTrace.CaptureRef? {
            latestCapture.map(AccessibilityTrace.CaptureRef.init(capture:))
        }

        public var pendingTraceCount: Int {
            pendingTraceBounds.count
        }

        @discardableResult
        public mutating func append(_ capture: AccessibilityTrace.Capture) -> AccessibilityTrace.CaptureRef {
            let linked = AccessibilityTrace.Capture(
                sequence: nextSequence,
                interface: capture.interface,
                parentHash: captures.last?.hash,
                context: capture.context,
                transition: capture.transition,
                hash: capture.hash
            )
            captures.append(linked)
            return AccessibilityTrace.CaptureRef(capture: linked)
        }

        @discardableResult
        public mutating func append(
            interface: Interface,
            context: AccessibilityTrace.Context = .empty,
            transition: AccessibilityTrace.Transition = .empty
        ) -> AccessibilityTrace.CaptureRef {
            append(AccessibilityTrace.Capture(
                sequence: nextSequence,
                interface: interface,
                parentHash: captures.last?.hash,
                context: context,
                transition: transition
            ))
        }

        @discardableResult
        public mutating func enqueuePendingTrace(
            _ trace: AccessibilityTrace,
            limit: Int? = nil
        ) -> AccessibilityTrace.PendingTrace? {
            guard let cursor = ingest(trace),
                  let first = cursor.first,
                  let last = cursor.last else {
                return nil
            }

            pendingTraceBounds.append(AccessibilityTracePendingTraceBounds(first: first, last: last))
            if let limit {
                trimPendingTraceBounds(to: limit)
            }
            pruneToRetentionPolicy()
            guard let pendingIndex = pendingTraceBounds.indices.last else { return nil }
            return pendingTrace(at: pendingIndex)
        }

        @discardableResult
        public mutating func ingest(_ trace: AccessibilityTrace) -> AccessibilityTrace.Cursor? {
            var refs: [AccessibilityTrace.CaptureRef] = []
            for (index, capture) in trace.captures.enumerated() {
                if index == 0, let latestCapture, latestCapture.hash == capture.hash {
                    refs.append(AccessibilityTrace.CaptureRef(capture: latestCapture))
                } else {
                    refs.append(append(capture))
                }
            }
            return refs.isEmpty ? nil : AccessibilityTrace.Cursor(captureRefs: refs)
        }

        public func capture(ref: AccessibilityTrace.CaptureRef) -> AccessibilityTrace.Capture? {
            index(of: ref).map { captures[$0] }
        }

        public func elementLookup(
            captureRef: AccessibilityTrace.CaptureRef?
        ) -> [String: HeistElement] {
            guard let captureRef,
                  let capture = capture(ref: captureRef) else {
                return [:]
            }
            return capture.interface.elements.reduce(into: [String: HeistElement]()) { partialResult, element in
                partialResult[element.heistId] = element
            }
        }

        public func trace(cursor: AccessibilityTrace.Cursor) -> AccessibilityTrace? {
            let cursorCaptures = cursor.captureRefs.compactMap { capture(ref: $0) }
            guard cursorCaptures.count == cursor.captureRefs.count else { return nil }
            return AccessibilityTrace(captures: cursorCaptures)
        }

        public func pendingCursor(at index: Int) -> AccessibilityTrace.Cursor? {
            guard pendingTraceBounds.indices.contains(index) else { return nil }
            return cursor(from: pendingTraceBounds[index])
        }

        public func pendingTrace(at index: Int) -> AccessibilityTrace.PendingTrace? {
            guard let cursor = pendingCursor(at: index),
                  let trace = trace(cursor: cursor) else {
                return nil
            }
            return AccessibilityTrace.PendingTrace(index: index, cursor: cursor, trace: trace)
        }

        public func pendingTraces(startingAt startIndex: Int = 0) -> [AccessibilityTrace.PendingTrace] {
            let boundedStartIndex = min(max(startIndex, 0), pendingTraceBounds.count)
            return pendingTraceBounds.indices
                .dropFirst(boundedStartIndex)
                .compactMap { pendingTrace(at: $0) }
        }

        public func trace(
            from start: AccessibilityTrace.CaptureRef?,
            to end: AccessibilityTrace.CaptureRef?
        ) -> AccessibilityTrace? {
            guard !captures.isEmpty else { return nil }

            let startIndex: [AccessibilityTrace.Capture].Index
            if let start {
                guard let index = index(of: start) else { return nil }
                startIndex = index
            } else {
                startIndex = captures.startIndex
            }

            let endIndex: [AccessibilityTrace.Capture].Index
            if let end {
                guard let index = index(of: end) else { return nil }
                endIndex = index
            } else {
                endIndex = captures.index(before: captures.endIndex)
            }

            guard startIndex <= endIndex else { return nil }
            return AccessibilityTrace(captures: Array(captures[startIndex...endIndex]))
        }

        public func delta(
            from start: AccessibilityTrace.CaptureRef?,
            to end: AccessibilityTrace.CaptureRef?
        ) -> AccessibilityTrace.Delta? {
            trace(from: start, to: end)?.captureEndpointDelta
        }

        public mutating func removePendingTrace(
            at index: Int
        ) -> AccessibilityTrace.PendingTrace? {
            guard let pendingTrace = pendingTrace(at: index) else { return nil }
            pendingTraceBounds.remove(at: index)
            return pendingTrace
        }

        public mutating func drainPendingTrace() -> AccessibilityTrace? {
            guard let pendingTrace = removePendingTrace(at: 0) else { return nil }
            markDelivered(through: pendingTrace.lastRef)
            return pendingTrace.trace
        }

        public mutating func drainPendingTraces() -> [AccessibilityTrace] {
            let pendingTraces = pendingTraces()
            guard !pendingTraces.isEmpty else { return [] }
            pendingTraceBounds.removeAll()
            markDelivered(through: pendingTraces.last?.lastRef)
            return pendingTraces.map(\.trace)
        }

        public mutating func markDelivered(through ref: AccessibilityTrace.CaptureRef?) {
            if let ref {
                guard capture(ref: ref) != nil else { return }
                if shouldAdvanceDeliveredRef(to: ref) {
                    deliveredRef = ref
                }
            }
            pruneToRetentionPolicy()
        }

        public mutating func reset() {
            captures.removeAll()
            pendingTraceBounds.removeAll()
            deliveredRef = nil
        }

        private func index(of ref: AccessibilityTrace.CaptureRef) -> [AccessibilityTrace.Capture].Index? {
            var lowerBound = captures.startIndex
            var upperBound = captures.endIndex
            while lowerBound < upperBound {
                let distance = captures.distance(from: lowerBound, to: upperBound)
                let midpoint = captures.index(lowerBound, offsetBy: distance / 2)
                if captures[midpoint].sequence < ref.sequence {
                    lowerBound = captures.index(after: midpoint)
                } else {
                    upperBound = midpoint
                }
            }

            guard lowerBound < captures.endIndex else { return nil }
            let capture = captures[lowerBound]
            guard capture.sequence == ref.sequence && capture.hash == ref.hash else { return nil }
            return lowerBound
        }

        private func shouldAdvanceDeliveredRef(to ref: AccessibilityTrace.CaptureRef) -> Bool {
            guard let deliveredRef,
                  let deliveredIndex = index(of: deliveredRef),
                  let nextIndex = index(of: ref) else {
                return true
            }
            return nextIndex >= deliveredIndex
        }

        private func cursor(from bounds: AccessibilityTracePendingTraceBounds) -> AccessibilityTrace.Cursor? {
            guard let startIndex = index(of: bounds.first),
                  let endIndex = index(of: bounds.last),
                  startIndex <= endIndex else {
                return nil
            }
            let refs = captures[startIndex...endIndex].map(AccessibilityTrace.CaptureRef.init(capture:))
            return AccessibilityTrace.Cursor(captureRefs: refs)
        }

        private func captureRefs(
            from bounds: AccessibilityTracePendingTraceBounds
        ) -> Set<AccessibilityTrace.CaptureRef> {
            guard let cursor = cursor(from: bounds) else { return [] }
            return Set(cursor.captureRefs)
        }

        private mutating func trimPendingTraceBounds(to limit: Int) {
            let boundedLimit = max(limit, 0)
            guard pendingTraceBounds.count > boundedLimit else { return }
            pendingTraceBounds.removeFirst(pendingTraceBounds.count - boundedLimit)
        }

        private mutating func pruneToRetentionPolicy() {
            guard retention == .dropAfterDelivery else { return }
            guard !captures.isEmpty else {
                pendingTraceBounds.removeAll()
                deliveredRef = nil
                return
            }

            var retainedRefs = Set<AccessibilityTrace.CaptureRef>()
            if let deliveredRef, capture(ref: deliveredRef) != nil {
                retainedRefs.insert(deliveredRef)
            }
            for bounds in pendingTraceBounds {
                retainedRefs.formUnion(captureRefs(from: bounds))
            }
            if let latestRef {
                retainedRefs.insert(latestRef)
            }

            captures = Self.relinked(captures.filter { retainedRefs.contains(AccessibilityTrace.CaptureRef(capture: $0)) })
            deliveredRef = deliveredRef.flatMap { capture(ref: $0).map(AccessibilityTrace.CaptureRef.init(capture:)) }
            pendingTraceBounds = pendingTraceBounds.filter {
                capture(ref: $0.first) != nil && capture(ref: $0.last) != nil
            }
        }

        private var nextSequence: Int {
            (captures.last?.sequence ?? 0) + 1
        }

        private static func relinked(
            _ captures: [AccessibilityTrace.Capture]
        ) -> [AccessibilityTrace.Capture] {
            var previousHash: String?
            return captures.map { capture in
                let linked = AccessibilityTrace.Capture(
                    sequence: capture.sequence,
                    interface: capture.interface,
                    parentHash: previousHash,
                    context: capture.context,
                    transition: capture.transition,
                    hash: capture.hash
                )
                previousHash = linked.hash
                return linked
            }
        }
    }
}
