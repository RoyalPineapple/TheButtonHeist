#if canImport(UIKit)
#if DEBUG
import UIKit

/// Detects UI state changes without touching the accessibility tree.
///
/// TheTripwire reads UIKit signals — view controller identity, presentation
/// layer movement, animation keys — to answer two questions:
///
/// 1. **Is the UI still moving?** (presentation layer fingerprinting)
/// 2. **Did the screen change?** (view controller identity)
///
/// The accessibility tree is the wire currency; TheTripwire never reads it.
/// It tells the crew *when* to look and *what kind of change* happened,
/// so TheBagman knows whether to send a full snapshot or a diff.
@MainActor
final class TheTripwire {

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
    /// This is the screen boundary: if this changes between two snapshots, it's a screen change.
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

    /// Did the screen change? Compares VC identity before and after an action.
    /// Both nil means no VC either time (no change); one nil means appeared/disappeared (change).
    func isScreenChange(before: ObjectIdentifier?, after: ObjectIdentifier?) -> Bool {
        guard let before, let after else { return before != nil || after != nil }
        return before != after
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

    /// Walk every layer in the traversable windows, sum their presentation positions.
    func takePresentationFingerprint() -> PresentationFingerprint {
        var xSum: CGFloat = 0
        var ySum: CGFloat = 0
        var opacitySum: CGFloat = 0
        var count = 0

        for (window, _) in getTraversableWindows() {
            var stack: [CALayer] = [window.layer]
            while let layer = stack.popLast() {
                let p = layer.presentation() ?? layer
                xSum += p.position.x
                ySum += p.position.y
                opacitySum += CGFloat(p.opacity)
                count += 1
                if let sublayers = layer.sublayers {
                    stack.append(contentsOf: sublayers)
                }
            }
        }
        return PresentationFingerprint(
            positionXSum: xSum, positionYSum: ySum,
            opacitySum: opacitySum, layerCount: count
        )
    }

    private static let ignoredAnimationKeyPrefixes: [String] = [
        "_UIParallaxMotionEffect",
    ]

    /// Is the interface all clear? Returns true when no relevant
    /// animations are active in the layer tree. Cheap synchronous gate
    /// for callers that can't await (e.g. the polling loop).
    func allClear() -> Bool {
        !getTraversableWindows().contains { window in
            var stack: [CALayer] = [window.window.layer]
            while let layer = stack.popLast() {
                if let keys = layer.animationKeys() {
                    let hasRelevant = keys.contains { key in
                        !Self.ignoredAnimationKeyPrefixes.contains { key.hasPrefix($0) }
                    }
                    if hasRelevant { return true }
                }
                if let sublayers = layer.sublayers { stack.append(contentsOf: sublayers) }
            }
            return false
        }
    }

    /// Approximate frame rate used by the settle display link.
    /// Used to convert caller-supplied seconds to frame counts at system boundaries.
    static let settleFrameRate: Int = 10

    /// Wait for the interface to become all clear.
    ///
    /// Monitors presentation layer movement via CADisplayLink (~10 Hz).
    /// `maxFrames` is the budget in display-link ticks before giving up.
    /// Returns true if settled before the budget expires, false if timed out.
    func waitForAllClear(maxFrames: Int = 10) async -> Bool {
        // Brief initial delay — SwiftUI needs a run loop tick to start animations.
        try? await Task.sleep(nanoseconds: 30_000_000) // 30ms

        let previous = takePresentationFingerprint()

        return await withCheckedContinuation { continuation in
            let observer = DisplayLinkObserver(
                maxFrames: maxFrames,
                initialFingerprint: previous,
                tripwire: self,
                continuation: continuation
            )
            observer.start()
        }
    }

    // MARK: - CADisplayLink Observer

    /// Bridges CADisplayLink (callback-based) to async/await via CheckedContinuation.
    /// The display link retains its target, so we invalidate it as soon as we're done.
    @MainActor private final class DisplayLinkObserver: NSObject {
        private var displayLink: CADisplayLink?
        private let maxFrames: Int
        private var framesElapsed = 0
        private var previous: PresentationFingerprint
        private var quietFrames = 0
        private weak var tripwire: TheTripwire?
        private var continuation: CheckedContinuation<Bool, Never>?

        init(
            maxFrames: Int,
            initialFingerprint: PresentationFingerprint,
            tripwire: TheTripwire,
            continuation: CheckedContinuation<Bool, Never>
        ) {
            self.maxFrames = maxFrames
            self.previous = initialFingerprint
            self.tripwire = tripwire
            self.continuation = continuation
        }

        func start() {
            let link = CADisplayLink(target: self, selector: #selector(onFrame))
            // ~10 Hz: one layer-tree walk every ~100ms is plenty for detecting
            // settle within human reaction time, and 6-12x cheaper than vsync.
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 12, preferred: 10)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc private func onFrame(_ link: CADisplayLink) {
            guard let tripwire else {
                finish(settled: false)
                return
            }

            // 1. Presentation layer fingerprint check
            let current = tripwire.takePresentationFingerprint()

            if previous.matches(current) {
                quietFrames += 1
            } else {
                quietFrames = 0
            }
            previous = current

            framesElapsed += 1

            if quietFrames >= 2 {
                finish(settled: true)
                return
            }

            if framesElapsed >= maxFrames {
                finish(settled: false)
            }
        }

        private func finish(settled: Bool) {
            displayLink?.invalidate()
            displayLink = nil
            continuation?.resume(returning: settled)
            continuation = nil
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
