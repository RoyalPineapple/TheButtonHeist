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
/// The accessibility tree is TheStash's domain; TheTripwire never reads it.
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

    var onTransition: (@MainActor (PulseTransition) -> Void)?

    private var pulsePhase: PulsePhase = .idle

    private var runningContext: RunningContext? {
        if case .running(let context) = pulsePhase { return context }
        return nil
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
    }

    func stopPulse() {
        guard let context = runningContext else { return }
        context.link.invalidate()

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
            guard await Task.cancellableSleep(for: .milliseconds(intervalMs)) else { break }
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
            windowCount: scan.windowCount,
            quietFrames: isQuiet ? (prev?.quietFrames ?? 0) + 1 : 0
        )
        context.latestReading = reading

        // Diff against previous reading and fire transitions
        if vcId != prev?.topmostVC {
            onTransition?(.screenChanged(from: prev?.topmostVC, to: vcId))
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

    // MARK: - Window Access

    /// All visible, non-fingerprint windows in foreground-active scenes, sorted
    /// by window level (front to back). Collects from all `UIWindowScene`s — not
    /// just key windows — so system-managed windows (popup menus, action sheets,
    /// alerts presented in their own UIWindow) are included without leaking
    /// inactive multi-window scenes into the accessibility tree.
    func getTraversableWindows() -> [(window: UIWindow, rootView: UIView)] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .filter { window in
                !(window is TheFingerprints.FingerprintWindow)
                    && !window.isHidden
                    && window.bounds.size != .zero
            }
            .sorted { $0.windowLevel > $1.windowLevel }
            .map { ($0, $0 as UIView) }
    }

    /// Windows filtered for accessibility tree parsing. Mirrors the filtering
    /// VoiceOver applies — only the topmost modal context is exposed, and
    /// everything beneath it is hidden from the tree.
    ///
    /// Three independent checks, in order:
    /// 1. **Explicit modal flag** — any window containing a view with
    ///    `accessibilityViewIsModal` set (popovers, custom overlays).
    /// 2. **Overlay window** — frontmost non-passthrough window has
    ///    `windowLevel > .normal` (UIAlertController, action sheets,
    ///    status-bar level UI). System decoration windows like the software
    ///    keyboard and text-effects window are excluded — they sit above
    ///    `.normal` but are not modal takeovers.
    /// 3. **Modal presentation** — a window's root VC has a presented VC,
    ///    in which case only the deepest presented VC's view is parsed,
    ///    matching what `UIPresentationController` exposes to UIKit's AX.
    ///
    /// If none match, all traversable non-passthrough windows are returned.
    ///
    /// For screenshots, use `getTraversableWindows()` — visual compositing should
    /// include all windows so the dimmed background remains visible.
    func getAccessibleWindows() -> [(window: UIWindow, rootView: UIView)] {
        Self.filterToAccessibleWindows(getTraversableWindows())
    }

    /// Window classes iOS uses for system-managed UI decorations that sit
    /// above `windowLevel.normal` but contain no app content the agent can
    /// usefully act on. Treating them as the topmost overlay would hide the
    /// real app window beneath, which is the common cause of "0 elements"
    /// snapshots while a software keyboard is up. `nonisolated` so the
    /// passthrough check can run as a plain `(UIWindow) -> Bool` — the data
    /// is immutable and touches no main-actor state.
    nonisolated static let systemPassthroughWindowClassNames: Set<String> = [
        "UIRemoteKeyboardWindow",
        "UITextEffectsWindow",
    ]

    /// Whether a window is a system-managed decoration (keyboard, text-effects)
    /// that should not be treated as a modal takeover even though its window
    /// level is above `.normal`.
    nonisolated static func isSystemPassthroughWindow(_ window: UIWindow) -> Bool {
        systemPassthroughWindowClassNames.contains(NSStringFromClass(type(of: window)))
    }

    /// Pure filter applying the VoiceOver-equivalent precedence chain to a
    /// window list. Extracted from `getAccessibleWindows()` so callers can
    /// supply a controlled list and the precedence logic can be exercised
    /// without depending on the host app's window state.
    ///
    /// `isPassthrough` lets tests inject a custom predicate so the
    /// passthrough branch can be exercised without instantiating private
    /// UIKit window classes.
    static func filterToAccessibleWindows(
        _ windows: [(window: UIWindow, rootView: UIView)],
        isPassthrough: (UIWindow) -> Bool = isSystemPassthroughWindow
    ) -> [(window: UIWindow, rootView: UIView)] {
        guard !windows.isEmpty else { return [] }

        if let modalEntry = windows.first(where: { containsModalView($0.window) }) {
            return [modalEntry]
        }

        let appWindows = windows.filter { !isPassthrough($0.window) }

        if let top = appWindows.first,
           top.window.windowLevel > .normal,
           top.window.rootViewController != nil {
            return [top]
        }

        if let presented = appWindows.lazy.compactMap(deepestPresentedEntry).first {
            return [presented]
        }

        return appWindows.isEmpty ? windows : appWindows
    }

    /// If `entry`'s root VC has a presentation chain, return the deepest
    /// presented VC's view paired with the window. Returns `nil` when there
    /// is no root VC or no presentation chain.
    private static func deepestPresentedEntry(
        _ entry: (window: UIWindow, rootView: UIView)
    ) -> (window: UIWindow, rootView: UIView)? {
        guard let rootVC = entry.window.rootViewController else { return nil }
        let chain = Array(sequence(first: rootVC, next: \.presentedViewController))
        guard let deepest = chain.last, deepest !== rootVC else { return nil }
        return (window: entry.window, rootView: deepest.view)
    }

    /// Check whether a window contains a view with `accessibilityViewIsModal`.
    /// Walks up to 4 levels deep to account for UIKit's internal wrapper views
    /// (e.g. `UITransitionView`, `UIDropShadowView`) inserted between the window
    /// and the view controller's content.
    private static func containsModalView(_ window: UIWindow) -> Bool {
        func check(_ view: UIView, depth: Int) -> Bool {
            if view.accessibilityViewIsModal { return true }
            guard depth > 0 else { return false }
            return view.subviews.contains { check($0, depth: depth - 1) }
        }
        return check(window, depth: 4)
    }

    // MARK: - View Controller Identity

    /// The topmost visible view controller — the deepest pushed/presented VC.
    /// Skips system passthrough windows (keyboard, text-effects) so a keyboard
    /// appearance doesn't falsely register as a view-controller change.
    func topmostViewController() -> UIViewController? {
        Self.topmostViewController(in: getTraversableWindows())
    }

    /// Pure topmost-VC resolution against an explicit window list. Extracted
    /// so the passthrough-skip logic can be exercised in unit tests without
    /// relying on the host app's window state. `isPassthrough` lets tests
    /// inject a custom predicate without instantiating private UIKit window
    /// classes.
    static func topmostViewController(
        in windows: [(window: UIWindow, rootView: UIView)],
        isPassthrough: (UIWindow) -> Bool = isSystemPassthroughWindow
    ) -> UIViewController? {
        guard let root = windows
            .first(where: { !isPassthrough($0.window) })?
            .window.rootViewController
        else {
            return nil
        }
        return deepestViewController(from: root)
    }

    private static func deepestViewController(from vc: UIViewController) -> UIViewController {
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
