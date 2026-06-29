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

    private struct TouchMutationRuntime {
        let setWindow: ObjCRuntime.Message<UITouch, ObjCRuntime.ObjectArgument<UIWindow>>
        let setView: ObjCRuntime.Message<UITouch, ObjCRuntime.ObjectArgument<UIResponder>>
        let setGestureView: ObjCRuntime.Message<UITouch, ObjCRuntime.ObjectArgument<UIResponder>>?
        let setLocationInWindow: ObjCRuntime.Message<UITouch, ObjCRuntime.PointBoolArguments>
        let setPhase: ObjCRuntime.Message<UITouch, ObjCRuntime.IntArgument>
        let setTapCount: ObjCRuntime.Message<UITouch, ObjCRuntime.IntArgument>
        let setIsFirstTouchForView: ObjCRuntime.Message<UITouch, ObjCRuntime.BoolArgument>?
        let setIsTap: ObjCRuntime.Message<UITouch, ObjCRuntime.BoolArgument>?
        let setTimestamp: ObjCRuntime.Message<UITouch, ObjCRuntime.DoubleArgument>
        let setHIDEvent: ObjCRuntime.Message<UITouch, ObjCRuntime.PointerArgument>?

        static func resolve(for touch: UITouch) -> TouchMutationRuntime? {
            guard let setWindow = require(.touchSetWindow, for: touch),
                  let setView = require(.touchSetView, for: touch),
                  let setLocationInWindow = require(.touchSetLocationInWindow, for: touch),
                  let setPhase = require(.touchSetPhase, for: touch),
                  let setTapCount = require(.touchSetTapCount, for: touch),
                  let setTimestamp = require(.touchSetTimestamp, for: touch)
            else { return nil }

            return TouchMutationRuntime(
                setWindow: setWindow,
                setView: setView,
                setGestureView: ObjCRuntime.message(.touchSetGestureView, to: touch),
                setLocationInWindow: setLocationInWindow,
                setPhase: setPhase,
                setTapCount: setTapCount,
                setIsFirstTouchForView: ObjCRuntime.message(.touchSetIsFirstTouchForView, to: touch),
                setIsTap: ObjCRuntime.message(.touchSetIsTap, to: touch),
                setTimestamp: setTimestamp,
                setHIDEvent: ObjCRuntime.message(.touchSetHIDEvent, to: touch)
            )
        }

        private static func require<Arguments>(
            _ method: ObjCRuntime.ObjectMethod<Arguments>,
            for touch: UITouch
        ) -> ObjCRuntime.Message<UITouch, Arguments>? {
            let message = ObjCRuntime.message(method, to: touch)
            if message == nil {
                insideJobLogger.error("UITouch doesn't respond to \(method.rawValue, privacy: .public)")
            }
            return message
        }
    }

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
        let responder: UIResponder

        /// Resolve the correct gesture target for a screen point.
        static func resolve(at screenPoint: CGPoint, in window: UIWindow) -> TouchTarget {
            let windowPoint = window.convert(screenPoint, from: nil)
            let responder = resolveHitTestTarget(in: window, at: windowPoint)
            return TouchTarget(window: window, windowPoint: windowPoint, responder: responder)
        }

        /// Create a fully configured touch bound to this target.
        /// Sets window, view, gestureView, location, phase, timestamp in one shot.
        func makeTouch(phase: UITouch.Phase) -> SyntheticTouch? {
            SyntheticTouch(target: self, phase: phase)
        }

        // MARK: - Private: Hit Test Resolution

        private static func resolveHitTestTarget(in window: UIWindow, at windowPoint: CGPoint) -> UIResponder {
            let standardHitView = window.hitTest(windowPoint, with: nil) ?? window

            guard #available(iOS 18.0, *),
                  let createContext = ObjCRuntime.classMessage(.contextWithPointRadius, on: .uiHitTestContext) else {
                return standardHitView
            }

            guard let context: NSObject = createContext.call(windowPoint, radius: 0) else {
                return standardHitView
            }

            var currentView: UIView? = standardHitView
            while let view = currentView {
                if let msg = ObjCRuntime.message(.viewHitTestWithContext, to: view),
                   let result: UIResponder = msg.call(context) {
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
        private let runtime: TouchMutationRuntime
        private(set) var location: CGPoint
        private(set) var phase: UITouch.Phase

        fileprivate init?(
            target: TouchTarget,
            phase: UITouch.Phase
        ) {
            let touch = UITouch()
            guard let runtime = TouchMutationRuntime.resolve(for: touch) else {
                return nil
            }

            runtime.setWindow.send(target.window)
            runtime.setView.send(target.responder)
            runtime.setGestureView?.send(target.responder)
            runtime.setLocationInWindow.call(target.windowPoint, resetPrevious: true)
            runtime.setPhase.call(phase.rawValue)
            runtime.setTapCount.call(1)
            runtime.setIsFirstTouchForView?.call(true)
            runtime.setIsTap?.call(true)
            runtime.setTimestamp.call(ProcessInfo.processInfo.systemUptime)

            self.touch = touch
            self.runtime = runtime
            self.location = target.windowPoint
            self.phase = phase
        }

        /// Update phase and timestamp atomically for the next event cycle.
        mutating func update(phase: UITouch.Phase) {
            self.phase = phase
            runtime.setPhase.call(phase.rawValue)
            runtime.setTimestamp.call(ProcessInfo.processInfo.systemUptime)
        }

        /// Update location for move events.
        mutating func update(location: CGPoint) {
            self.location = location
            runtime.setLocationInWindow.call(location, resetPrevious: false)
        }

        /// Update both phase and location in one step.
        mutating func update(phase: UITouch.Phase, location: CGPoint) {
            update(location: location)
            update(phase: phase)
        }

        /// Attach an IOHIDEvent to this touch.
        func setHIDEvent(_ hidEvent: HIDEvent) {
            guard let setHIDEvent = runtime.setHIDEvent else { return }
            hidEvent.withUnsafePointer {
                setHIDEvent.call($0)
            }
        }
    }

}

#endif // DEBUG
#endif // canImport(UIKit)
