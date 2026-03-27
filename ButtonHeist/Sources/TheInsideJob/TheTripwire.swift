#if canImport(UIKit)
#if DEBUG
import UIKit

/// Detects UI state changes without touching the accessibility tree.
///
/// TheTripwire monitors UIKit signals via a persistent ~10 Hz pulse — a single
/// CADisplayLink that samples all UI state on one clock. Cheap signals
/// (layer positions, animations, pending layout) run every tick; moderate
/// signals (VC identity) every 3rd tick; slow signals (keyboard, window count)
/// every 5th tick.
///
/// The pulse answers three questions:
/// 1. **Is the UI settled?** (no animations, no pending layout, stable fingerprint)
/// 2. **Did the screen change?** (VC identity comparison)
/// 3. **What transitioned?** (settle/unsettle, screen change, keyboard change)
///
/// The accessibility tree is TheBagman's domain; TheTripwire never reads it.
@MainActor
final class TheTripwire {

    // MARK: - Pulse Reading

    /// Snapshot of all monitored UI signals at a single tick.
    struct PulseReading {
        let tick: UInt64
        let timestamp: CFAbsoluteTime

        // Core signals (every tick)
        let layoutPending: Bool
        let fingerprint: PresentationFingerprint
        let hasRelevantAnimations: Bool

        // Moderate signals (every 3rd tick, carried forward between samples)
        let topmostVC: ObjectIdentifier?
        let firstResponder: ObjectIdentifier?

        // Slow signals (every 5th tick, carried forward between samples)
        let keyboardVisible: Bool
        let textInputActive: Bool
        let windowCount: Int

        // Derived settle state
        let quietFrames: Int

        /// The UI is settled when no layout is pending, no animations
        /// are running, and the fingerprint has been stable for 2+ frames.
        var isSettled: Bool {
            !layoutPending && !hasRelevantAnimations && quietFrames >= 2
        }
    }

    /// State transitions detected by the pulse.
    enum PulseTransition {
        case settled
        case unsettled
        case screenChanged(from: ObjectIdentifier?, to: ObjectIdentifier?)
        case focusChanged(from: ObjectIdentifier?, to: ObjectIdentifier?)
        case keyboardChanged(visible: Bool)
        case textInputChanged(active: Bool)
    }

    // MARK: - Presentation Layer Fingerprinting

    /// Fingerprint of all presentation layer positions in the window hierarchy.
    /// Summing positions is cheap and catches any layer movement — if anything
    /// shifts, the sum shifts.
    struct PresentationFingerprint {
        let positionXSum: CGFloat
        let positionYSum: CGFloat
        let opacitySum: CGFloat
        let layerCount: Int

        private static let posTolerance: CGFloat = 0.5
        private static let opacityTolerance: CGFloat = 0.05

        func matches(_ other: PresentationFingerprint) -> Bool {
            layerCount == other.layerCount
                && abs(positionXSum - other.positionXSum) < Self.posTolerance
                && abs(positionYSum - other.positionYSum) < Self.posTolerance
                && abs(opacitySum - other.opacitySum) < Self.opacityTolerance
        }
    }

    // MARK: - Combined Layer Scan

    /// Result of a single layer-tree walk that collects fingerprint,
    /// animation, and layout data in one pass.
    struct LayerScan {
        var positionXSum: CGFloat = 0
        var positionYSum: CGFloat = 0
        var opacitySum: CGFloat = 0
        var layerCount: Int = 0
        var hasRelevantAnimations = false
        var hasPendingLayout = false
        var windowCount: Int = 0

        var fingerprint: PresentationFingerprint {
            PresentationFingerprint(
                positionXSum: positionXSum,
                positionYSum: positionYSum,
                opacitySum: opacitySum,
                layerCount: layerCount
            )
        }
    }

    /// Walk every layer once, collecting fingerprint + animations + layout.
    func scanLayers() -> LayerScan {
        var scan = LayerScan()
        let windows = getTraversableWindows()
        scan.windowCount = windows.count
        for (window, _) in windows {
            var stack: [CALayer] = [window.layer]
            while let layer = stack.popLast() {
                let p = layer.presentation() ?? layer
                scan.positionXSum += p.position.x
                scan.positionYSum += p.position.y
                scan.opacitySum += CGFloat(p.opacity)
                scan.layerCount += 1

                if layer.needsLayout() {
                    scan.hasPendingLayout = true
                }

                if !scan.hasRelevantAnimations, let keys = layer.animationKeys() {
                    scan.hasRelevantAnimations = keys.contains { key in
                        !Self.ignoredAnimationKeyPrefixes.contains { key.hasPrefix($0) }
                    }
                }

                if let sublayers = layer.sublayers {
                    stack.append(contentsOf: sublayers)
                }
            }
        }
        return scan
    }

    // MARK: - Pulse State

    private(set) var latestReading: PulseReading?
    var onTransition: ((PulseTransition) -> Void)?

    private var displayLink: CADisplayLink?
    private var pulseTarget: PulseTick?
    private var tickCount: UInt64 = 0
    private var quietFrameCount: Int = 0
    private var previousFingerprint: PresentationFingerprint?

    // Carried-forward state for Nth-tick signals
    private var lastKnownVC: ObjectIdentifier?
    private var lastKnownFirstResponder: ObjectIdentifier?
    private var lastKnownKeyboardVisible = false
    private var lastKnownTextInputActive = false
    private var lastKnownWindowCount = 0

    // Notification-driven flags (set by observers, read by tick)
    private(set) var keyboardVisibleFlag = false
    private(set) var textInputActiveFlag = false

    // Transition tracking
    private var wasSettled = false

    // Settle waiters
    private var settleWaiters: [SettleWaiter] = []

    private struct SettleWaiter {
        var quietFrames: Int
        let requiredQuietFrames: Int
        let deadline: CFAbsoluteTime
        let continuation: CheckedContinuation<Bool, Never>
    }

    // MARK: - Tick Cadence

    static let vcSampleCadence: UInt64 = 3
    static let slowSampleCadence: UInt64 = 5

    // MARK: - Pulse Lifecycle

    var isPulseRunning: Bool { displayLink != nil }

    func startPulse() {
        guard displayLink == nil else { return }
        let target = PulseTick(tripwire: self)
        let link = CADisplayLink(target: target, selector: #selector(PulseTick.handleTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 12, preferred: 10)
        link.add(to: .main, forMode: .common)
        displayLink = link
        pulseTarget = target
        startNotificationObservation()
    }

    func stopPulse() {
        displayLink?.invalidate()
        displayLink = nil
        pulseTarget = nil
        stopNotificationObservation()

        // Resolve any pending waiters as timed out
        for waiter in settleWaiters {
            waiter.continuation.resume(returning: false)
        }
        settleWaiters.removeAll()

        latestReading = nil
        tickCount = 0
        quietFrameCount = 0
        previousFingerprint = nil
        wasSettled = false
        lastKnownVC = nil
        lastKnownFirstResponder = nil
        lastKnownKeyboardVisible = false
        lastKnownTextInputActive = false
        lastKnownWindowCount = 0
        keyboardVisibleFlag = false
        textInputActiveFlag = false
    }

    // MARK: - Settle Waiting

    /// Wait for the UI to settle — no animations, no pending layout,
    /// stable fingerprint for `requiredQuietFrames` consecutive ticks.
    ///
    /// Each waiter tracks its own quiet-frame count from the moment of
    /// registration, so post-action animations are captured even if the
    /// pulse was already settled.
    ///
    /// Returns true if settled before timeout, false if timed out.
    func waitForSettle(timeout: TimeInterval = 1.0, requiredQuietFrames: Int = 2) async -> Bool {
        startPulse()
        return await withCheckedContinuation { continuation in
            settleWaiters.append(SettleWaiter(
                quietFrames: 0,
                requiredQuietFrames: requiredQuietFrames,
                deadline: CFAbsoluteTimeGetCurrent() + timeout,
                continuation: continuation
            ))
        }
    }

    /// Wait for the interface to become all clear.
    ///
    /// Delegates to `waitForSettle` — the persistent pulse handles monitoring.
    /// Returns true if settled before timeout, false if timed out.
    func waitForAllClear(timeout: TimeInterval = 1.0) async -> Bool {
        await waitForSettle(timeout: timeout)
    }

    // MARK: - Tick Handler

    fileprivate func onTick() {
        tickCount += 1
        let now = CFAbsoluteTimeGetCurrent()

        // Flush pending implicit transactions so SwiftUI's deferred
        // layout commits before we scan.
        CATransaction.flush()

        // Single layer walk for all core signals
        let scan = scanLayers()
        let fingerprint = scan.fingerprint

        let isQuiet = !scan.hasPendingLayout
            && !scan.hasRelevantAnimations
            && (previousFingerprint?.matches(fingerprint) ?? true)

        if isQuiet {
            quietFrameCount += 1
        } else {
            quietFrameCount = 0
        }
        previousFingerprint = fingerprint

        // VC identity + first responder (every 3rd tick)
        if tickCount % Self.vcSampleCadence == 0 {
            let vcId = topmostViewController().map(ObjectIdentifier.init)
            if vcId != lastKnownVC {
                let oldVC = lastKnownVC
                lastKnownVC = vcId
                onTransition?(.screenChanged(from: oldVC, to: vcId))
            }

            let responderId = currentFirstResponder().map(ObjectIdentifier.init)
            if responderId != lastKnownFirstResponder {
                let oldResponder = lastKnownFirstResponder
                lastKnownFirstResponder = responderId
                onTransition?(.focusChanged(from: oldResponder, to: responderId))
            }
        }

        // Slow signals (every 5th tick)
        if tickCount % Self.slowSampleCadence == 0 {
            lastKnownWindowCount = scan.windowCount

            if keyboardVisibleFlag != lastKnownKeyboardVisible {
                lastKnownKeyboardVisible = keyboardVisibleFlag
                onTransition?(.keyboardChanged(visible: keyboardVisibleFlag))
            }

            if textInputActiveFlag != lastKnownTextInputActive {
                lastKnownTextInputActive = textInputActiveFlag
                onTransition?(.textInputChanged(active: textInputActiveFlag))
            }
        }

        // Build reading
        let reading = PulseReading(
            tick: tickCount,
            timestamp: now,
            layoutPending: scan.hasPendingLayout,
            fingerprint: fingerprint,
            hasRelevantAnimations: scan.hasRelevantAnimations,
            topmostVC: lastKnownVC,
            firstResponder: lastKnownFirstResponder,
            keyboardVisible: lastKnownKeyboardVisible,
            textInputActive: lastKnownTextInputActive,
            windowCount: lastKnownWindowCount,
            quietFrames: quietFrameCount
        )
        latestReading = reading

        // Settle transitions
        let settled = reading.isSettled
        if settled && !wasSettled {
            onTransition?(.settled)
        } else if !settled && wasSettled {
            onTransition?(.unsettled)
        }
        wasSettled = settled

        resolveSettleWaiters(now: now, isQuiet: isQuiet)
    }

    private func resolveSettleWaiters(now: CFAbsoluteTime, isQuiet: Bool) {
        // Update quiet frames for all waiters
        for index in settleWaiters.indices {
            if isQuiet {
                settleWaiters[index].quietFrames += 1
            } else {
                settleWaiters[index].quietFrames = 0
            }
        }

        // Resolve and remove settled/timed-out waiters (reverse for safe removal)
        for index in settleWaiters.indices.reversed() {
            let waiter = settleWaiters[index]
            if waiter.quietFrames >= waiter.requiredQuietFrames {
                waiter.continuation.resume(returning: true)
                settleWaiters.remove(at: index)
            } else if now >= waiter.deadline {
                waiter.continuation.resume(returning: false)
                settleWaiters.remove(at: index)
            }
        }
    }

    // MARK: - Notification Observation

    private func startNotificationObservation() {
        let nc = NotificationCenter.default

        // Keyboard visibility — frame-based detection matches KIF's approach.
        // The frame check handles edge cases where the keyboard window exists
        // but is off-screen (undocked, floating, or dismissed mid-animation).
        nc.addObserver(self, selector: #selector(keyboardFrameDidChange),
                       name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        nc.addObserver(self, selector: #selector(keyboardWillShow),
                       name: UIResponder.keyboardWillShowNotification, object: nil)
        nc.addObserver(self, selector: #selector(keyboardDidHide),
                       name: UIResponder.keyboardDidHideNotification, object: nil)

        // Text input (first responder proxy)
        nc.addObserver(self, selector: #selector(textEditingDidBegin),
                       name: UITextField.textDidBeginEditingNotification, object: nil)
        nc.addObserver(self, selector: #selector(textEditingDidEnd),
                       name: UITextField.textDidEndEditingNotification, object: nil)
        nc.addObserver(self, selector: #selector(textEditingDidBegin),
                       name: UITextView.textDidBeginEditingNotification, object: nil)
        nc.addObserver(self, selector: #selector(textEditingDidEnd),
                       name: UITextView.textDidEndEditingNotification, object: nil)
    }

    private func stopNotificationObservation() {
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        nc.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        nc.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
        nc.removeObserver(self, name: UITextField.textDidBeginEditingNotification, object: nil)
        nc.removeObserver(self, name: UITextField.textDidEndEditingNotification, object: nil)
        nc.removeObserver(self, name: UITextView.textDidBeginEditingNotification, object: nil)
        nc.removeObserver(self, name: UITextView.textDidEndEditingNotification, object: nil)
    }

    @objc private func keyboardFrameDidChange(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let screenBounds = UIScreen.main.bounds
        keyboardVisibleFlag = endFrame.intersects(screenBounds)
            && endFrame.height > 0
            && endFrame.origin.y < screenBounds.height
    }

    @objc private func keyboardWillShow() { keyboardVisibleFlag = true }
    @objc private func keyboardDidHide() { keyboardVisibleFlag = false }
    @objc private func textEditingDidBegin() { textInputActiveFlag = true }
    @objc private func textEditingDidEnd() { textInputActiveFlag = false }

    // MARK: - Window Access

    /// The traversable windows in the active scene, sorted by window level (front to back).
    /// Shared with TheBagman — both need the same window set.
    func getTraversableWindows() -> [(window: UIWindow, rootView: UIView)] {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            return []
        }

        return windowScene.windows
            .filter { window in
                !(window is TheFingerprints.FingerprintWindow)
                    && !window.isHidden
                    && window.bounds.size != .zero
            }
            .sorted { $0.windowLevel > $1.windowLevel }
            .map { ($0, $0 as UIView) }
    }

    // MARK: - First Responder

    /// The current first responder view, if any.
    /// Walks the view hierarchy of all traversable windows.
    func currentFirstResponder() -> UIView? {
        for (window, _) in getTraversableWindows() {
            if let responder = findFirstResponder(in: window) {
                return responder
            }
        }
        return nil
    }

    private func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = findFirstResponder(in: sub) { return found }
        }
        return nil
    }

    // MARK: - View Controller Identity

    /// The topmost visible view controller — the deepest pushed/presented VC.
    func topmostViewController() -> UIViewController? {
        guard let root = getTraversableWindows().first?.window.rootViewController else {
            return nil
        }
        return deepestViewController(from: root)
    }

    private func deepestViewController(from vc: UIViewController) -> UIViewController {
        if let presented = vc.presentedViewController {
            return deepestViewController(from: presented)
        }
        if let nav = vc as? UINavigationController, let top = nav.topViewController {
            return deepestViewController(from: top)
        }
        if let tab = vc as? UITabBarController, let selected = tab.selectedViewController {
            return deepestViewController(from: selected)
        }
        for child in vc.children {
            if child is UINavigationController || child is UITabBarController {
                return deepestViewController(from: child)
            }
        }
        return vc
    }

    /// Did the view controller change? Compares VC identity before and after an action.
    func isScreenChange(before: ObjectIdentifier?, after: ObjectIdentifier?) -> Bool {
        guard let before, let after else { return before != nil || after != nil }
        return before != after
    }

    // MARK: - Standalone Queries

    /// Walk every layer in the traversable windows, sum their presentation positions.
    func takePresentationFingerprint() -> PresentationFingerprint {
        scanLayers().fingerprint
    }

    /// Are any layers in the window tree waiting for a layout pass?
    func hasPendingLayout() -> Bool {
        scanLayers().hasPendingLayout
    }

    /// Is the interface all clear? When the pulse is running, returns the
    /// latest reading's settle state. Otherwise falls back to a synchronous scan.
    func allClear() -> Bool {
        if let reading = latestReading { return reading.isSettled }
        let scan = scanLayers()
        return !scan.hasPendingLayout && !scan.hasRelevantAnimations
    }

    // MARK: - Constants

    private static let ignoredAnimationKeyPrefixes: [String] = [
        "_UIParallaxMotionEffect",
    ]
}

// MARK: - CADisplayLink Target

/// Weak-referencing target for the persistent CADisplayLink.
/// Auto-invalidates the link if TheTripwire is deallocated.
@MainActor
private final class PulseTick: NSObject {
    weak var tripwire: TheTripwire?

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
    }

    @objc func handleTick(_ link: CADisplayLink) {
        guard let tripwire else {
            link.invalidate()
            return
        }
        tripwire.onTick()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
