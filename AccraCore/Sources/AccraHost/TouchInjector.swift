#if canImport(UIKit)
import UIKit

/// Injects synthetic touch events for tap simulation.
///
/// Implementation based on KIF (Keep It Functional) testing framework.
/// Key iOS 26 fix: Creates a fresh UIEvent for each touch phase (began, ended)
/// instead of reusing the same event, which iOS 26's stricter validation rejects.
///
/// Fallback chain:
/// 1. Low-level touch injection via synthetic UIEvent + IOHIDEvent
/// 2. accessibilityActivate() on hit-tested view
/// 3. UIControl.sendActions(for: .touchUpInside)
/// 4. Responder chain walk for UIControl
@MainActor
final class TouchInjector {

    /// Result of a tap attempt with detailed information
    enum TapResult: Equatable {
        case success
        case viewNotInteractive(reason: String)
        case noViewAtPoint
        case noKeyWindow
        case injectionFailed
    }

    // MARK: - Public API

    /// Simulate a tap at the given screen coordinates.
    /// - Parameter point: Point in screen coordinates
    /// - Returns: True if tap was dispatched successfully
    func tap(at point: CGPoint) -> Bool {
        return tapWithResult(at: point) == .success
    }

    /// Simulate a tap with detailed result information
    /// - Parameter point: Point in screen coordinates
    /// - Returns: TapResult indicating success or failure reason
    func tapWithResult(at point: CGPoint) -> TapResult {
        guard let window = getKeyWindow() else {
            print("[TouchInjector] No key window found")
            return .noKeyWindow
        }

        let windowPoint = window.convert(point, from: nil)

        guard let hitView = window.hitTest(windowPoint, with: nil) else {
            print("[TouchInjector] No view at point")
            return .noViewAtPoint
        }

        // Check if the view is interactive
        if let reason = checkViewInteractivity(hitView) {
            print("[TouchInjector] View not interactive: \(reason)")
            return .viewNotInteractive(reason: reason)
        }

        // Try low-level touch injection first (works for all view types)
        if injectTap(at: windowPoint, window: window, view: hitView) {
            print("[TouchInjector] Tap injected via synthetic events")
            return .success
        }

        // Fall back to high-level methods
        if fallbackTap(view: hitView) {
            return .success
        }

        return .injectionFailed
    }

    // MARK: - Private: Interactivity Checks

    /// Check if a view is interactive and can receive taps
    /// - Returns: nil if interactive, or a reason string if not interactive
    private func checkViewInteractivity(_ view: UIView) -> String? {
        // Check UIView's user interaction property
        if !view.isUserInteractionEnabled {
            return "isUserInteractionEnabled is false"
        }

        // Check if view is hidden or has zero alpha
        if view.isHidden {
            return "view is hidden"
        }

        if view.alpha < 0.01 {
            return "view alpha is effectively zero"
        }

        // Check accessibility traits for disabled state
        if view.accessibilityTraits.contains(.notEnabled) {
            return "accessibility trait 'notEnabled' is set"
        }

        // Walk up the view hierarchy to check parent interactivity
        var parent = view.superview
        while let p = parent {
            if !p.isUserInteractionEnabled {
                return "parent view '\(type(of: p))' has isUserInteractionEnabled=false"
            }
            parent = p.superview
        }

        return nil  // View is interactive
    }

    // MARK: - Private: Low-Level Touch Injection

    /// Inject a tap using synthetic UITouch and UIEvent
    private func injectTap(at windowPoint: CGPoint, window: UIWindow, view: UIView) -> Bool {
        // Create touch for began phase
        guard let touch = SyntheticTouchFactory.createTouch(
            at: windowPoint,
            in: window,
            view: view,
            phase: .began
        ) else {
            print("[TouchInjector] Failed to create touch")
            return false
        }

        // Create IOHIDEvent for the touch
        let hidEventBegan = IOHIDEventBuilder.createEvent(
            for: [(touch: touch, location: windowPoint)],
            isTouching: true
        )

        // Attach HID event to touch
        if let hidEvent = hidEventBegan {
            SyntheticTouchFactory.setHIDEvent(touch, event: hidEvent)
        }

        // iOS 26 FIX: Create FRESH event for began phase
        guard let beganEvent = SyntheticEventFactory.createEventForTouch(touch, hidEvent: hidEventBegan) else {
            print("[TouchInjector] Failed to create began event")
            return false
        }

        // Send began event
        UIApplication.shared.sendEvent(beganEvent)

        // Update touch to ended phase
        SyntheticTouchFactory.setPhase(touch, phase: .ended)

        // Create IOHIDEvent for ended
        let hidEventEnded = IOHIDEventBuilder.createEvent(
            for: [(touch: touch, location: windowPoint)],
            isTouching: false
        )

        if let hidEvent = hidEventEnded {
            SyntheticTouchFactory.setHIDEvent(touch, event: hidEvent)
        }

        // iOS 26 FIX: Create FRESH event for ended phase (NOT reusing beganEvent!)
        guard let endedEvent = SyntheticEventFactory.createEventForTouch(touch, hidEvent: hidEventEnded) else {
            print("[TouchInjector] Failed to create ended event")
            return false
        }

        // Send ended event
        UIApplication.shared.sendEvent(endedEvent)

        return true
    }

    // MARK: - Private: High-Level Fallback

    /// Fall back to high-level activation methods
    private func fallbackTap(view: UIView) -> Bool {
        // Try accessibility activation
        if view.accessibilityActivate() {
            print("[TouchInjector] Activated via accessibilityActivate")
            return true
        }

        // Try sendActions for UIControl
        if let control = view as? UIControl {
            control.sendActions(for: .touchUpInside)
            print("[TouchInjector] Activated via sendActions")
            return true
        }

        // Walk up responder chain
        var responder: UIResponder? = view
        while let r = responder {
            if let control = r as? UIControl {
                control.sendActions(for: .touchUpInside)
                print("[TouchInjector] Activated control in responder chain")
                return true
            }
            responder = r.next
        }

        print("[TouchInjector] All activation methods failed")
        return false
    }

    // MARK: - Private Helpers

    private func getKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
#endif
