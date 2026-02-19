#if canImport(UIKit)
#if DEBUG
import UIKit

/// Cracks open the app's touch system for remote gesture injection.
///
/// Supports tap, long press, swipe, drag, pinch, rotate, and two-finger tap
/// gestures using synthetic UITouch/UIEvent injection via IOKit.
/// Implementation based on KIF (Keep It Functional) testing framework.
/// Key iOS 26 fix: Creates a fresh UIEvent for each touch phase
/// instead of reusing the same event.
///
/// This is a last-resort mechanism — higher-level activation methods
/// (accessibilityActivate) should be attempted first by the caller,
/// since synthetic touch injection cannot confirm that the gesture was handled.
@MainActor
final class SafeCracker {

    // MARK: - Internal Touch State

    private var activeTouches: [UITouch] = []
    private var activeWindow: UIWindow?

    // MARK: - Public: Single-Finger Gestures

    /// Simulate a tap at the given screen coordinates.
    /// - Parameter point: Point in screen coordinates
    /// - Returns: True if the touch events were dispatched (not necessarily handled)
    func tap(at point: CGPoint) -> Bool {
        guard touchDown(at: point) else { return false }
        return touchUp()
    }

    /// Simulate a long press at the given screen coordinates.
    /// - Parameters:
    ///   - point: Point in screen coordinates
    ///   - duration: How long to hold the press (seconds, default 0.5)
    func longPress(at point: CGPoint, duration: TimeInterval = 0.5) async -> Bool {
        guard touchDown(at: point) else { return false }
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        return touchUp()
    }

    /// Simulate a swipe gesture between two screen points.
    /// - Parameters:
    ///   - start: Starting point in screen coordinates
    ///   - end: Ending point in screen coordinates
    ///   - duration: Duration of the swipe (seconds, default 0.15)
    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.15) async -> Bool {
        guard touchDown(at: start) else { return false }

        let stepDelay: TimeInterval = 0.01 // 10ms between phases (matches KIF)
        let steps = max(Int(duration / stepDelay), 3)

        for i in 1...steps {
            let progress = Double(i) / Double(steps)
            let point = CGPoint(
                x: start.x + progress * (end.x - start.x),
                y: start.y + progress * (end.y - start.y)
            )
            moveTo(point)
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        return touchUp()
    }

    /// Simulate a drag gesture between two screen points.
    /// Slower than swipe — used for reordering, slider adjustment, etc.
    /// - Parameters:
    ///   - start: Starting point in screen coordinates
    ///   - end: Ending point in screen coordinates
    ///   - duration: Duration of the drag (seconds, default 0.5)
    func drag(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.5) async -> Bool {
        guard touchDown(at: start) else { return false }

        let stepDelay: TimeInterval = 0.01
        let steps = max(Int(duration / stepDelay), 5)

        for i in 1...steps {
            let progress = Double(i) / Double(steps)
            let point = CGPoint(
                x: start.x + progress * (end.x - start.x),
                y: start.y + progress * (end.y - start.y)
            )
            moveTo(point)
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        return touchUp()
    }

    /// Simulate drawing along a path of waypoints.
    /// - Parameters:
    ///   - points: Ordered array of screen coordinates to trace through
    ///   - duration: Total duration of the gesture in seconds
    func drawPath(points: [CGPoint], duration: TimeInterval) async -> Bool {
        guard points.count >= 2 else { return false }

        guard touchDown(at: points[0]) else { return false }

        // Calculate total path length for even speed distribution
        var totalLength: CGFloat = 0
        var segmentLengths: [CGFloat] = []
        for i in 1..<points.count {
            let dx = points[i].x - points[i-1].x
            let dy = points[i].y - points[i-1].y
            let len = sqrt(dx * dx + dy * dy)
            segmentLengths.append(len)
            totalLength += len
        }

        guard totalLength > 0 else {
            return touchUp()
        }

        let stepDelay: TimeInterval = 0.01
        let totalSteps = max(Int(duration / stepDelay), points.count)

        // Walk the polyline at uniform speed
        for step in 1...totalSteps {
            let progress = CGFloat(step) / CGFloat(totalSteps)
            let targetDist = progress * totalLength

            // Find which segment this distance falls on
            var accumulated: CGFloat = 0
            var point = points.last!
            for i in 0..<segmentLengths.count {
                let segLen = segmentLengths[i]
                if accumulated + segLen >= targetDist {
                    let segProgress = (targetDist - accumulated) / segLen
                    point = CGPoint(
                        x: points[i].x + segProgress * (points[i+1].x - points[i].x),
                        y: points[i].y + segProgress * (points[i+1].y - points[i].y)
                    )
                    break
                }
                accumulated += segLen
            }

            moveTo(point)
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        return touchUp()
    }

    // MARK: - Public: Text Input (via UIKeyboardImpl)

    /// Check if the software keyboard is currently visible.
    func isKeyboardVisible() -> Bool {
        findKeyboardFrame() != nil
    }

    /// Type text by injecting characters into the active keyboard.
    /// Uses UIKeyboardImpl.addInputString: — the same approach KIF uses.
    /// The keyboard must already be visible (a text field must be focused).
    /// - Parameters:
    ///   - text: The text to type, character by character
    ///   - interKeyDelay: Nanoseconds to wait between each character (default 30ms)
    func typeText(_ text: String, interKeyDelay: UInt64 = 30_000_000) async -> Bool {
        guard let impl = getKeyboardImpl() else { return false }
        let sel = NSSelectorFromString("addInputString:")
        for char in text {
            _ = impl.perform(sel, with: String(char))
            try? await Task.sleep(nanoseconds: interKeyDelay)
        }
        return true
    }

    /// Delete characters by sending delete events to the active keyboard.
    /// Uses UIKeyboardImpl.deleteFromInput — the same approach KIF uses.
    /// - Parameters:
    ///   - count: Number of characters to delete
    ///   - interKeyDelay: Nanoseconds to wait between each delete (default 30ms)
    func deleteText(count: Int, interKeyDelay: UInt64 = 30_000_000) async -> Bool {
        guard count > 0 else { return true }
        guard let impl = getKeyboardImpl() else { return false }
        let sel = NSSelectorFromString("deleteFromInput")
        for _ in 0..<count {
            _ = impl.perform(sel)
            try? await Task.sleep(nanoseconds: interKeyDelay)
        }
        return true
    }

    // MARK: - Edit Actions (via Responder Chain)

    /// Standard edit actions that can be invoked on the first responder.
    enum EditAction: String, CaseIterable {
        case copy
        case paste
        case cut
        case select
        case selectAll

        var selector: Selector {
            switch self {
            case .copy:      return #selector(UIResponderStandardEditActions.copy(_:))
            case .paste:     return #selector(UIResponderStandardEditActions.paste(_:))
            case .cut:       return #selector(UIResponderStandardEditActions.cut(_:))
            case .select:    return #selector(UIResponderStandardEditActions.select(_:))
            case .selectAll: return #selector(UIResponderStandardEditActions.selectAll(_:))
            }
        }
    }

    /// Perform a standard edit action on the current first responder.
    /// Uses UIApplication.sendAction to route through the responder chain,
    /// following KIF's pattern of bypassing the edit menu UI entirely.
    /// - Returns: true if the action was handled by some responder
    func performEditAction(_ action: EditAction) -> Bool {
        UIApplication.shared.sendAction(action.selector, to: nil, from: nil, for: nil)
    }

    // MARK: - Private: Keyboard Helpers

    /// Get the UIKeyboardImpl active instance via ObjC runtime.
    /// UIKeyboardImpl is a private class that manages the keyboard input system.
    /// addInputString: injects text directly, bypassing the need to find and tap
    /// individual key views (which aren't accessible since iOS renders the keyboard
    /// in a remote process).
    private func getKeyboardImpl() -> AnyObject? {
        guard let kbClass = NSClassFromString("UIKeyboardImpl") else { return nil }
        let sel = NSSelectorFromString("activeInstance")
        guard (kbClass as AnyObject).responds(to: sel),
              let result = (kbClass as AnyObject).perform(sel) else { return nil }
        return result.takeUnretainedValue()
    }

    /// Find the keyboard frame by looking for UIInputSetHostView in the window hierarchy.
    private func findKeyboardFrame() -> CGRect? {
        let allWindows: [UIWindow] = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in allWindows {
            if let frame = findInputHostFrame(in: window) {
                return frame
            }
        }
        return nil
    }

    private func findInputHostFrame(in view: UIView) -> CGRect? {
        let className = String(describing: type(of: view))
        if className == "UIInputSetHostView" && view.frame.height > 100 && !view.isHidden {
            return view.convert(view.bounds, to: nil)
        }
        for sub in view.subviews {
            if let frame = findInputHostFrame(in: sub) {
                return frame
            }
        }
        return nil
    }

    // MARK: - Public: Multi-Touch Gestures

    /// Simulate a pinch gesture centered at a screen point.
    /// - Parameters:
    ///   - center: Center point of the pinch in screen coordinates
    ///   - scale: Scale factor (>1.0 = spread/zoom in, <1.0 = pinch/zoom out)
    ///   - spread: Initial distance from center to each finger (default 100pt)
    ///   - duration: Duration of the gesture (default 0.5s)
    func pinch(center: CGPoint, scale: CGFloat, spread: CGFloat = 100, duration: TimeInterval = 0.5) async -> Bool {
        let angle: CGFloat = .pi / 4 // 45° diagonal
        let startSpread = spread
        let endSpread = spread * scale

        let finger1Start = CGPoint(
            x: center.x + cos(angle) * startSpread,
            y: center.y + sin(angle) * startSpread
        )
        let finger2Start = CGPoint(
            x: center.x - cos(angle) * startSpread,
            y: center.y - sin(angle) * startSpread
        )

        guard touchesDown(at: [finger1Start, finger2Start]) else { return false }

        let stepDelay: TimeInterval = 0.01
        let steps = max(Int(duration / stepDelay), 5)

        for i in 1...steps {
            let progress = CGFloat(i) / CGFloat(steps)
            let currentSpread = startSpread + progress * (endSpread - startSpread)

            let p1 = CGPoint(
                x: center.x + cos(angle) * currentSpread,
                y: center.y + sin(angle) * currentSpread
            )
            let p2 = CGPoint(
                x: center.x - cos(angle) * currentSpread,
                y: center.y - sin(angle) * currentSpread
            )
            moveTouches(to: [p1, p2])
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        return touchesUp()
    }

    /// Simulate a rotation gesture centered at a screen point.
    /// - Parameters:
    ///   - center: Center point of the rotation in screen coordinates
    ///   - angle: Rotation angle in radians (positive = counter-clockwise)
    ///   - radius: Distance from center to each finger (default 100pt)
    ///   - duration: Duration of the gesture (default 0.5s)
    func rotate(center: CGPoint, angle: CGFloat, radius: CGFloat = 100, duration: TimeInterval = 0.5) async -> Bool {
        let startAngle: CGFloat = 0

        let finger1Start = CGPoint(
            x: center.x + cos(startAngle) * radius,
            y: center.y + sin(startAngle) * radius
        )
        let finger2Start = CGPoint(
            x: center.x + cos(startAngle + .pi) * radius,
            y: center.y + sin(startAngle + .pi) * radius
        )

        guard touchesDown(at: [finger1Start, finger2Start]) else { return false }

        let stepDelay: TimeInterval = 0.01
        let steps = max(Int(duration / stepDelay), 5)

        for i in 1...steps {
            let progress = CGFloat(i) / CGFloat(steps)
            let currentAngle = startAngle + progress * angle

            let p1 = CGPoint(
                x: center.x + cos(currentAngle) * radius,
                y: center.y + sin(currentAngle) * radius
            )
            let p2 = CGPoint(
                x: center.x + cos(currentAngle + .pi) * radius,
                y: center.y + sin(currentAngle + .pi) * radius
            )
            moveTouches(to: [p1, p2])
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        return touchesUp()
    }

    /// Simulate a two-finger tap at a screen point.
    /// - Parameters:
    ///   - center: Center point between the two fingers
    ///   - spread: Distance between the two fingers (default 40pt)
    func twoFingerTap(at center: CGPoint, spread: CGFloat = 40) -> Bool {
        let p1 = CGPoint(x: center.x - spread / 2, y: center.y)
        let p2 = CGPoint(x: center.x + spread / 2, y: center.y)
        guard touchesDown(at: [p1, p2]) else { return false }
        return touchesUp()
    }

    // MARK: - Internal: Single-Finger Primitives (delegate to N-finger)

    private func touchDown(at point: CGPoint) -> Bool {
        return touchesDown(at: [point])
    }

    @discardableResult
    private func moveTo(_ point: CGPoint) -> Bool {
        return moveTouches(to: [point])
    }

    private func touchUp() -> Bool {
        return touchesUp()
    }

    // MARK: - Internal: N-Finger Primitives

    /// Begin touches at N screen points simultaneously.
    private func touchesDown(at points: [CGPoint]) -> Bool {
        guard !points.isEmpty else { return false }
        guard let window = getKeyWindow() else {
            print("[SafeCracker] No key window found")
            return false
        }

        var touches: [UITouch] = []
        var fingerData: [IOHIDEventBuilder.FingerTouchData] = []

        for point in points {
            let windowPoint = window.convert(point, from: nil)
            guard let hitView = window.hitTest(windowPoint, with: nil) else {
                print("[SafeCracker] No view at point \(point)")
                return false
            }
            guard let touch = SyntheticTouchFactory.createTouch(
                at: windowPoint, in: window, view: hitView, phase: .began
            ) else {
                print("[SafeCracker] Failed to create touch")
                return false
            }
            touches.append(touch)
            fingerData.append(IOHIDEventBuilder.FingerTouchData(
                touch: touch, location: windowPoint, phase: .began
            ))
        }

        let hidEvent = IOHIDEventBuilder.createEvent(for: fingerData)
        for touch in touches {
            if let hidEvent { SyntheticTouchFactory.setHIDEvent(touch, event: hidEvent) }
        }

        guard let event = SyntheticEventFactory.createEventForTouches(touches, hidEvent: hidEvent) else {
            print("[SafeCracker] Failed to create began event")
            return false
        }

        UIApplication.shared.sendEvent(event)
        activeTouches = touches
        activeWindow = window
        return true
    }

    /// Move all active touches to new screen points.
    /// points.count must equal activeTouches.count.
    @discardableResult
    private func moveTouches(to points: [CGPoint]) -> Bool {
        guard !activeTouches.isEmpty, let window = activeWindow else { return false }
        guard points.count == activeTouches.count else { return false }

        var fingerData: [IOHIDEventBuilder.FingerTouchData] = []

        for (touch, point) in zip(activeTouches, points) {
            let windowPoint = window.convert(point, from: nil)
            SyntheticTouchFactory.setLocation(touch, point: windowPoint)
            SyntheticTouchFactory.setPhase(touch, phase: .moved)
            fingerData.append(IOHIDEventBuilder.FingerTouchData(
                touch: touch, location: windowPoint, phase: .moved
            ))
        }

        let hidEvent = IOHIDEventBuilder.createEvent(for: fingerData)
        for touch in activeTouches {
            if let hidEvent { SyntheticTouchFactory.setHIDEvent(touch, event: hidEvent) }
        }

        guard let event = SyntheticEventFactory.createEventForTouches(activeTouches, hidEvent: hidEvent) else {
            return false
        }

        UIApplication.shared.sendEvent(event)
        return true
    }

    /// Lift all active touches.
    private func touchesUp() -> Bool {
        guard !activeTouches.isEmpty, let window = activeWindow else { return false }

        var fingerData: [IOHIDEventBuilder.FingerTouchData] = []

        for touch in activeTouches {
            SyntheticTouchFactory.setPhase(touch, phase: .ended)
            let windowPoint = touch.location(in: window)
            fingerData.append(IOHIDEventBuilder.FingerTouchData(
                touch: touch, location: windowPoint, phase: .ended
            ))
        }

        let hidEvent = IOHIDEventBuilder.createEvent(for: fingerData)
        for touch in activeTouches {
            if let hidEvent { SyntheticTouchFactory.setHIDEvent(touch, event: hidEvent) }
        }

        guard let event = SyntheticEventFactory.createEventForTouches(activeTouches, hidEvent: hidEvent) else {
            print("[SafeCracker] Failed to create ended event")
            return false
        }

        UIApplication.shared.sendEvent(event)
        activeTouches = []
        activeWindow = nil
        return true
    }

    // MARK: - Private

    private func getKeyWindow() -> UIWindow? {
        // Find the main app window, skipping overlay windows (high windowLevel)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.windowLevel <= .normal && $0.rootViewController?.view != nil }
    }
}
#endif // DEBUG
#endif // canImport(UIKit)
