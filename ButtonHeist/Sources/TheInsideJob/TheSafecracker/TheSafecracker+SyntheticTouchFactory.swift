#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheSafecracker {

    /// Factory for creating synthetic UITouch instances using private APIs.
    /// Based on KIF's UITouch-KIFAdditions.m implementation.
    @MainActor final class SyntheticTouchFactory {

        static func createTouch(at point: CGPoint, in window: UIWindow, view: UIView, phase: UITouch.Phase) -> UITouch? {
            let touch = UITouch()
            ObjCRuntime.message("setWindow:", to: touch)?.call(window)
            ObjCRuntime.message("setView:", to: touch)?.call(view)
            setTouchLocation(touch, point: point, resetPrevious: true)
            ObjCRuntime.message("setPhase:", to: touch)?.call(phase.rawValue)
            ObjCRuntime.message("setTapCount:", to: touch)?.call(1)
            ObjCRuntime.message("_setIsFirstTouchForView:", to: touch)?.call(true)
            ObjCRuntime.message("setIsTap:", to: touch)?.call(true)
            ObjCRuntime.message("setTimestamp:", to: touch)?.call(ProcessInfo.processInfo.systemUptime)
            return touch
        }

        static func setPhase(_ touch: UITouch, phase: UITouch.Phase) {
            ObjCRuntime.message("setPhase:", to: touch)?.call(phase.rawValue)
            ObjCRuntime.message("setTimestamp:", to: touch)?.call(ProcessInfo.processInfo.systemUptime)
        }

        static func setHIDEvent(_ touch: UITouch, event: UnsafeMutableRawPointer) {
            guard let msg = ObjCRuntime.message("_setHidEvent:", to: touch) else {
                insideJobLogger.error("UITouch doesn't respond to _setHidEvent:")
                return
            }
            msg.call(event)
        }

        static func setLocation(_ touch: UITouch, point: CGPoint) {
            setTouchLocation(touch, point: point, resetPrevious: false)
        }

        static func setGestureView(_ touch: UITouch, view: UIView) {
            ObjCRuntime.message("setGestureView:", to: touch)?.call(view)
        }

        private static func setTouchLocation(_ touch: UITouch, point: CGPoint, resetPrevious: Bool) {
            guard let msg = ObjCRuntime.message("_setLocationInWindow:resetPrevious:", to: touch) else {
                touch.setValue(point, forKey: "locationInWindow")
                return
            }
            msg.call(point, resetPrevious)
        }
    }
}
#endif
#endif
