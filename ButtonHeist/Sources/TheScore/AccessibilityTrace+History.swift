import Foundation

public enum AccessibilityTraceRetention: Sendable, Equatable {
    case dropAfterDelivery
    case persistForSession
}

public extension AccessibilityTrace {
    /// Append-only accessibility capture history between explicit prune points.
    ///
    /// `captures` is the only stored truth. Refs, traces, and deltas are
    /// projections over the retained captures and are rebuilt on demand.
    struct History: Sendable, Equatable {
        public private(set) var captures: [AccessibilityTrace.Capture]
        public let retention: AccessibilityTraceRetention

        public init(retention: AccessibilityTraceRetention = .dropAfterDelivery) {
            self.captures = []
            self.retention = retention
        }

        public var latestCapture: AccessibilityTrace.Capture? {
            captures.last
        }

        public var latestRef: AccessibilityTrace.CaptureRef? {
            latestCapture.map(AccessibilityTrace.CaptureRef.init(capture:))
        }

        @discardableResult
        public mutating func append(_ capture: AccessibilityTrace.Capture) -> AccessibilityTrace.CaptureRef {
            captures = Self.normalized(captures + [capture])
            return AccessibilityTrace.CaptureRef(capture: captures[captures.index(before: captures.endIndex)])
        }

        @discardableResult
        public mutating func append(
            interface: Interface,
            context: AccessibilityTrace.Context = .empty,
            transition: AccessibilityTrace.Transition = .empty
        ) -> AccessibilityTrace.CaptureRef {
            append(AccessibilityTrace.Capture(
                sequence: captures.count + 1,
                interface: interface,
                parentHash: captures.last?.hash,
                context: context,
                transition: transition
            ))
        }

        public func capture(ref: AccessibilityTrace.CaptureRef) -> AccessibilityTrace.Capture? {
            captures.first { $0.sequence == ref.sequence && $0.hash == ref.hash }
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

        public mutating func reset() {
            captures.removeAll()
        }

        private func index(of ref: AccessibilityTrace.CaptureRef) -> [AccessibilityTrace.Capture].Index? {
            captures.firstIndex { $0.sequence == ref.sequence && $0.hash == ref.hash }
        }

        private static func normalized(
            _ captures: [AccessibilityTrace.Capture]
        ) -> [AccessibilityTrace.Capture] {
            AccessibilityTrace(captures: captures).captures
        }
    }
}
