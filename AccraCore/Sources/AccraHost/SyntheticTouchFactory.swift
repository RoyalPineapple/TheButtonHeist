#if canImport(UIKit)
import UIKit

/// Factory for creating synthetic UITouch instances using private APIs.
/// Based on KIF's UITouch-KIFAdditions.m implementation.
@MainActor
final class SyntheticTouchFactory {

    /// Create a UITouch at the specified point
    /// - Parameters:
    ///   - point: Location in window coordinates
    ///   - window: The window containing the touch
    ///   - view: The view that receives the touch
    ///   - phase: Initial touch phase
    /// - Returns: Configured UITouch or nil if creation failed
    static func createTouch(at point: CGPoint, in window: UIWindow, view: UIView, phase: UITouch.Phase) -> UITouch? {
        let touch = UITouch()

        // Must set window first as it resets other values
        performSelector(on: touch, selector: "setWindow:", with: window)
        performSelector(on: touch, selector: "setView:", with: view)

        // Set location using private method with resetPrevious parameter
        setTouchLocation(touch, point: point, resetPrevious: true)

        // Set phase
        performSelector(on: touch, selector: "setPhase:", with: phase.rawValue)

        // Set additional properties
        performSelector(on: touch, selector: "setTapCount:", with: 1)
        performSelector(on: touch, selector: "_setIsFirstTouchForView:", with: true)
        performSelector(on: touch, selector: "setIsTap:", with: true)

        // Set timestamp
        let timestamp = ProcessInfo.processInfo.systemUptime
        performSelector(on: touch, selector: "setTimestamp:", with: timestamp)

        return touch
    }

    /// Update touch phase and timestamp
    /// - Parameters:
    ///   - touch: The touch to update
    ///   - phase: New phase value
    static func setPhase(_ touch: UITouch, phase: UITouch.Phase) {
        performSelector(on: touch, selector: "setPhase:", with: phase.rawValue)
        let timestamp = ProcessInfo.processInfo.systemUptime
        performSelector(on: touch, selector: "setTimestamp:", with: timestamp)
    }

    /// Set IOHIDEvent on the touch (required for iOS 9+)
    /// - Parameters:
    ///   - touch: The touch to update
    ///   - event: The IOHIDEvent pointer
    static func setHIDEvent(_ touch: UITouch, event: UnsafeMutableRawPointer) {
        let selector = NSSelectorFromString("_setHidEvent:")
        guard touch.responds(to: selector) else {
            print("[SyntheticTouchFactory] UITouch doesn't respond to _setHidEvent:")
            return
        }
        _ = touch.perform(selector, with: event)
    }

    // MARK: - Private Helpers

    private static func performSelector(on object: NSObject, selector: String, with value: Any?) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel) else {
            print("[SyntheticTouchFactory] Object doesn't respond to \(selector)")
            return
        }
        _ = object.perform(sel, with: value)
    }

    private static func setTouchLocation(_ touch: UITouch, point: CGPoint, resetPrevious: Bool) {
        // _setLocationInWindow:resetPrevious: takes CGPoint and BOOL
        let selector = NSSelectorFromString("_setLocationInWindow:resetPrevious:")
        guard touch.responds(to: selector) else {
            // Fallback to simple setValue for older iOS versions
            touch.setValue(point, forKey: "locationInWindow")
            return
        }

        // Direct call using unsafeBitCast for methods with non-object parameters
        if let imp = touch.method(for: selector) {
            typealias SetLocationFunc = @convention(c) (AnyObject, Selector, CGPoint, Bool) -> Void
            let function = unsafeBitCast(imp, to: SetLocationFunc.self)
            function(touch, selector, point, resetPrevious)
        }
    }
}
#endif
