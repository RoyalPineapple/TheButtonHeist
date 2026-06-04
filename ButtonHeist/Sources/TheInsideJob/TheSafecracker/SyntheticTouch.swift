#if canImport(UIKit)
#if DEBUG
import UIKit

// MARK: - Touch Pipeline
//
// Type-safe pipeline for synthetic touch injection. The types enforce
// the required call order, so callers pass concrete screen geometry into
// a touch event without semantic target policy:
//
//   TouchTarget.resolve(at:in:)  → TouchTarget
//        ↓
//   .makeTouch(phase:)           → SyntheticTouch
//        ↓
//   TouchEvent(touches:)         → TouchEvent
//        ↓
//   .send()                      → delivers to UIApplication
//        ↓
//   touch.update(phase:)         → next TouchEvent cycle

extension TheSafecracker {

    // MARK: - TouchTarget

    /// A resolved hit test result: window + point + gesture responder.
    ///
    /// On iOS 18+, SwiftUI routes gesture events through `UIKitGestureContainer`
    /// (a `UIResponder`, not `UIView`). Standard `hitTest:withEvent:` returns a
    /// rendering leaf that ignores touches. `resolve` walks the view hierarchy
    /// with `_hitTestWithContext:` to find the UIKit responder target — same
    /// approach as KIF v3.11.2 (PR #1323). This is view/responder hit testing,
    /// not accessibility hierarchy inspection.
    ///
    /// The only way to get a `TouchTarget` is through `resolve(at:in:)`.
    ///
    /// `@MainActor` justification: holds UIWindow + UIResponder references.
    @MainActor struct TouchTarget { // swiftlint:disable:this agent_main_actor_value_type
        let window: UIWindow
        let windowPoint: CGPoint
        let responder: AnyObject

        /// Resolve the correct gesture target for a screen point.
        static func resolve(at screenPoint: CGPoint, in window: UIWindow) -> TouchTarget {
            let windowPoint = window.convert(screenPoint, from: nil)
            let responder = resolveHitTestTarget(in: window, at: windowPoint)
            return TouchTarget(window: window, windowPoint: windowPoint, responder: responder)
        }

        /// Create a fully configured touch bound to this target.
        /// Sets window, view, gestureView, location, phase, timestamp in one shot.
        func makeTouch(phase: UITouch.Phase) -> SyntheticTouch? {
            let touch = UITouch()
            ObjCRuntime.message("setWindow:", to: touch)?.call(window)
            ObjCRuntime.message("setView:", to: touch)?.call(responder)
            ObjCRuntime.message("setGestureView:", to: touch)?.call(responder)

            if let locationMsg = ObjCRuntime.message("_setLocationInWindow:resetPrevious:", to: touch) {
                locationMsg.call(windowPoint, true)
            } else {
                touch.setValue(windowPoint, forKey: "locationInWindow")
            }

            ObjCRuntime.message("setPhase:", to: touch)?.call(phase.rawValue)
            ObjCRuntime.message("setTapCount:", to: touch)?.call(1)
            ObjCRuntime.message("_setIsFirstTouchForView:", to: touch)?.call(true)
            ObjCRuntime.message("setIsTap:", to: touch)?.call(true)
            ObjCRuntime.message("setTimestamp:", to: touch)?.call(ProcessInfo.processInfo.systemUptime)

            return SyntheticTouch(touch: touch, location: windowPoint, phase: phase)
        }

        // MARK: - Private: Hit Test Resolution

        private static func resolveHitTestTarget(in window: UIWindow, at windowPoint: CGPoint) -> AnyObject {
            let standardHitView = window.hitTest(windowPoint, with: nil) ?? window

            guard #available(iOS 18.0, *),
                  let createMsg = ObjCRuntime.classMessage("contextWithPoint:radius:", on: "_UIHitTestContext") else {
                return standardHitView
            }

            typealias ContextFn = @convention(c) (AnyObject, Selector, CGPoint, CGFloat) -> AnyObject? // swiftlint:disable:this nesting
            guard let context = createMsg.imp(as: ContextFn.self)(createMsg.target, createMsg.selector, windowPoint, 0) else {
                return standardHitView
            }

            var currentView: UIView? = standardHitView
            while let view = currentView {
                if let msg = ObjCRuntime.message("_hitTestWithContext:", to: view),
                   let result: AnyObject = msg.call(context) {
                    return result
                }
                currentView = view.superview
            }

            return standardHitView
        }
    }

    // MARK: - SyntheticTouch

    /// A configured UITouch with its current location and phase.
    /// Can only be created from a `TouchTarget`, guaranteeing it has
    /// the correct window, view, and gesture target set.
    ///
    /// `@MainActor` justification: wraps a UITouch reference.
    @MainActor struct SyntheticTouch { // swiftlint:disable:this agent_main_actor_value_type
        let touch: UITouch
        private(set) var location: CGPoint
        private(set) var phase: UITouch.Phase

        /// Update phase and timestamp atomically for the next event cycle.
        mutating func update(phase: UITouch.Phase) {
            self.phase = phase
            ObjCRuntime.message("setPhase:", to: touch)?.call(phase.rawValue)
            ObjCRuntime.message("setTimestamp:", to: touch)?.call(ProcessInfo.processInfo.systemUptime)
        }

        /// Update location for move events.
        mutating func update(location: CGPoint) {
            self.location = location
            if let msg = ObjCRuntime.message("_setLocationInWindow:resetPrevious:", to: touch) {
                msg.call(location, false)
            }
        }

        /// Update both phase and location in one step.
        mutating func update(phase: UITouch.Phase, location: CGPoint) {
            update(location: location)
            update(phase: phase)
        }

        /// Attach an IOHIDEvent to this touch.
        func setHIDEvent(_ hidEvent: UnsafeMutableRawPointer) {
            ObjCRuntime.message("_setHidEvent:", to: touch)?.call(hidEvent)
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
