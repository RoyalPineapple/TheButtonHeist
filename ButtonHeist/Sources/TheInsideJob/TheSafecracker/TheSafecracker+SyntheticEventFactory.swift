#if canImport(UIKit)
#if DEBUG
import UIKit

extension TheSafecracker {

    /// Factory for creating and manipulating UIEvent instances for touch injection.
    @MainActor final class SyntheticEventFactory {

        static func getTouchesEvent() -> UIEvent? {
            guard let msg = ObjCRuntime.message("_touchesEvent", to: UIApplication.shared) else {
                insideJobLogger.error("UIApplication doesn't respond to _touchesEvent")
                return nil
            }
            return msg.call() as UIEvent?
        }

        static func clearTouches(from event: UIEvent) {
            guard let msg = ObjCRuntime.message("_clearTouches", to: event) else {
                insideJobLogger.error("UIEvent doesn't respond to _clearTouches")
                return
            }
            msg.call()
        }

        static func addTouch(_ touch: UITouch, to event: UIEvent, delayed: Bool = false) {
            guard let msg = ObjCRuntime.message("_addTouch:forDelayedDelivery:", to: event) else {
                insideJobLogger.error("UIEvent doesn't respond to _addTouch:forDelayedDelivery:")
                return
            }
            // Mixed object + value args — use imp escape hatch
            typealias AddTouchFn = @convention(c) (AnyObject, Selector, UITouch, Bool) -> Void // swiftlint:disable:this nesting
            msg.imp(as: AddTouchFn.self)(event, msg.selector, touch, delayed)
        }

        static func setHIDEvent(_ hidEvent: UnsafeMutableRawPointer, on event: UIEvent) {
            guard let msg = ObjCRuntime.message("_setHIDEvent:", to: event) else {
                insideJobLogger.error("UIEvent doesn't respond to _setHIDEvent:")
                return
            }
            msg.call(hidEvent)
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
