#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

/// Result of resolving a screen coordinate from an element target or explicit point.
/// Shared between TheStash (resolution) and TheBrains (consumption).
///
/// `@MainActor` justification: carries `TheSafecracker.InteractionResult` which
/// references MainActor-bound state — isolation aligns with consumers.
@MainActor enum PointResolution { // swiftlint:disable:this agent_main_actor_value_type
    case success(CGPoint)
    case failure(TheSafecracker.InteractionResult)
}

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

    // MARK: - Keyboard State

    /// Whether the software keyboard is currently visible. Updated via
    /// keyboard notifications — no polling needed.
    private(set) var keyboardVisibleFlag = false

    func startKeyboardObservation() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardFrameDidChange),
                           name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillShow),
                           name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardDidHide),
                           name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    func stopKeyboardObservation() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        center.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        center.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    @objc private func keyboardFrameDidChange(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let screenBounds = notification.object
            .flatMap { $0 as? UIScreen }?.bounds
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.bounds
            ?? .zero
        keyboardVisibleFlag = endFrame.intersects(screenBounds)
            && endFrame.height > 0
            && endFrame.origin.y < screenBounds.height
    }

    @objc private func keyboardWillShow() { keyboardVisibleFlag = true }
    @objc private func keyboardDidHide() { keyboardVisibleFlag = false }

    // MARK: - Fingerprints

    /// Visual interaction indicators for taps and gesture tracking.
    lazy var fingerprints = TheFingerprints()

    /// Show a brief fingerprint indicator at a screen point.
    func showFingerprint(at point: CGPoint) {
        fingerprints.showFingerprint(at: point)
    }

    // MARK: - Interaction Result

    /// Outcome of a high-level interaction (action, gesture, text entry).
    /// TheInsideJob wraps this with InterfaceDelta to produce the wire ActionResult.
    struct InteractionResult {
        let success: Bool
        let method: ActionMethod
        let message: String?
        let value: String?
        let scrollSearchResult: ScrollSearchResult?

        init(success: Bool, method: ActionMethod, message: String?, value: String?, scrollSearchResult: ScrollSearchResult? = nil) {
            self.success = success
            self.method = method
            self.message = message
            self.value = value
            self.scrollSearchResult = scrollSearchResult
        }

        static func failure(_ method: ActionMethod, message: String) -> InteractionResult {
            InteractionResult(success: false, method: method, message: message, value: nil)
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
        guard await Task.cancellableSleep(for: Self.gestureYieldDelay) else { return false }
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
        while elapsed < duration && !Task.isCancelled {
            guard await Task.cancellableSleep(nanoseconds: UInt64(stepDelay * 1_000_000_000)) else { break }
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
            if Task.isCancelled { break }
            moveTo(point)
            fingerprints.updateTrackingFingerprints(to: [point])
            onGestureMove?([point])
            guard await Task.cancellableSleep(nanoseconds: UInt64(stepDelay * 1_000_000_000)) else { break }
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
            if Task.isCancelled { break }
            moveTo(point)
            fingerprints.updateTrackingFingerprints(to: [point])
            onGestureMove?([point])
            guard await Task.cancellableSleep(nanoseconds: UInt64(stepDelay * 1_000_000_000)) else { break }
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
        for index in 1..<points.count {
            let dx = points[index].x - points[index - 1].x
            let dy = points[index].y - points[index - 1].y
            let length = sqrt(dx * dx + dy * dy)
            segmentLengths.append(length)
            totalLength += length
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
            for index in 0..<segmentLengths.count {
                let segmentLength = segmentLengths[index]
                if accumulated + segmentLength >= targetDist {
                    let segmentProgress = (targetDist - accumulated) / segmentLength
                    return CGPoint(
                        x: points[index].x + segmentProgress * (points[index + 1].x - points[index].x),
                        y: points[index].y + segmentProgress * (points[index + 1].y - points[index].y)
                    )
                }
                accumulated += segmentLength
            }
            return points[points.count - 1]
        }

        // Execute gesture with pre-computed path
        guard touchDown(at: points[0]) else { return false }
        fingerprints.beginTrackingFingerprints(at: [points[0]])
        onGestureMove?([points[0]])

        for point in waypoints {
            if Task.isCancelled { break }
            moveTo(point)
            fingerprints.updateTrackingFingerprints(to: [point])
            onGestureMove?([point])
            guard await Task.cancellableSleep(nanoseconds: UInt64(stepDelay * 1_000_000_000)) else { break }
        }

        fingerprints.endTrackingFingerprints()
        return touchUp()
    }

    // MARK: - Public: Text Input (via KeyboardBridge)

    /// Check if the software keyboard is currently visible.
    /// Reads the notification-driven flag (frame-based detection, matching
    /// KIF's approach) with a fallback to KeyboardBridge for hardware
    /// keyboard scenarios.
    func isKeyboardVisible() -> Bool {
        if keyboardVisibleFlag { return true }
        return KeyboardBridge.shared()?.hasActiveInput ?? false
    }

    /// Type text by injecting characters into the active keyboard.
    /// Routes through KeyboardBridge → UIKeyboardImpl.addInputString: per character.
    func typeText(_ text: String, interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay) async -> Bool {
        guard let keyboard = KeyboardBridge.shared() else { return false }
        for char in text {
            keyboard.type(char)
            guard await Task.cancellableSleep(nanoseconds: interKeyDelay) else { break }
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
            guard await Task.cancellableSleep(nanoseconds: interKeyDelay) else { break }
        }
        return true
    }

    /// Clear all text in the focused text input using select-all + delete.
    /// Routes through the responder chain — no view hierarchy walk needed.
    func clearText() async -> Bool {
        // Select all via responder chain
        UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll), to: nil, from: nil, for: nil)
        guard await Task.cancellableSleep(for: Self.selectionSettleDelay) else { return false }

        // Delete via keyboard bridge (preferred) or responder chain
        if let keyboard = KeyboardBridge.shared() {
            keyboard.deleteBackward()
        } else {
            return false
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
    /// Routes through the responder chain — no view hierarchy walk needed.
    func resignFirstResponder() -> Bool {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

        for index in activeTouches.indices {
            let windowPoint = window.convert(points[index], from: nil)
            activeTouches[index].update(phase: .moved, location: windowPoint)
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

        for index in activeTouches.indices {
            activeTouches[index].update(phase: .stationary)
        }

        guard let event = TouchEvent(touches: activeTouches) else { return false }
        event.send()
        return true
    }

    /// Lift all active touches.
    func touchesUp() -> Bool {
        guard !activeTouches.isEmpty else { return false }

        for index in activeTouches.indices {
            activeTouches[index].update(phase: .ended)
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

// MARK: - Timing Constants

nonisolated extension TheSafecracker {

    /// Default inter-key delay for text injection (30ms). Single source of truth
    /// for typeText and deleteText default parameters.
    static let defaultInterKeyDelay: UInt64 = 30_000_000

    /// Maximum allowed inter-key delay (500ms) to prevent unreasonably slow typing.
    static let maxInterKeyDelay: UInt64 = 500_000_000

    /// Yield between touch began/ended phases (50ms) so SwiftUI's gesture
    /// pipeline has run-loop time to transition from "possible" to "recognized".
    static let gestureYieldDelay: Duration = .milliseconds(50)

    /// Yield after setting selectedTextRange (50ms) so the keyboard's internal
    /// state treats the selection as current before the subsequent delete.
    static let selectionSettleDelay: Duration = .milliseconds(50)

    /// Poll interval for keyboard readiness after tapping a text field (100ms).
    static let keyboardPollInterval: Duration = .milliseconds(100)

    /// Maximum number of polls before giving up on keyboard readiness (20 × 100ms = 2s).
    static let keyboardPollMaxAttempts: Int = 20
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
