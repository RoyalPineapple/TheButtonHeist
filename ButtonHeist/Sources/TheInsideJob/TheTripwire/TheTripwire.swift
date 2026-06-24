#if canImport(UIKit)
#if DEBUG
import UIKit

/// Detects UIKit tripwire triggers without touching the accessibility tree.
///
/// TheTripwire monitors UIKit signals via a persistent low-frequency pulse — a single
/// CADisplayLink that samples all UI state on one clock. Every tick runs the
/// full set of checks: layer scan (fingerprint, animations, layout), VC
/// identity, public navigation state, and ordered visible windows.
///
/// The pulse answers three questions:
/// 1. **Is the UI settled?** (no pending layout, stable presentation fingerprint)
/// 2. **Should the accessibility tree be checked again?** (Tripwire triggered)
///
/// The accessibility tree is TheStash's domain; TheTripwire never reads it.
@MainActor
final class TheTripwire {

    var pulsePhase: PulsePhase = .idle

    var runningContext: RunningContext? {
        if case .running(let context) = pulsePhase { return context }
        return nil
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

    static let ignoredAnimationKeyPrefixes: [String] = [
        "_UIParallaxMotionEffect",
        "match-",
    ]

    static var pulseFrameRateRange: CAFrameRateRange {
        pulseFrameRateRange(knobs: .current)
    }

    static var singleTickSettleTimeout: TimeInterval {
        InsideJobRuntimeKnobs.current.singleTripwireTickSettleTimeout
    }

    static func pulseFrameRateRange(knobs: InsideJobRuntimeKnobs) -> CAFrameRateRange {
        let preferred = knobs.tripwirePulseFramesPerSecond
        let minimum = max(1, Int((Double(preferred) * 0.8).rounded(.down)))
        let maximum = max(preferred, Int((Double(preferred) * 1.2).rounded(.up)))
        return CAFrameRateRange(
            minimum: Float(minimum),
            maximum: Float(maximum),
            preferred: Float(preferred)
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
