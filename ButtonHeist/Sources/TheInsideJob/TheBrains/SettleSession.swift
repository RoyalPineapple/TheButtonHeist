#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import TheScore
import AccessibilitySnapshotParser

// MARK: - SettleOutcome

/// Result of running a multi-cycle AX-tree settle loop.
enum SettleOutcome: Equatable {

    /// The AX tree reached `cycles` consecutive stable cycles within
    /// `timeoutMs`. The most recently parsed snapshot is the result.
    case settled(timeMs: Int)

    /// The topmost view controller changed during the loop. Caller should
    /// hand off to the existing screen-transition repopulation handler,
    /// which uses Tripwire's animation-aware `waitForAllClear` — that's the
    /// signal that's appropriate for "is the slide-in animation done?".
    case screenChanged(timeMs: Int)

    /// The settle deadline elapsed while the tree was still changing.
    /// Caller returns the current state with `settled: false`.
    case timedOut(timeMs: Int)

    /// Wall-clock duration of the loop, in milliseconds.
    var timeMs: Int {
        switch self {
        case .settled(let ms), .screenChanged(let ms), .timedOut(let ms): return ms
        }
    }

    /// True iff the outcome reached a stable AX-tree state without bailing
    /// out for a screen transition or hitting the deadline.
    var didSettleCleanly: Bool {
        if case .settled = self { return true }
        return false
    }
}

// MARK: - SettleFingerprint

/// A reduction of the parsed accessibility tree to a single hash that masks
/// out value churn on elements carrying the `updatesFrequently` trait.
///
/// Two cycles with equal fingerprints are structurally identical from the
/// perspective of a screen-reader user: same set of elements, same labels,
/// same identifiers, same traits, same frames, and same values (except for
/// elements that have explicitly opted out of value monitoring via the
/// iOS `updatesFrequently` accessibility trait).
struct SettleFingerprint: Equatable {

    let hash: Int

    init(_ elements: [AccessibilityElement]) {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for element in elements {
            Self.combine(element, into: &hasher)
        }
        self.hash = hasher.finalize()
    }

    private static func combine(_ element: AccessibilityElement, into hasher: inout Hasher) {
        hasher.combine(element.label)
        hasher.combine(element.identifier)
        hasher.combine(element.traits.rawValue)
        if case .frame(let rect) = element.shape {
            hasher.combine(rect.origin.x)
            hasher.combine(rect.origin.y)
            hasher.combine(rect.size.width)
            hasher.combine(rect.size.height)
        }
        // Value churn on `updatesFrequently` elements is the iOS-defined
        // signal for "I update constantly, ignore me." Respecting that is
        // the accessibility-correct behaviour: spinners, timers, and other
        // self-cycling elements don't block settle even though their value
        // string changes every frame.
        if !element.traits.contains(.updatesFrequently) {
            hasher.combine(element.value)
        }
    }
}

// MARK: - SettleSession

/// Multi-cycle accessibility-tree settle loop.
///
/// Polls the parsed AX tree at fixed intervals and returns once the tree has
/// been stable for `config.cycles` consecutive observations, with
/// `updatesFrequently` value-churn ignored. CALayer animations are *not*
/// consulted here — a UI is settled from a screen-reader user's perspective
/// once the AX tree stops changing, regardless of ongoing visual motion
/// (analog clock hands, animated gradients, Lottie loops). Layer-animation
/// detection is the right tool for screen *transitions*, but not for
/// inter-screen stability — that's handled by the `.screenChanged` bail-out
/// path below.
///
/// Owns no state across calls — constructed per action.
@MainActor
struct SettleSession {

    /// 100ms cycle cadence. Hardcoded — exposing this as a knob would let
    /// callers tune polling cadence, which has no legitimate use case and
    /// would invite "make settle faster" footguns.
    static let cycleIntervalMs: Int = 100

    let config: SettleConfig
    let stash: TheStash
    let tripwire: TheTripwire
    /// Each cycle's parsed AX-tree is appended here so `actionResultWithDelta`
    /// can classify transient/flicker elements after settle finishes.
    let timeline: SnapshotTimeline

    /// Run the settle loop, returning the outcome and elapsed time.
    func run(start: CFAbsoluteTime) async -> SettleOutcome {
        let startVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
        let cycleNs = UInt64(Self.cycleIntervalMs) * 1_000_000
        let deadline = start + Double(config.timeoutMs) / 1000

        var stableCycles = 0
        var previousFingerprint: SettleFingerprint?

        while CFAbsoluteTimeGetCurrent() < deadline {
            do {
                try await Task.sleep(nanoseconds: cycleNs)
            } catch {
                return .timedOut(timeMs: Self.elapsedMs(since: start))
            }

            // Bail out if a screen transition started — let the existing
            // animation-aware repopulation handler take over.
            let nowVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
            if nowVC != startVC {
                return .screenChanged(timeMs: Self.elapsedMs(since: start))
            }

            // Read-only parse: peek at the live tree without mutating the
            // registry. Final apply happens once after settle, in the
            // caller's `actionResultWithDelta` flow.
            guard let parse = stash.parse() else { continue }
            timeline.append(parse.elements)
            let fingerprint = SettleFingerprint(parse.elements)

            if let previousFingerprint, fingerprint == previousFingerprint {
                stableCycles += 1
                if stableCycles >= config.cycles {
                    return .settled(timeMs: Self.elapsedMs(since: start))
                }
            } else {
                stableCycles = 0
            }
            previousFingerprint = fingerprint
        }
        return .timedOut(timeMs: Self.elapsedMs(since: start))
    }

    private static func elapsedMs(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

// MARK: - TheBrains Settle Resolver

extension TheBrains {

    /// Resolve the effective `SettleConfig` for an action. Per-action override
    /// (from the request envelope) wins over session config (from the auth
    /// handshake), which wins over built-in defaults.
    func resolveSettleConfig(perAction: SettleConfig?) -> SettleConfig {
        SettleConfig.resolve(perAction: perAction, session: sessionSettleConfig)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
