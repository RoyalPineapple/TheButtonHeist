#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore
import ThePlans

/// Facade for mechanical input injection.
///
/// Element inflation and semantic-vs-mechanical policy live in TheBrains. This
/// type exposes low-level keyboard, edit, scroll, and coordinate/touch
/// primitives used after a command has resolved to concrete runtime input.
@MainActor
final class TheSafecracker {

    private let keyboardInput = SafecrackerKeyboardInput()
    private let touchInjection = SafecrackerTouchInjection()
    private let editActions = SafecrackerEditActions()

    var keyboardBridgeProvider: () -> KeyboardBridge? {
        get { keyboardInput.keyboardBridgeProvider }
        set { keyboardInput.keyboardBridgeProvider = newValue }
    }

    func startKeyboardObservation() {
        keyboardInput.startObservation()
    }

    func stopKeyboardObservation() {
        keyboardInput.stopObservation()
    }

    func isKeyboardVisible() -> Bool {
        keyboardInput.isKeyboardVisible()
    }

    func hasActiveTextInput() -> Bool {
        keyboardInput.hasActiveTextInput()
    }

    func typeText(
        _ text: String,
        interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay
    ) async -> KeyboardTextInjectionResult {
        await keyboardInput.typeText(text, interKeyDelay: interKeyDelay)
    }

    func performEditAction(_ action: EditAction) -> Bool {
        editActions.perform(action)
    }

    func resignFirstResponder() -> Bool {
        editActions.resignFirstResponder()
    }

    func tap(at point: CGPoint) async -> Bool {
        await touchInjection.tap(at: point)
    }

    func longPress(at point: CGPoint, duration: GestureDuration = .longPressDefault) async -> Bool {
        await touchInjection.longPress(at: point, duration: duration)
    }

    func swipe(from start: CGPoint, to end: CGPoint, duration: GestureDuration = .swipeDefault) async -> Bool {
        await touchInjection.swipe(from: start, to: end, duration: duration)
    }

    func drag(from start: CGPoint, to end: CGPoint, duration: GestureDuration = .dragDefault) async -> Bool {
        await touchInjection.drag(from: start, to: end, duration: duration)
    }
}

// MARK: - Timing Constants

nonisolated extension TheSafecracker {

    /// Default inter-key delay for text injection (30ms).
    static let defaultInterKeyDelay: UInt64 = 30_000_000

    /// Yield between touch began/ended phases (50ms) so SwiftUI's gesture
    /// pipeline has run-loop time to transition from "possible" to "recognized".
    static let gestureYieldDelay: Duration = .milliseconds(50)

    /// Dispatch cadence for synthetic gesture movement events (10ms).
    static let touchGestureStepDelay: TimeInterval = 0.01

    /// Poll interval for keyboard readiness after tapping a text field (100ms).
    static let keyboardPollInterval: Duration = .milliseconds(100)

    /// Maximum number of polls before giving up on keyboard readiness (20 × 100ms = 2s).
    static let keyboardPollMaxAttempts: Int = 20
}

#endif // DEBUG
#endif // canImport(UIKit)
