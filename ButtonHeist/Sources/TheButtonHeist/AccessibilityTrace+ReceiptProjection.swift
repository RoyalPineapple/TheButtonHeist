import Foundation

import TheScore

extension AccessibilityTrace {
    /// Delta projected from the first and final capture receipts in this trace.
    ///
    /// `AccessibilityTrace.Capture` is the durable source of truth. This helper
    /// keeps compatibility surfaces that still expose `Delta` deriving their
    /// projection from receipt endpoints instead of independently accumulated
    /// delta state.
    var captureReceiptDelta: AccessibilityTrace.Delta? {
        guard let first = captures.first, let last = captures.last else { return nil }
        return Self.meaningfulCaptureDelta(.between(first, last))
    }

    private static func meaningfulCaptureDelta(_ delta: AccessibilityTrace.Delta) -> AccessibilityTrace.Delta? {
        switch delta {
        case .noChange(let payload) where payload.transient.isEmpty:
            return nil
        case .noChange, .elementsChanged, .screenChanged:
            return delta
        }
    }
}
