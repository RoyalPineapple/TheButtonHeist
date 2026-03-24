#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

/// Cracks open the app's touch system for remote gesture injection.
///
/// Supports tap, long press, swipe, drag, pinch, rotate, and two-finger tap
/// gestures using synthetic UITouch/UIEvent injection via IOKit.
/// Implementation based on KIF (Keep It Functional) testing framework.
/// Key iOS 26 fix: Creates a fresh UIEvent for each touch phase
/// instead of reusing the same event.
///
/// The `activate` command handles accessibilityActivate → synthetic tap
/// fallback internally. The `tap` command is a low-level escape hatch
/// for fuzzing and debugging — it bypasses accessibilityActivate entirely.
@MainActor
final class TheSafecracker {

    // MARK: - TheBagman Reference

    /// Back-reference to the element cache and UI observation owner.
    /// Used by extension files to resolve interaction targets.
    weak var bagman: TheBagman?

    // MARK: - Fingerprints

    /// Visual interaction indicators for taps and gesture tracking.
    lazy var fingerprints = TheFingerprints()

    // MARK: - Interaction Result

    /// Outcome of a high-level interaction (action, gesture, text entry).
    /// TheInsideJob wraps this with InterfaceDelta to produce the wire ActionResult.
    struct InteractionResult {
        let success: Bool
        let method: ActionMethod
        let message: String?
        let value: String?

        static func failure(_ method: ActionMethod, message: String) -> InteractionResult {
            InteractionResult(success: false, method: method, message: message, value: nil)
        }
    }

    /// Result of resolving a screen coordinate from an element target or explicit point.
    /// Uses a custom enum instead of `Result` so `InteractionResult` doesn't need `Error` conformance.
    enum PointResolution {
        case success(CGPoint)
        case failure(InteractionResult)
    }

    // MARK: - Timing Constants

    /// Default inter-key delay for text injection (30ms). Single source of truth
    /// for typeText and deleteText default parameters.
    nonisolated static let defaultInterKeyDelay: UInt64 = 30_000_000

    /// Maximum allowed inter-key delay (500ms) to prevent unreasonably slow typing.
    nonisolated static let maxInterKeyDelay: UInt64 = 500_000_000

    /// Yield between touch began/ended phases (50ms) so SwiftUI's gesture
    /// pipeline has run-loop time to transition from "possible" to "recognized".
    nonisolated static let gestureYieldDelay: UInt64 = 50_000_000

    // MARK: - Keyboard Visibility (Notification-Based)

    /// Tracks keyboard visibility via `UIKeyboardDidChangeFrameNotification`,
    /// matching KIF's approach. The view-hierarchy walk (`UIInputSetHostView`)
    /// broke on iOS 26 because the keyboard window no longer appears in
    /// `UIWindowScene.windows`.
    private var keyboardVisible = false
    private var keyboardObserver: NSObjectProtocol?

    func startKeyboardTracking() {
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return
                }
                let screenBounds = UIScreen.main.bounds
                self.keyboardVisible = endFrame.intersects(screenBounds)
                    && endFrame.height > 0
                    && endFrame.origin.y < screenBounds.height
            }
        }
    }

    func stopKeyboardTracking() {
        if let observer = keyboardObserver {
            NotificationCenter.default.removeObserver(observer)
            keyboardObserver = nil
        }
    }

    // MARK: - Internal Touch State

    private var activeTouches: [SyntheticTouch] = []
    private var activeWindow: UIWindow?

    /// Called during continuous gestures with all current finger positions.
    /// Set by TheInsideJob to update recording overlays during gesture execution.
    var onGestureMove: (([CGPoint]) -> Void)?

    // MARK: - Public: Single-Finger Gestures

    /// Simulate a tap at the given screen coordinates.
    /// Yields to the main run loop between began and ended phases so that
    /// SwiftUI gesture recognizers (which process events asynchronously)
    /// have a chance to transition from "possible" to "recognized".
    /// - Parameter point: Point in screen coordinates
    /// - Returns: True if the touch events were dispatched (not necessarily handled)
    func tap(at point: CGPoint) async -> Bool {
        guard touchDown(at: point) else { return false }
        try? await Task.sleep(nanoseconds: Self.gestureYieldDelay)
        return touchUp()
    }

    /// Simulate a long press at the given screen coordinates.
    /// - Parameters:
    ///   - point: Point in screen coordinates
    ///   - duration: How long to hold the press (seconds, default 0.5)
    func longPress(at point: CGPoint, duration: TimeInterval = 0.5) async -> Bool {
        guard touchDown(at: point) else { return false }
        fingerprints.beginTrackingFingerprints(at: [point])
        onGestureMove?([point])
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        fingerprints.endTrackingFingerprints()
        return touchUp()
    }

    /// Simulate a swipe gesture between two screen points.
    /// - Parameters:
    ///   - start: Starting point in screen coordinates
    ///   - end: Ending point in screen coordinates
    ///   - duration: Duration of the swipe (seconds, default 0.15)
    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.15) async -> Bool {
        guard touchDown(at: start) else { return false }
        fingerprints.beginTrackingFingerprints(at: [start])
        onGestureMove?([start])

        let stepDelay: TimeInterval = 0.01 // 10ms between phases (matches KIF)
        let steps = max(Int(duration / stepDelay), 3)

        for i in 1...steps {
            let progress = Double(i) / Double(steps)
            let point = CGPoint(
                x: start.x + progress * (end.x - start.x),
                y: start.y + progress * (end.y - start.y)
            )
            moveTo(point)
            fingerprints.updateTrackingFingerprints(to: [point])
            onGestureMove?([point])
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        fingerprints.endTrackingFingerprints()
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
        fingerprints.beginTrackingFingerprints(at: [start])
        onGestureMove?([start])

        let stepDelay: TimeInterval = 0.01
        let steps = max(Int(duration / stepDelay), 5)

        for i in 1...steps {
            let progress = Double(i) / Double(steps)
            let point = CGPoint(
                x: start.x + progress * (end.x - start.x),
                y: start.y + progress * (end.y - start.y)
            )
            moveTo(point)
            fingerprints.updateTrackingFingerprints(to: [point])
            onGestureMove?([point])
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        fingerprints.endTrackingFingerprints()
        return touchUp()
    }

    /// Simulate drawing along a path of waypoints.
    /// - Parameters:
    ///   - points: Ordered array of screen coordinates to trace through
    ///   - duration: Total duration of the gesture in seconds
    func drawPath(points: [CGPoint], duration: TimeInterval) async -> Bool {
        guard points.count >= 2 else { return false }

        guard touchDown(at: points[0]) else { return false }
        fingerprints.beginTrackingFingerprints(at: [points[0]])
        onGestureMove?([points[0]])

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
            fingerprints.endTrackingFingerprints()
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
            var point = points[points.count - 1]
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
            fingerprints.updateTrackingFingerprints(to: [point])
            onGestureMove?([point])
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        fingerprints.endTrackingFingerprints()
        return touchUp()
    }

    // MARK: - Public: Text Input (via UIKeyboardImpl)

    /// Check if the software keyboard is currently visible.
    /// Uses notification-based tracking (KIF's approach) with a fallback
    /// to checking UIKeyboardImpl for an active input delegate.
    func isKeyboardVisible() -> Bool {
        if keyboardVisible { return true }
        guard let impl = getKeyboardImpl() else { return false }
        let delegate: AnyObject? = ObjCRuntime.message("delegate", to: impl)?.call()
        return delegate is UIKeyInput
    }

    /// Type text by injecting characters into the active keyboard.
    /// Uses UIKeyboardImpl.addInputString: — the same approach KIF uses.
    /// The keyboard must already be visible (a text field must be focused).
    /// - Parameters:
    ///   - text: The text to type, character by character
    ///   - interKeyDelay: Nanoseconds to wait between each character (default 30ms)
    func typeText(_ text: String, interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay) async -> Bool {
        guard let impl = getKeyboardImpl(),
              let msg = ObjCRuntime.message("addInputString:", to: impl) else { return false }
        for char in text {
            msg.call(String(char) as AnyObject)
            try? await Task.sleep(nanoseconds: interKeyDelay)
        }
        return true
    }

    /// Delete characters by sending delete events to the active keyboard.
    /// Uses UIKeyboardImpl.deleteFromInput — the same approach KIF uses.
    /// - Parameters:
    ///   - count: Number of characters to delete
    ///   - interKeyDelay: Nanoseconds to wait between each delete (default 30ms)
    func deleteText(count: Int, interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay) async -> Bool {
        guard count > 0 else { return true }
        guard let impl = getKeyboardImpl(),
              let msg = ObjCRuntime.message("deleteFromInput", to: impl) else { return false }
        for _ in 0..<count {
            msg.call()
            try? await Task.sleep(nanoseconds: interKeyDelay)
        }
        return true
    }

    // MARK: - Edit Actions (via Responder Chain)

    /// Perform a standard edit action on the current first responder.
    /// Uses UIApplication.sendAction to route through the responder chain,
    /// following KIF's pattern of bypassing the edit menu UI entirely.
    /// - Returns: true if the action was handled by some responder
    func performEditAction(_ action: EditAction) -> Bool {
        UIApplication.shared.sendAction(action.selector, to: nil, from: nil, for: nil)
    }

    /// Resign first responder, dismissing the keyboard if visible.
    /// Walks the view hierarchy of all windows to find the current first responder
    /// and calls resignFirstResponder() on it.
    /// - Returns: true if a first responder was found and resigned
    func resignFirstResponder() -> Bool {
        let allWindows: [UIWindow] = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in allWindows {
            if let responder = findFirstResponder(in: window) {
                responder.resignFirstResponder()
                return true
            }
        }
        return false
    }

    private func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = findFirstResponder(in: sub) { return found }
        }
        return nil
    }

    // MARK: - Private: Keyboard Helpers

    /// Get the UIKeyboardImpl active instance via ObjC runtime.
    /// UIKeyboardImpl is a private class that manages the keyboard input system.
    /// addInputString: injects text directly, bypassing the need to find and tap
    /// individual key views (which aren't accessible since iOS renders the keyboard
    /// in a remote process).
    private func getKeyboardImpl() -> AnyObject? {
        ObjCRuntime.classMessage("activeInstance", on: "UIKeyboardImpl")?.call()
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
    func touchesDown(at points: [CGPoint]) -> Bool {
        guard !points.isEmpty else { return false }
        guard let window = windowForPoint(points[0]) else {
            insideJobLogger.error("No window found for point \(String(describing: points[0]))")
            return false
        }

        var touches: [SyntheticTouch] = []
        for point in points {
            let target = TouchTarget.resolve(at: point, in: window)
            guard let touch = target.makeTouch(phase: .began) else {
                insideJobLogger.error("Failed to create touch")
                return false
            }
            touches.append(touch)
        }

        guard let event = TouchEvent(touches: touches) else {
            insideJobLogger.error("Failed to create began event")
            return false
        }

        event.send()
        activeTouches = touches
        activeWindow = window
        return true
    }

    /// Move all active touches to new screen points.
    /// points.count must equal activeTouches.count.
    @discardableResult
    func moveTouches(to points: [CGPoint]) -> Bool {
        guard !activeTouches.isEmpty, let window = activeWindow else { return false }
        guard points.count == activeTouches.count else { return false }

        for i in activeTouches.indices {
            let windowPoint = window.convert(points[i], from: nil)
            activeTouches[i].update(phase: .moved, location: windowPoint)
        }

        guard let event = TouchEvent(touches: activeTouches) else { return false }
        event.send()
        return true
    }

    /// Lift all active touches.
    func touchesUp() -> Bool {
        guard !activeTouches.isEmpty else { return false }

        for i in activeTouches.indices {
            activeTouches[i].update(phase: .ended)
        }

        guard let event = TouchEvent(touches: activeTouches) else {
            insideJobLogger.error("Failed to create ended event")
            return false
        }

        event.send()
        activeTouches = []
        activeWindow = nil
        return true
    }

    // MARK: - Private

    /// Find the correct window for a tap at the given screen point.
    /// Iterates all windows frontmost-first (highest windowLevel first),
    /// following KIF's pattern from UIApplication-KIFAdditions.m.
    /// Returns the first window whose hitTest succeeds at the point.
    private func windowForPoint(_ point: CGPoint) -> UIWindow? {
        let allWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { !($0 is TheFingerprints.FingerprintWindow) && !$0.isHidden }
            .sorted { $0.windowLevel > $1.windowLevel }

        for window in allWindows {
            let windowPoint = window.convert(point, from: nil)
            if window.hitTest(windowPoint, with: nil) != nil {
                return window
            }
        }
        return nil
    }

}

// MARK: - EditAction + Selector

extension EditAction {
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

#endif // DEBUG
#endif // canImport(UIKit)
