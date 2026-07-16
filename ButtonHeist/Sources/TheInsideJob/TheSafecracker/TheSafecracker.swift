#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore
import ThePlans

@MainActor
final class TheSafecracker {

    struct PreparedTouchDispatch: Equatable, Sendable {
        fileprivate let preparedTouchID: SafecrackerTouchInjection.PreparedTouchID
    }

    private let keyboardInput = SafecrackerKeyboardInput()
    private let fingerprints: TheFingerprints
    private let touchInjection: SafecrackerTouchInjection
    private let editActions = SafecrackerEditActions()

    init(fingerprintsEnabled: Bool = true) {
        let fingerprints = TheFingerprints(isEnabled: fingerprintsEnabled)
        self.fingerprints = fingerprints
        self.touchInjection = SafecrackerTouchInjection(fingerprints: fingerprints)
    }

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

    func waitForActiveTextInput() async -> Bool {
        if hasActiveTextInput() { return true }
        for _ in 0..<Self.keyboardPollMaxAttempts {
            guard await Task.cancellableSleep(for: Self.keyboardPollInterval) else { return false }
            if hasActiveTextInput() { return true }
        }
        return false
    }

    func typeText(
        _ text: String,
        interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay
    ) async -> KeyboardTextInjectionResult {
        await keyboardInput.typeText(text, interKeyDelay: interKeyDelay)
    }

    func clearText(
        existingValue: String?,
        interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay
    ) async -> KeyboardTextInjectionResult {
        await keyboardInput.clearText(existingValue: existingValue, interKeyDelay: interKeyDelay)
    }

    func performEditAction(_ action: EditAction, on object: NSObject) -> Bool {
        editActions.perform(action, on: object)
    }

    func resignFirstResponder() -> Bool {
        editActions.resignFirstResponder()
    }

    func resignFirstResponder(_ object: NSObject) -> Bool {
        editActions.resignFirstResponder(object)
    }

    func showFingerprint(at point: CGPoint) {
        guard GeometryValidation.validateScreenPoint(point) == nil else { return }
        fingerprints.show(at: point)
    }

    func prepareTap(at point: CGPoint) -> PreparedTouchDispatch? {
        preparedTouchDispatch(touchInjection.prepareTap(at: point))
    }

    func prepareLongPress(
        at point: CGPoint,
        duration: GestureDuration = .longPressDefault
    ) -> PreparedTouchDispatch? {
        preparedTouchDispatch(touchInjection.prepareLongPress(at: point, duration: duration))
    }

    func prepareSwipe(
        from start: CGPoint,
        to end: CGPoint,
        duration: GestureDuration = .swipeDefault
    ) -> PreparedTouchDispatch? {
        preparedTouchDispatch(touchInjection.prepareSwipe(from: start, to: end, duration: duration))
    }

    func prepareDrag(
        from start: CGPoint,
        to end: CGPoint,
        duration: GestureDuration = .dragDefault
    ) -> PreparedTouchDispatch? {
        preparedTouchDispatch(touchInjection.prepareDrag(from: start, to: end, duration: duration))
    }

    private func preparedTouchDispatch(
        _ preparedTouchID: SafecrackerTouchInjection.PreparedTouchID?
    ) -> PreparedTouchDispatch? {
        preparedTouchID.map(PreparedTouchDispatch.init(preparedTouchID:))
    }

    func completePreparedTouch(_ dispatch: PreparedTouchDispatch) async -> Bool {
        await touchInjection.complete(dispatch.preparedTouchID)
    }
}

nonisolated extension TheSafecracker {

    static let defaultInterKeyDelay: UInt64 = 30_000_000

    static let gestureYieldDelay: Duration = .milliseconds(50)

    static let touchGestureStepDelay: TimeInterval = 0.01

    static let keyboardPollInterval: Duration = .milliseconds(100)

    static let keyboardPollMaxAttempts: Int = 20
}

#endif // DEBUG
#endif // canImport(UIKit)
