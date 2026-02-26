#if canImport(UIKit)
#if DEBUG
import UIKit

/// Factory for creating and manipulating UIEvent instances for touch injection.
/// Based on KIF's UIView-KIFAdditions.m implementation.
@MainActor
final class SyntheticEventFactory {

    /// Get the singleton touches event from UIApplication
    /// - Returns: The shared UIEvent for touches, or nil if unavailable
    static func getTouchesEvent() -> UIEvent? {
        let app = UIApplication.shared
        let selector = NSSelectorFromString("_touchesEvent")
        guard app.responds(to: selector) else {
            insideJobLogger.error("UIApplication doesn't respond to _touchesEvent")
            return nil
        }
        return app.perform(selector)?.takeUnretainedValue() as? UIEvent
    }

    /// Clear all touches from an event
    /// - Parameter event: The event to clear
    static func clearTouches(from event: UIEvent) {
        let selector = NSSelectorFromString("_clearTouches")
        guard (event as NSObject).responds(to: selector) else {
            insideJobLogger.error("UIEvent doesn't respond to _clearTouches")
            return
        }
        _ = (event as NSObject).perform(selector)
    }

    /// Add a touch to an event
    /// - Parameters:
    ///   - touch: The touch to add
    ///   - event: The event to add to
    ///   - delayed: Whether to use delayed delivery
    static func addTouch(_ touch: UITouch, to event: UIEvent, delayed: Bool = false) {
        let selector = NSSelectorFromString("_addTouch:forDelayedDelivery:")
        guard (event as NSObject).responds(to: selector) else {
            insideJobLogger.error("UIEvent doesn't respond to _addTouch:forDelayedDelivery:")
            return
        }

        // Use direct method invocation for two parameters
        if let imp = (event as NSObject).method(for: selector) {
            typealias AddTouchFunc = @convention(c) (AnyObject, Selector, UITouch, Bool) -> Void
            let function = unsafeBitCast(imp, to: AddTouchFunc.self)
            function(event, selector, touch, delayed)
        }
    }

    /// Set IOHIDEvent on a UIEvent
    /// - Parameters:
    ///   - hidEvent: The IOHIDEvent pointer
    ///   - event: The UIEvent to update
    static func setHIDEvent(_ hidEvent: UnsafeMutableRawPointer, on event: UIEvent) {
        let selector = NSSelectorFromString("_setHIDEvent:")
        guard (event as NSObject).responds(to: selector) else {
            insideJobLogger.error("UIEvent doesn't respond to _setHIDEvent:")
            return
        }
        // Must use direct IMP invocation — perform(_:with:) boxes the raw pointer
        // incorrectly instead of passing it as a C pointer to the ObjC method.
        if let imp = (event as NSObject).method(for: selector) {
            typealias SetHIDFunc = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Void
            let function = unsafeBitCast(imp, to: SetHIDFunc.self)
            function(event, selector, hidEvent)
        }
    }

    /// Create a fully configured event for a touch
    /// - Parameters:
    ///   - touch: The touch to configure the event with
    ///   - hidEvent: Optional IOHIDEvent to attach
    /// - Returns: Configured UIEvent or nil if creation failed
    static func createEventForTouch(_ touch: UITouch, hidEvent: UnsafeMutableRawPointer?) -> UIEvent? {
        guard let event = getTouchesEvent() else { return nil }

        clearTouches(from: event)

        if let hidEvent = hidEvent {
            setHIDEvent(hidEvent, on: event)
        }

        addTouch(touch, to: event, delayed: false)

        return event
    }

    /// Create a fully configured event for multiple touches
    /// - Parameters:
    ///   - touches: The touches to add to the event
    ///   - hidEvent: Optional IOHIDEvent to attach
    /// - Returns: Configured UIEvent or nil if creation failed
    static func createEventForTouches(_ touches: [UITouch], hidEvent: UnsafeMutableRawPointer?) -> UIEvent? {
        guard let event = getTouchesEvent() else { return nil }
        clearTouches(from: event)
        if let hidEvent { setHIDEvent(hidEvent, on: event) }
        for touch in touches {
            addTouch(touch, to: event, delayed: false)
        }
        return event
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
