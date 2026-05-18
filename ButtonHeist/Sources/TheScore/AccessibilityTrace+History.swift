import Foundation

public enum AccessibilityTraceRetention: Sendable, Equatable {
    case dropAfterDelivery
    case persistForSession
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

    /// Append-only accessibility capture history between explicit prune points.
    ///
    /// `captures` is the only stored truth. Refs, traces, and deltas are
    /// projections over the retained captures and are rebuilt on demand.
    struct History: Sendable, Equatable {
        public private(set) var captures: [AccessibilityTrace.Capture]
        public var retention: AccessibilityTraceRetention

        public init(
            retention: AccessibilityTraceRetention = .dropAfterDelivery,
            captures: [AccessibilityTrace.Capture] = []
        ) {
            self.captures = []
            self.retention = retention
            for capture in captures {
                append(capture)
            }
        }

        public var latestCapture: AccessibilityTrace.Capture? {
            captures.last
        }

        public var latestRef: AccessibilityTrace.CaptureRef? {
            latestCapture.map(AccessibilityTrace.CaptureRef.init(capture:))
        }

        public var latestCaptureRef: AccessibilityTrace.CaptureRef? {
            latestRef
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
            _ interface: Interface,
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
        public mutating func append(
            interface: Interface,
            context: AccessibilityTrace.Context = .empty,
            transition: AccessibilityTrace.Transition = .empty
        ) -> AccessibilityTrace.CaptureRef {
            append(interface, context: context, transition: transition)
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
            captures.first { $0.sequence == ref.sequence && $0.hash == ref.hash }
        }

        public func trace(cursor: AccessibilityTrace.Cursor) -> AccessibilityTrace? {
            let cursorCaptures = cursor.captureRefs.compactMap { capture(ref: $0) }
            guard cursorCaptures.count == cursor.captureRefs.count else { return nil }
            return AccessibilityTrace(captures: cursorCaptures)
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

        public mutating func markDelivered(through ref: AccessibilityTrace.CaptureRef?) {
            guard retention == .dropAfterDelivery, !captures.isEmpty else { return }

            let keepStartIndex: [AccessibilityTrace.Capture].Index
            if let ref {
                guard let index = index(of: ref) else { return }
                keepStartIndex = index
            } else {
                keepStartIndex = captures.index(before: captures.endIndex)
            }

            captures = Self.normalized(Array(captures[keepStartIndex...]))
        }

        public mutating func markDelivered(
            _ ref: AccessibilityTrace.CaptureRef?,
            retaining retainedRefs: Set<AccessibilityTrace.CaptureRef> = []
        ) {
            var refs = retainedRefs
            if let ref {
                refs.insert(ref)
            }
            prune(retaining: refs)
        }

        public mutating func prune(retaining retainedRefs: Set<AccessibilityTrace.CaptureRef>) {
            guard retention == .dropAfterDelivery else { return }
            var refs = retainedRefs
            if let latestRef {
                refs.insert(latestRef)
            }
            captures.removeAll { !refs.contains(AccessibilityTrace.CaptureRef(capture: $0)) }
        }

        public mutating func reset() {
            captures.removeAll()
        }

        public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
            captures.removeAll(keepingCapacity: keepCapacity)
        }

        private func index(of ref: AccessibilityTrace.CaptureRef) -> [AccessibilityTrace.Capture].Index? {
            captures.firstIndex { $0.sequence == ref.sequence && $0.hash == ref.hash }
        }

        private var nextSequence: Int {
            (captures.map(\.sequence).max() ?? 0) + 1
        }

        private static func normalized(
            _ captures: [AccessibilityTrace.Capture]
        ) -> [AccessibilityTrace.Capture] {
            AccessibilityTrace(captures: captures).captures
        }
    }
}
