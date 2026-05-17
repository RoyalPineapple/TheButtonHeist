import Foundation

public extension AccessibilityTrace {
    /// Compact first-to-last capture view for background output and expectation checks.
    var backgroundDelta: AccessibilityTrace.Delta? {
        guard let first = captures.first, let last = captures.last else { return nil }
        return Self.meaningfulBackgroundDelta(.between(first, last))
    }

    private static func meaningfulBackgroundDelta(_ delta: AccessibilityTrace.Delta) -> AccessibilityTrace.Delta? {
        switch delta {
        case .noChange(let payload) where payload.transient.isEmpty:
            return nil
        case .noChange, .elementsChanged, .screenChanged:
            return delta
        }
    }
}
