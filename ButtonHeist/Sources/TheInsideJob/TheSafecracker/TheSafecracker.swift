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

    // MARK: - Crew References

    /// Back-reference to the element cache and UI observation owner.
    /// Used by extension files to resolve interaction targets.
    weak var bagman: TheBagman?

    /// Back-reference to the timing and window state observer.
    /// Used by ensureOnScreen to wait for scroll animations to settle.
    weak var tripwire: TheTripwire?

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

    /// Yield after setting selectedTextRange (50ms) so the keyboard's internal
    /// state treats the selection as current before the subsequent delete.
    nonisolated static let selectionSettleDelay: UInt64 = 50_000_000

    /// Poll interval for keyboard readiness after tapping a text field (100ms).
    nonisolated static let keyboardPollInterval: UInt64 = 100_000_000

    /// Maximum number of polls before giving up on keyboard readiness (20 × 100ms = 2s).
    nonisolated static let keyboardPollMaxAttempts: Int = 20

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
    /// Sends `.stationary` phase events every 10ms during the hold (matching KIF)
    /// so gesture recognizers stay alive and processing.
    /// - Parameters:
    ///   - point: Point in screen coordinates
    ///   - duration: How long to hold the press (seconds, default 0.5)
    func longPress(at point: CGPoint, duration: TimeInterval = 0.5) async -> Bool {
        guard touchDown(at: point) else { return false }
        fingerprints.beginTrackingFingerprints(at: [point])
        onGestureMove?([point])

        let stepDelay: TimeInterval = 0.01
        var elapsed: TimeInterval = 0
        while elapsed < duration {
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
            elapsed += stepDelay
            sendStationary()
        }

        fingerprints.endTrackingFingerprints()
        return touchUp()
    }

    /// Simulate a swipe gesture between two screen points.
    /// Pre-computes all waypoints before the gesture loop (matches KIF's
    /// `dragPointsAlongPaths:` pattern) so the path is stable even if
    /// the view moves during the gesture.
    /// - Parameters:
    ///   - start: Starting point in screen coordinates
    ///   - end: Ending point in screen coordinates
    ///   - duration: Duration of the swipe (seconds, default 0.15)
    func swipe(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.15) async -> Bool {
        let stepDelay: TimeInterval = 0.01
        let steps = max(Int(duration / stepDelay), 3)
        let waypoints = (1...steps).map { i -> CGPoint in
            let progress = Double(i) / Double(steps)
            return CGPoint(
                x: start.x + progress * (end.x - start.x),
                y: start.y + progress * (end.y - start.y)
            )
        }

        guard touchDown(at: start) else { return false }
        fingerprints.beginTrackingFingerprints(at: [start])
        onGestureMove?([start])

        for point in waypoints {
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
    /// Pre-computes all waypoints before the gesture loop.
    /// - Parameters:
    ///   - start: Starting point in screen coordinates
    ///   - end: Ending point in screen coordinates
    ///   - duration: Duration of the drag (seconds, default 0.5)
    func drag(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.5) async -> Bool {
        let stepDelay: TimeInterval = 0.01
        let steps = max(Int(duration / stepDelay), 5)
        let waypoints = (1...steps).map { i -> CGPoint in
            let progress = Double(i) / Double(steps)
            return CGPoint(
                x: start.x + progress * (end.x - start.x),
                y: start.y + progress * (end.y - start.y)
            )
        }

        guard touchDown(at: start) else { return false }
        fingerprints.beginTrackingFingerprints(at: [start])
        onGestureMove?([start])

        for point in waypoints {
            moveTo(point)
            fingerprints.updateTrackingFingerprints(to: [point])
            onGestureMove?([point])
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        fingerprints.endTrackingFingerprints()
        return touchUp()
    }

    /// Simulate drawing along a path of waypoints.
    /// Pre-computes all interpolated waypoints at uniform speed before
    /// the gesture loop begins.
    /// - Parameters:
    ///   - points: Ordered array of screen coordinates to trace through
    ///   - duration: Total duration of the gesture in seconds
    func drawPath(points: [CGPoint], duration: TimeInterval) async -> Bool {
        guard points.count >= 2 else { return false }

        // Pre-compute: calculate segment lengths and total path length
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
            // Degenerate path — just tap the start point
            guard touchDown(at: points[0]) else { return false }
            return touchUp()
        }

        let stepDelay: TimeInterval = 0.01
        let totalSteps = max(Int(duration / stepDelay), points.count)

        // Pre-compute: build full waypoint array at uniform speed
        let waypoints = (1...totalSteps).map { step -> CGPoint in
            let progress = CGFloat(step) / CGFloat(totalSteps)
            let targetDist = progress * totalLength

            var accumulated: CGFloat = 0
            for i in 0..<segmentLengths.count {
                let segLen = segmentLengths[i]
                if accumulated + segLen >= targetDist {
                    let segProgress = (targetDist - accumulated) / segLen
                    return CGPoint(
                        x: points[i].x + segProgress * (points[i+1].x - points[i].x),
                        y: points[i].y + segProgress * (points[i+1].y - points[i].y)
                    )
                }
                accumulated += segLen
            }
            return points[points.count - 1]
        }

        // Execute gesture with pre-computed path
        guard touchDown(at: points[0]) else { return false }
        fingerprints.beginTrackingFingerprints(at: [points[0]])
        onGestureMove?([points[0]])

        for point in waypoints {
            moveTo(point)
            fingerprints.updateTrackingFingerprints(to: [point])
            onGestureMove?([point])
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }

        fingerprints.endTrackingFingerprints()
        return touchUp()
    }

    // MARK: - Public: Text Input (via KeyboardBridge)

    /// Check if the software keyboard is currently visible.
    /// Uses notification-based tracking (KIF's approach) with a fallback
    /// to checking UIKeyboardImpl for an active input delegate.
    func isKeyboardVisible() -> Bool {
        if keyboardVisible { return true }
        return KeyboardBridge.shared()?.hasActiveInput ?? false
    }

    /// Type text by injecting characters into the active keyboard.
    /// Routes through KeyboardBridge → UIKeyboardImpl.addInputString: per character.
    func typeText(_ text: String, interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay) async -> Bool {
        guard let keyboard = KeyboardBridge.shared() else { return false }
        for char in text {
            keyboard.type(char)
            try? await Task.sleep(nanoseconds: interKeyDelay)
        }
        return true
    }

    /// Delete characters by sending backspace events to the active keyboard.
    /// Routes through KeyboardBridge → UIKeyboardImpl.deleteFromInput per character.
    func deleteText(count: Int, interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay) async -> Bool {
        guard count > 0 else { return true }
        guard let keyboard = KeyboardBridge.shared() else { return false }
        for _ in 0..<count {
            keyboard.deleteBackward()
            try? await Task.sleep(nanoseconds: interKeyDelay)
        }
        return true
    }

    /// Clear all text in the focused text input using UITextInput select-all + delete.
    /// Uses UITextInput protocol directly — works with UITextField, UITextView,
    /// and any custom UITextInput conformer.
    func clearText() async -> Bool {
        guard let textInput = firstResponderView() as? (any UITextInput) else {
            return false
        }

        let start = textInput.beginningOfDocument
        let end = textInput.endOfDocument
        guard let fullRange = textInput.textRange(from: start, to: end) else { return true }
        if fullRange.isEmpty { return true }
        textInput.selectedTextRange = fullRange
        // Brief yield so the selection registers before delete
        try? await Task.sleep(nanoseconds: Self.selectionSettleDelay)

        if let keyboard = KeyboardBridge.shared() {
            keyboard.deleteBackward()
        } else {
            textInput.deleteBackward()
        }
        return true
    }

    // MARK: - Edit Actions (via Responder Chain)

    /// Perform a standard edit action on the current first responder.
    /// Uses UIApplication.sendAction to route through the responder chain,
    /// following KIF's pattern of bypassing the edit menu UI entirely.
    func performEditAction(_ action: EditAction) -> Bool {
        UIApplication.shared.sendAction(action.selector, to: nil, from: nil, for: nil)
    }

    /// Resign first responder, dismissing the keyboard if visible.
    func resignFirstResponder() -> Bool {
        guard let responder = firstResponderView() else { return false }
        responder.resignFirstResponder()
        return true
    }

    // MARK: - First Responder

    /// Find the first responder view across all windows in the active scene.
    func firstResponderView() -> UIView? {
        let allWindows: [UIWindow] = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in allWindows {
            if let found = findFirstResponder(in: window) { return found }
        }
        return nil
    }

    func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = findFirstResponder(in: sub) { return found }
        }
        return nil
    }

    // MARK: - Public: Text Input Readiness

    /// Whether a text input is ready to accept typed characters.
    /// KeyboardBridge resolves UIKeyboardImpl.sharedInstance — if present,
    /// the keyboard is ready in both software and hardware modes.
    func hasActiveTextInput() -> Bool {
        KeyboardBridge.shared() != nil
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

    /// Send a stationary event for all active touches without moving them.
    /// Used during long press to keep gesture recognizers processing (matches KIF).
    @discardableResult
    private func sendStationary() -> Bool {
        guard !activeTouches.isEmpty else { return false }

        for i in activeTouches.indices {
            activeTouches[i].update(phase: .stationary)
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
