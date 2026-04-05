#if canImport(UIKit)
#if DEBUG
import UIKit

/// Detects UI state changes without touching the accessibility tree.
///
/// TheTripwire monitors UIKit signals via a persistent ~10 Hz pulse — a single
/// CADisplayLink that samples all UI state on one clock. Every tick runs the
/// full set of checks: layer scan (fingerprint, animations, layout), VC
/// identity, first responder, keyboard/text-input flags, and window count.
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

        let layoutPending: Bool
        let fingerprint: PresentationFingerprint
        let hasRelevantAnimations: Bool
        let topmostVC: ObjectIdentifier?
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
                let presentationLayer = layer.presentation() ?? layer
                scan.positionXSum += presentationLayer.position.x
                scan.positionYSum += presentationLayer.position.y
                scan.opacitySum += CGFloat(presentationLayer.opacity)
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

    /// Mutable context that exists only while the pulse is running.
    /// Reference type so tick mutations don't require enum reconstruction.
    private final class RunningContext {
        let link: CADisplayLink
        let target: PulseTick
        var latestReading: PulseReading?
        var tickCount: UInt64 = 0
        var keyboardVisibleFlag = false
        var textInputActiveFlag = false
        var settleWaiters: [SettleWaiter] = []

        init(link: CADisplayLink, target: PulseTick) {
            self.link = link
            self.target = target
        }
    }

    private enum PulsePhase {
        case idle
        case running(RunningContext)
    }

    /// The latest pulse reading, if the pulse is running.
    private(set) var latestReading: PulseReading? {
        get { runningContext?.latestReading }
        set { runningContext?.latestReading = newValue }
    }

    var onTransition: ((PulseTransition) -> Void)?

    private var pulsePhase: PulsePhase = .idle

    private var runningContext: RunningContext? {
        if case .running(let context) = pulsePhase { return context }
        return nil
    }

    /// Keyboard visibility flag, valid only while pulse is running.
    private(set) var keyboardVisibleFlag: Bool {
        get { runningContext?.keyboardVisibleFlag ?? false }
        set { runningContext?.keyboardVisibleFlag = newValue }
    }

    /// Text input flag, valid only while pulse is running.
    private(set) var textInputActiveFlag: Bool {
        get { runningContext?.textInputActiveFlag ?? false }
        set { runningContext?.textInputActiveFlag = newValue }
    }

    private struct SettleWaiter {
        var quietFrames: Int
        let requiredQuietFrames: Int
        let deadline: CFAbsoluteTime
        let continuation: CheckedContinuation<Bool, Never>
    }

    // MARK: - Pulse Lifecycle

    var isPulseRunning: Bool { runningContext != nil }

    func startPulse() {
        guard case .idle = pulsePhase else { return }
        let target = PulseTick(tripwire: self)
        let link = CADisplayLink(target: target, selector: #selector(PulseTick.handleTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 12, preferred: 10)
        link.add(to: .main, forMode: .common)
        pulsePhase = .running(RunningContext(link: link, target: target))
        startNotificationObservation()
    }

    func stopPulse() {
        guard let context = runningContext else { return }
        context.link.invalidate()
        stopNotificationObservation()

        for waiter in context.settleWaiters {
            waiter.continuation.resume(returning: false)
        }

        pulsePhase = .idle
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
        guard let context = runningContext else { return false }
        return await withCheckedContinuation { continuation in
            context.settleWaiters.append(SettleWaiter(
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

    /// Yield to the main run loop for N display frames. Each iteration
    /// flushes pending Core Animation transactions and gives layout a
    /// chance to run — enough for lazy containers to materialise content
    /// without waiting for animations to finish.
    func yieldFrames(_ count: Int) async {
        for _ in 0..<count {
            CATransaction.flush()
            await Task.yield()
        }
    }

    /// Yield frames with real wall-clock time between each.
    /// Unlike `yieldFrames` (which uses `Task.yield()`), this uses
    /// `Task.sleep` to give CADisplayLink animations time to process.
    /// Required for accessibility SPI scroll methods that queue animated
    /// scrolls — `Task.yield()` alone doesn't advance the animation.
    func yieldRealFrames(_ count: Int, intervalMs: UInt64 = 16) async {
        for _ in 0..<count {
            CATransaction.flush()
            try? await Task.sleep(for: .milliseconds(intervalMs))
        }
    }

    // MARK: - Tick Handler

    fileprivate func onTick() {
        guard let context = runningContext else { return }
        context.tickCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        let prev = context.latestReading

        // Flush pending implicit transactions so SwiftUI's deferred
        // layout commits before we scan.
        CATransaction.flush()

        let scan = scanLayers()
        let fingerprint = scan.fingerprint

        let isQuiet = !scan.hasPendingLayout
            && !scan.hasRelevantAnimations
            && (prev?.fingerprint.matches(fingerprint) ?? true)

        let vcId = topmostViewController().map(ObjectIdentifier.init)

        let reading = PulseReading(
            tick: context.tickCount,
            timestamp: now,
            layoutPending: scan.hasPendingLayout,
            fingerprint: fingerprint,
            hasRelevantAnimations: scan.hasRelevantAnimations,
            topmostVC: vcId,
            keyboardVisible: context.keyboardVisibleFlag,
            textInputActive: context.textInputActiveFlag,
            windowCount: scan.windowCount,
            quietFrames: isQuiet ? (prev?.quietFrames ?? 0) + 1 : 0
        )
        context.latestReading = reading

        // Diff against previous reading and fire transitions
        if vcId != prev?.topmostVC {
            onTransition?(.screenChanged(from: prev?.topmostVC, to: vcId))
        }
        if context.keyboardVisibleFlag != (prev?.keyboardVisible ?? false) {
            onTransition?(.keyboardChanged(visible: context.keyboardVisibleFlag))
        }
        if context.textInputActiveFlag != (prev?.textInputActive ?? false) {
            onTransition?(.textInputChanged(active: context.textInputActiveFlag))
        }
        if reading.isSettled && !(prev?.isSettled ?? false) {
            onTransition?(.settled)
        } else if !reading.isSettled && (prev?.isSettled ?? false) {
            onTransition?(.unsettled)
        }

        resolveSettleWaiters(context: context, now: now, isQuiet: isQuiet)
    }

    private func resolveSettleWaiters(context: RunningContext, now: CFAbsoluteTime, isQuiet: Bool) {
        for index in context.settleWaiters.indices {
            if isQuiet {
                context.settleWaiters[index].quietFrames += 1
            } else {
                context.settleWaiters[index].quietFrames = 0
            }
        }

        for index in context.settleWaiters.indices.reversed() {
            let waiter = context.settleWaiters[index]
            if waiter.quietFrames >= waiter.requiredQuietFrames {
                waiter.continuation.resume(returning: true)
                context.settleWaiters.remove(at: index)
            } else if now >= waiter.deadline {
                waiter.continuation.resume(returning: false)
                context.settleWaiters.remove(at: index)
            }
        }
    }

    // MARK: - Notification Observation

    private func startNotificationObservation() {
        let notificationCenter = NotificationCenter.default

        // Keyboard visibility — frame-based detection matches KIF's approach.
        // The frame check handles edge cases where the keyboard window exists
        // but is off-screen (undocked, floating, or dismissed mid-animation).
        notificationCenter.addObserver(self, selector: #selector(keyboardFrameDidChange),
                       name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(keyboardWillShow),
                       name: UIResponder.keyboardWillShowNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(keyboardDidHide),
                       name: UIResponder.keyboardDidHideNotification, object: nil)

        // Text input (first responder proxy)
        notificationCenter.addObserver(self, selector: #selector(textEditingDidBegin),
                       name: UITextField.textDidBeginEditingNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(textEditingDidEnd),
                       name: UITextField.textDidEndEditingNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(textEditingDidBegin),
                       name: UITextView.textDidBeginEditingNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(textEditingDidEnd),
                       name: UITextView.textDidEndEditingNotification, object: nil)
    }

    private func stopNotificationObservation() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        notificationCenter.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        notificationCenter.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
        notificationCenter.removeObserver(self, name: UITextField.textDidBeginEditingNotification, object: nil)
        notificationCenter.removeObserver(self, name: UITextField.textDidEndEditingNotification, object: nil)
        notificationCenter.removeObserver(self, name: UITextView.textDidBeginEditingNotification, object: nil)
        notificationCenter.removeObserver(self, name: UITextView.textDidEndEditingNotification, object: nil)
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
    /// latest reading's settle state (requires 2 consecutive quiet frames).
    /// Otherwise falls back to a synchronous scan checking both pending layout
    /// and active animations — stricter than the pre-pulse check which only
    /// looked at animations.
    func allClear() -> Bool {
        switch pulsePhase {
        case .running(let context):
            return context.latestReading?.isSettled ?? false
        case .idle:
            let scan = scanLayers()
            return !scan.hasPendingLayout && !scan.hasRelevantAnimations
        }
    }

    // MARK: - Constants

    private static let ignoredAnimationKeyPrefixes: [String] = [
        "_UIParallaxMotionEffect",
        "match-",
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
