import TheScore

extension TheFence {

    /// Owns retained accessibility captures plus the queued background traces.
    struct BackgroundAccessibilityState {
        private static let defaultPendingTraceLimit = 20

        private var history = AccessibilityTrace.History(retention: .dropAfterDelivery)
        private let pendingTraceLimit: Int

        init(pendingTraceLimit: Int = Self.defaultPendingTraceLimit) {
            self.pendingTraceLimit = pendingTraceLimit
        }

        var pendingTraceCount: Int {
            history.pendingTraceCount
        }

        var latestRef: AccessibilityTrace.CaptureRef? {
            history.latestRef
        }

        mutating func reset() {
            history.reset()
            history.retention = .dropAfterDelivery
        }

        mutating func enqueue(_ trace: AccessibilityTrace) {
            history.enqueuePendingTrace(trace, limit: pendingTraceLimit)
        }

        mutating func drainTrace() -> AccessibilityTrace? {
            history.drainPendingTrace()
        }

        mutating func drainTraces() -> [AccessibilityTrace] {
            history.drainPendingTraces()
        }

        func pendingTraces(startingAt startIndex: Int = 0) -> [AccessibilityTrace.PendingTrace] {
            history.pendingTraces(startingAt: startIndex)
        }

        mutating func removePendingTrace(at index: Int) -> AccessibilityTrace.PendingTrace? {
            history.removePendingTrace(at: index)
        }

        @discardableResult
        mutating func append(interface: Interface) -> AccessibilityTrace.CaptureRef {
            history.append(interface: interface)
        }

        @discardableResult
        mutating func ingest(_ trace: AccessibilityTrace) -> AccessibilityTrace.Cursor? {
            history.ingest(trace)
        }

        func capture(ref: AccessibilityTrace.CaptureRef) -> AccessibilityTrace.Capture? {
            history.capture(ref: ref)
        }

        func elementLookup(captureRef: AccessibilityTrace.CaptureRef?) -> [HeistId: HeistElement] {
            history.elementLookup(captureRef: captureRef)
        }

        mutating func markDelivered(through ref: AccessibilityTrace.CaptureRef?) {
            history.markDelivered(through: ref)
        }

        mutating func beginRecordingRetention() {
            history.retention = .persistForSession
        }

        mutating func endRecordingRetention() {
            history.retention = .dropAfterDelivery
        }
    }
}
