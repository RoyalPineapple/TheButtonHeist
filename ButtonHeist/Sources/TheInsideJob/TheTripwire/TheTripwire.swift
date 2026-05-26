#if canImport(UIKit)
#if DEBUG
import UIKit

/// Detects UIKit tripwire triggers without touching the accessibility tree.
///
/// TheTripwire monitors UIKit signals via a persistent ~10 Hz pulse — a single
/// CADisplayLink that samples all UI state on one clock. Every tick runs the
/// full set of checks: layer scan (fingerprint, animations, layout), VC
/// identity, public navigation state, and ordered visible windows.
///
/// The pulse answers three questions:
/// 1. **Is the UI settled?** (no animations, no pending layout, stable fingerprint)
/// 2. **Should the accessibility tree be checked again?** (Tripwire triggered)
/// 3. **What transitioned?** (settle/unsettle, Tripwire triggered)
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
        let tripwireSignal: TripwireSignal
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
        case tripwireTriggered(from: TripwireSignal, to: TripwireSignal)
    }

    enum PulseTickBaseline {
        case firstTick
        case observed(PulseReading)

        init(previous: PulseReading?) {
            if let previous {
                self = .observed(previous)
            } else {
                self = .firstTick
            }
        }

        func isQuiet(scan: LayerScan, fingerprint: PresentationFingerprint) -> Bool {
            guard !scan.hasPendingLayout, !scan.hasRelevantAnimations else { return false }
            switch self {
            case .firstTick:
                return true
            case .observed(let previous):
                return previous.fingerprint.matches(fingerprint)
            }
        }

        func quietFrames(afterQuiet quiet: Bool) -> Int {
            guard quiet else { return 0 }
            switch self {
            case .firstTick:
                return 1
            case .observed(let previous):
                return previous.quietFrames + 1
            }
        }

        func transitions(to reading: PulseReading) -> [PulseTransition] {
            switch self {
            case .firstTick:
                return []
            case .observed(let previous):
                return observedTransitions(from: previous, to: reading)
            }
        }

        private func observedTransitions(
            from previous: PulseReading,
            to reading: PulseReading
        ) -> [PulseTransition] {
            var transitions: [PulseTransition] = []
            if reading.tripwireSignal != previous.tripwireSignal {
                transitions.append(.tripwireTriggered(from: previous.tripwireSignal, to: reading.tripwireSignal))
            }
            if reading.isSettled && !previous.isSettled {
                transitions.append(.settled)
            } else if !reading.isSettled && previous.isSettled {
                transitions.append(.unsettled)
            }
            return transitions
        }
    }

    /// Cheap UIKit-side identity used to decide whether to re-check the
    /// accessibility tree. A changed Tripwire signal means "parse and check";
    /// it does not guarantee the parsed interface changed.
    struct TripwireSignal: Equatable {
        static let empty = TripwireSignal(
            topmostVC: nil,
            navigation: .empty,
            windowStack: .empty
        )

        let topmostVC: ObjectIdentifier?
        let navigation: NavigationSignal
        let windowStack: WindowStackSignal
    }

    /// Public UIKit navigation state sampled from the topmost controller. This
    /// catches SwiftUI NavigationStack-style changes that remain inside one
    /// hosting controller, without walking SwiftUI's private view tree.
    struct NavigationSignal: Equatable {
        static let empty = NavigationSignal(
            navigationDepth: nil,
            title: nil,
            backButtonTitle: nil,
            selectedTabIndex: nil,
            presentedViewController: nil
        )

        let navigationDepth: Int?
        let title: String?
        let backButtonTitle: String?
        let selectedTabIndex: Int?
        let presentedViewController: ObjectIdentifier?
    }

    /// Ordered visible window identity. Key-window status is deliberately part
    /// of the Tripwire signal, not an accessibility-scope filter.
    struct WindowStackSignal: Equatable {
        static let empty = WindowStackSignal(windows: [])

        let windows: [WindowSignal]
    }

    struct WindowSignal: Equatable {
        let id: ObjectIdentifier
        let level: CGFloat
        let isKeyWindow: Bool
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

    private enum LayerSamplingTarget {
        case presentation(CALayer)
        case model(CALayer)

        var layer: CALayer {
            switch self {
            case .presentation(let layer), .model(let layer):
                return layer
            }
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
                let sampledLayer = Self.layerSamplingTarget(for: layer).layer
                scan.positionXSum += sampledLayer.position.x
                scan.positionYSum += sampledLayer.position.y
                scan.opacitySum += CGFloat(sampledLayer.opacity)
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

    private static func layerSamplingTarget(for layer: CALayer) -> LayerSamplingTarget {
        if let presentationLayer = layer.presentation() {
            return .presentation(presentationLayer)
        }
        return .model(layer)
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
    ///
    /// **Settle signal boundary.** This is the layer-level settle path: it
    /// watches CALayer fingerprint, animations, and pending layout, and
    /// never reads the AX tree. Use it when the caller only needs "the UI
    /// has stopped moving" — post-jump SPI animations, broadcast pacing,
    /// wait-for-idle, wait-for-change polling. For post-action correctness
    /// (where AX-tree fingerprint stability is the load-bearing signal)
    /// use `SettleSession` instead; for per-frame swipe motion detection
    /// (where the viewport heistId set is the signal) use the swipe-settle
    /// loop in `Navigation+Scroll.swift`. The boundary is intentional —
    /// layer quiet and AX-tree quiet disagree on every spinner.
    func waitForAllClear(timeout: TimeInterval = 1.0) async -> Bool {
        await waitForSettle(timeout: timeout)
    }

    /// Yield to the main run loop for N display frames. Each iteration
    /// flushes pending Core Animation transactions and gives layout a
    /// chance to run — enough for lazy containers to materialise content
    /// without waiting for animations to finish.
    ///
    /// **Settle signal boundary.** Fixed-count yields are not a settle
    /// signal — they are empirically calibrated waits for known animation
    /// timings. Use this when the caller needs to advance a known number
    /// of layout passes (post-scroll CATransaction flush, intra-swipe
    /// frame stepping) without subscribing to the persistent pulse. For
    /// signal-driven waits, see `waitForAllClear` (layer) or `SettleSession`
    /// (AX tree).
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
    ///
    /// Same fixed-count contract as `yieldFrames(_:)` — see that doc for
    /// the four-implementation settle-signal boundary.
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
        let baseline = PulseTickBaseline(previous: context.latestReading)

        // Flush pending implicit transactions so SwiftUI's deferred
        // layout commits before we scan.
        CATransaction.flush()

        let scan = scanLayers()
        let fingerprint = scan.fingerprint

        let isQuiet = baseline.isQuiet(scan: scan, fingerprint: fingerprint)

        let tripwireSignal = tripwireSignal()
        let vcId = tripwireSignal.topmostVC

        let reading = PulseReading(
            tick: context.tickCount,
            timestamp: now,
            layoutPending: scan.hasPendingLayout,
            fingerprint: fingerprint,
            hasRelevantAnimations: scan.hasRelevantAnimations,
            topmostVC: vcId,
            tripwireSignal: tripwireSignal,
            windowCount: scan.windowCount,
            quietFrames: baseline.quietFrames(afterQuiet: isQuiet)
        )
        context.latestReading = reading

        for transition in baseline.transitions(to: reading) {
            onTransition?(transition)
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

    /// All visible windows in foreground-active scenes, sorted by window level
    /// (front to back). Collects from all `UIWindowScene`s — not just key
    /// windows — so system-managed windows (popup menus, action sheets, alerts
    /// presented in their own UIWindow) are included without leaking inactive
    /// multi-window scenes into the accessibility tree.
    static func orderedVisibleWindows(includeFingerprints: Bool = false) -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .filter { window in
                (includeFingerprints || !(window is TheFingerprints.FingerprintWindow))
                    && !window.isHidden
                    && window.bounds.size != .zero
            }
            .sorted { $0.windowLevel > $1.windowLevel }
    }

    /// All visible, non-fingerprint windows in foreground-active scenes, sorted
    /// by window level (front to back).
    func getTraversableWindows() -> [(window: UIWindow, rootView: UIView)] {
        Self.orderedVisibleWindows()
            .map { ($0, $0 as UIView) }
    }

    /// Tripwire identity sampled from public UIKit state without touching AX.
    func tripwireSignal() -> TripwireSignal {
        let windows = Self.orderedVisibleWindows()
        let entries = windows.map { ($0, $0 as UIView) }
        let topmost = Self.topmostViewController(in: entries)
        return TripwireSignal(
            topmostVC: topmost.map(ObjectIdentifier.init),
            navigation: Self.navigationSignal(for: topmost),
            windowStack: Self.windowStackSignal(for: windows)
        )
    }

    /// Ordered visible window identity. Used as a change signal only; never
    /// as a rule for excluding lower windows from the accessibility tree.
    static func windowStackSignal(for windows: [UIWindow]) -> WindowStackSignal {
        WindowStackSignal(windows: windows.map { window in
            WindowSignal(
                id: ObjectIdentifier(window),
                level: window.windowLevel.rawValue,
                isKeyWindow: window.isKeyWindow
            )
        })
    }

    /// Public navigation signal for UIKit and SwiftUI-hosted screens.
    static func navigationSignal(for viewController: UIViewController?) -> NavigationSignal {
        guard let viewController else { return .empty }

        let navigationController = resolvedNavigationController(for: viewController)
        let tabBarController = resolvedTabBarController(for: viewController)
        let navigationItem = viewController.navigationItem
        let topNavigationItem = navigationController?.navigationBar.topItem

        return NavigationSignal(
            navigationDepth: navigationController?.viewControllers.count,
            title: resolvedTitle(
                navigationItem: navigationItem,
                viewController: viewController,
                topNavigationItem: topNavigationItem
            ),
            backButtonTitle: resolvedBackButtonTitle(
                navigationItem: navigationItem,
                topNavigationItem: topNavigationItem
            ),
            selectedTabIndex: tabBarController?.selectedIndex,
            presentedViewController: viewController.presentedViewController.map(ObjectIdentifier.init)
        )
    }

    private static func resolvedNavigationController(for viewController: UIViewController) -> UINavigationController? {
        if let navigationController = viewController as? UINavigationController {
            return navigationController
        }
        return viewController.navigationController
    }

    private static func resolvedTabBarController(for viewController: UIViewController) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        return viewController.tabBarController
    }

    private static func resolvedTitle(
        navigationItem: UINavigationItem,
        viewController: UIViewController,
        topNavigationItem: UINavigationItem?
    ) -> String? {
        if let title = navigationItem.title {
            return title
        }
        if let title = viewController.title {
            return title
        }
        return topNavigationItem?.title
    }

    private static func resolvedBackButtonTitle(
        navigationItem: UINavigationItem,
        topNavigationItem: UINavigationItem?
    ) -> String? {
        if let title = navigationItem.backButtonTitle {
            return title
        }
        if let title = navigationItem.backBarButtonItem?.title {
            return title
        }
        if let title = topNavigationItem?.backButtonTitle {
            return title
        }
        return topNavigationItem?.backBarButtonItem?.title
    }

    /// Windows that can be handed to the accessibility parser.
    ///
    /// This filter intentionally does not inspect the view hierarchy for
    /// `accessibilityViewIsModal`. It excludes system passthrough windows and
    /// preserves every remaining app window. The parser owns modal-scope
    /// discovery, and `TheBurglar` stops parsing lower windows when the parser
    /// emits a modal boundary container.
    ///
    /// Resolution steps, in order:
    /// 1. **System passthrough windows** — keyboard and text-effects windows
    ///    are excluded because they sit above `.normal` but contain no app
    ///    content the agent can usefully act on.
    /// 2. **Modal presentation** — each window whose root VC has a presented
    ///    VC is parsed from the deepest presented VC's view, matching what
    ///    `UIPresentationController` exposes to UIKit's AX for that window.
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

        let appWindows = windows.filter { !isPassthrough($0.window) }
        return appWindows.map { entry in
            if let accessibleEntry = accessibleRootEntry(entry) {
                return accessibleEntry
            }
            return entry
        }
    }

    /// Return the view that should anchor accessibility parsing for a window.
    /// Parser-level UIKit guards handle private intermediary views; keeping the
    /// presented controller root preserves modal boundary metadata.
    private static func accessibleRootEntry(
        _ entry: (window: UIWindow, rootView: UIView)
    ) -> (window: UIWindow, rootView: UIView)? {
        guard let rootVC = entry.window.rootViewController else { return nil }
        let chain = Array(sequence(first: rootVC, next: \.presentedViewController))
        guard let deepest = chain.last else { return nil }
        let rootView = accessibilityRootView(for: deepest)
        guard rootView !== entry.rootView else { return deepest !== rootVC ? (entry.window, rootView) : nil }
        return (window: entry.window, rootView: rootView)
    }

    private static func accessibilityRootView(for viewController: UIViewController) -> UIView {
        return viewController.view
    }

    // MARK: - View Controller Identity

    /// The topmost visible view controller from public presentation and
    /// standard container state. Skips system passthrough windows (keyboard,
    /// text-effects) so a keyboard appearance doesn't falsely register as a
    /// view-controller change.
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
        return vc
    }

    /// Did Tripwire trigger? This prompts parsing only; parsed accessibility
    /// signatures classify the result as no-change, element-change, or
    /// screen-change.
    func didTripwireTrigger(before: TripwireSignal, after: TripwireSignal) -> Bool {
        before != after
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
            guard let reading = context.latestReading else { return false }
            return reading.isSettled
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
