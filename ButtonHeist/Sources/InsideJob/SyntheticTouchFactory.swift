#if canImport(UIKit)
#if DEBUG
import UIKit

/// Factory for creating synthetic UITouch instances using private APIs.
/// Based on KIF's UITouch-KIFAdditions.m implementation.
///
/// All private API methods are invoked via direct IMP calls with @convention(c)
/// typed function pointers. Using perform(_:with:) for non-object parameters
/// (Int, Bool, Double) would pass NSNumber object pointers instead of raw values.
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
        performObjSelector(on: touch, selector: "setWindow:", with: window)
        performObjSelector(on: touch, selector: "setView:", with: view)

        // Set location using private method with resetPrevious parameter
        setTouchLocation(touch, point: point, resetPrevious: true)

        // Set phase
        performIntSelector(on: touch, selector: "setPhase:", with: phase.rawValue)

        // Set additional properties
        performIntSelector(on: touch, selector: "setTapCount:", with: 1)
        performBoolSelector(on: touch, selector: "_setIsFirstTouchForView:", with: true)
        performBoolSelector(on: touch, selector: "setIsTap:", with: true)

        // Set timestamp
        let timestamp = ProcessInfo.processInfo.systemUptime
        performDoubleSelector(on: touch, selector: "setTimestamp:", with: timestamp)

        return touch
    }

    /// Update touch phase and timestamp
    /// - Parameters:
    ///   - touch: The touch to update
    ///   - phase: New phase value
    static func setPhase(_ touch: UITouch, phase: UITouch.Phase) {
        performIntSelector(on: touch, selector: "setPhase:", with: phase.rawValue)
        let timestamp = ProcessInfo.processInfo.systemUptime
        performDoubleSelector(on: touch, selector: "setTimestamp:", with: timestamp)
    }

    /// Set IOHIDEvent on the touch (required for iOS 9+)
    /// - Parameters:
    ///   - touch: The touch to update
    ///   - event: The IOHIDEvent pointer
    static func setHIDEvent(_ touch: UITouch, event: UnsafeMutableRawPointer) {
        let selector = NSSelectorFromString("_setHidEvent:")
        guard touch.responds(to: selector) else {
            insideJobLogger.error("UITouch doesn't respond to _setHidEvent:")
            return
        }
        if let imp = touch.method(for: selector) {
            typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Void
            unsafeBitCast(imp, to: Fn.self)(touch, selector, event)
        }
    }

    /// Update touch location for move events.
    /// Uses resetPrevious: false so the touch maintains previous location for velocity calculation.
    static func setLocation(_ touch: UITouch, point: CGPoint) {
        setTouchLocation(touch, point: point, resetPrevious: false)
    }

    // MARK: - Private: Direct IMP Invocation Helpers

    /// Call a method that takes an object parameter (e.g., setWindow:, setView:)
    private static func performObjSelector(on object: NSObject, selector: String, with value: AnyObject) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel) else { return }
        _ = object.perform(sel, with: value)
    }

    /// Call a method that takes an Int/NSInteger parameter (e.g., setPhase:, setTapCount:)
    private static func performIntSelector(on object: NSObject, selector: String, with value: Int) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel) else { return }
        if let imp = object.method(for: sel) {
            typealias Fn = @convention(c) (AnyObject, Selector, Int) -> Void
            unsafeBitCast(imp, to: Fn.self)(object, sel, value)
        }
    }

    /// Call a method that takes a Bool/BOOL parameter (e.g., _setIsFirstTouchForView:, setIsTap:)
    private static func performBoolSelector(on object: NSObject, selector: String, with value: Bool) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel) else { return }
        if let imp = object.method(for: sel) {
            typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(imp, to: Fn.self)(object, sel, value)
        }
    }

    /// Call a method that takes a Double/TimeInterval parameter (e.g., setTimestamp:)
    private static func performDoubleSelector(on object: NSObject, selector: String, with value: Double) {
        let sel = NSSelectorFromString(selector)
        guard object.responds(to: sel) else { return }
        if let imp = object.method(for: sel) {
            typealias Fn = @convention(c) (AnyObject, Selector, Double) -> Void
            unsafeBitCast(imp, to: Fn.self)(object, sel, value)
        }
    }

    /// Set touch location via _setLocationInWindow:resetPrevious:
    private static func setTouchLocation(_ touch: UITouch, point: CGPoint, resetPrevious: Bool) {
        let selector = NSSelectorFromString("_setLocationInWindow:resetPrevious:")
        guard touch.responds(to: selector) else {
            touch.setValue(point, forKey: "locationInWindow")
            return
        }
        if let imp = touch.method(for: selector) {
            typealias Fn = @convention(c) (AnyObject, Selector, CGPoint, Bool) -> Void
            unsafeBitCast(imp, to: Fn.self)(touch, selector, point, resetPrevious)
        }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
