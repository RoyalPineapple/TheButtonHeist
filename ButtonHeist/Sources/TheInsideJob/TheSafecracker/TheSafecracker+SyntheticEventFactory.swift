#if canImport(UIKit)
#if DEBUG
import UIKit

private typealias AddTouchFunc = @convention(c) (AnyObject, Selector, UITouch, Bool) -> Void
private typealias SetHIDFunc = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Void

extension TheSafecracker {

    /// Factory for creating and manipulating UIEvent instances for touch injection.
    @MainActor final class SyntheticEventFactory {

        static func getTouchesEvent() -> UIEvent? {
            let app = UIApplication.shared
            let selector = NSSelectorFromString("_touchesEvent")
            guard app.responds(to: selector) else {
                insideJobLogger.error("UIApplication doesn't respond to _touchesEvent")
                return nil
            }
            return app.perform(selector)?.takeUnretainedValue() as? UIEvent
        }

        static func clearTouches(from event: UIEvent) {
            let selector = NSSelectorFromString("_clearTouches")
            guard (event as NSObject).responds(to: selector) else {
                insideJobLogger.error("UIEvent doesn't respond to _clearTouches")
                return
            }
            _ = (event as NSObject).perform(selector)
        }

        static func addTouch(_ touch: UITouch, to event: UIEvent, delayed: Bool = false) {
            let selector = NSSelectorFromString("_addTouch:forDelayedDelivery:")
            guard (event as NSObject).responds(to: selector) else {
                insideJobLogger.error("UIEvent doesn't respond to _addTouch:forDelayedDelivery:")
                return
            }
            if let imp = (event as NSObject).method(for: selector) {
                let function = unsafeBitCast(imp, to: AddTouchFunc.self)
                function(event, selector, touch, delayed)
            }
        }

        static func setHIDEvent(_ hidEvent: UnsafeMutableRawPointer, on event: UIEvent) {
            let selector = NSSelectorFromString("_setHIDEvent:")
            guard (event as NSObject).responds(to: selector) else {
                insideJobLogger.error("UIEvent doesn't respond to _setHIDEvent:")
                return
            }
            if let imp = (event as NSObject).method(for: selector) {
                let function = unsafeBitCast(imp, to: SetHIDFunc.self)
                function(event, selector, hidEvent)
            }
        }

        static func createEventForTouch(_ touch: UITouch, hidEvent: UnsafeMutableRawPointer?) -> UIEvent? {
            guard let event = getTouchesEvent() else { return nil }
            clearTouches(from: event)
            if let hidEvent = hidEvent { setHIDEvent(hidEvent, on: event) }
            addTouch(touch, to: event, delayed: false)
            return event
        }

        static func createEventForTouches(_ touches: [UITouch], hidEvent: UnsafeMutableRawPointer?) -> UIEvent? {
            guard let event = getTouchesEvent() else { return nil }
            clearTouches(from: event)
            if let hidEvent { setHIDEvent(hidEvent, on: event) }
            for touch in touches { addTouch(touch, to: event, delayed: false) }
            return event
        }
    }
}
#endif
#endif
