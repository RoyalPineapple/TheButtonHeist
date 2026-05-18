import Foundation

public extension AccessibilityTrace {
    /// Compact first-to-last capture view for background output and expectation checks.
    var backgroundDelta: AccessibilityTrace.Delta? {
        meaningfulCaptureEndpointDelta
    }
}
