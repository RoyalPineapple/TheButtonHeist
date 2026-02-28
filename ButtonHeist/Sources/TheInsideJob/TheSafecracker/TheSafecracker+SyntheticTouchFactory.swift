#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheSafecracker {

    /// Factory for creating synthetic UITouch instances using private APIs.
    /// Based on KIF's UITouch-KIFAdditions.m implementation.
    final class SyntheticTouchFactory {

        static func createTouch(at point: CGPoint, in window: UIWindow, view: UIView, phase: UITouch.Phase) -> UITouch? {
            let touch = UITouch()
            performObjSelector(on: touch, selector: "setWindow:", with: window)
            performObjSelector(on: touch, selector: "setView:", with: view)
            setTouchLocation(touch, point: point, resetPrevious: true)
            performIntSelector(on: touch, selector: "setPhase:", with: phase.rawValue)
            performIntSelector(on: touch, selector: "setTapCount:", with: 1)
            performBoolSelector(on: touch, selector: "_setIsFirstTouchForView:", with: true)
            performBoolSelector(on: touch, selector: "setIsTap:", with: true)
            let timestamp = ProcessInfo.processInfo.systemUptime
            performDoubleSelector(on: touch, selector: "setTimestamp:", with: timestamp)
            return touch
        }

        static func setPhase(_ touch: UITouch, phase: UITouch.Phase) {
            performIntSelector(on: touch, selector: "setPhase:", with: phase.rawValue)
            let timestamp = ProcessInfo.processInfo.systemUptime
            performDoubleSelector(on: touch, selector: "setTimestamp:", with: timestamp)
        }

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

        static func setLocation(_ touch: UITouch, point: CGPoint) {
            setTouchLocation(touch, point: point, resetPrevious: false)
        }

        private static func performObjSelector(on object: NSObject, selector: String, with value: AnyObject) {
            let sel = NSSelectorFromString(selector)
            guard object.responds(to: sel) else { return }
            _ = object.perform(sel, with: value)
        }

        private static func performIntSelector(on object: NSObject, selector: String, with value: Int) {
            let sel = NSSelectorFromString(selector)
            guard object.responds(to: sel) else { return }
            if let imp = object.method(for: sel) {
                typealias Fn = @convention(c) (AnyObject, Selector, Int) -> Void
                unsafeBitCast(imp, to: Fn.self)(object, sel, value)
            }
        }

        private static func performBoolSelector(on object: NSObject, selector: String, with value: Bool) {
            let sel = NSSelectorFromString(selector)
            guard object.responds(to: sel) else { return }
            if let imp = object.method(for: sel) {
                typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
                unsafeBitCast(imp, to: Fn.self)(object, sel, value)
            }
        }

        private static func performDoubleSelector(on object: NSObject, selector: String, with value: Double) {
            let sel = NSSelectorFromString(selector)
            guard object.responds(to: sel) else { return }
            if let imp = object.method(for: sel) {
                typealias Fn = @convention(c) (AnyObject, Selector, Double) -> Void
                unsafeBitCast(imp, to: Fn.self)(object, sel, value)
            }
        }

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
}
#endif
#endif
