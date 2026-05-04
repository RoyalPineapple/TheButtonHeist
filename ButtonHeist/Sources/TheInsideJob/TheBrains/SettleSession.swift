#if canImport(UIKit)
#if DEBUG
import Foundation
import UIKit

import AccessibilitySnapshotParser

// MARK: - SettleOutcome

/// Result of running the multi-cycle AX-tree settle loop.
enum SettleOutcome: Equatable {

    /// The AX tree reached `cyclesRequired` consecutive stable cycles.
    case settled(timeMs: Int)

    /// Topmost VC changed during the loop. The caller hands off to the
    /// existing animation-aware repopulation handler, which is the right
    /// signal for "is the slide-in animation done?".
    case screenChanged(timeMs: Int)

    /// The hard timeout elapsed while the tree was still changing.
    case timedOut(timeMs: Int)

    var timeMs: Int {
        switch self {
        case .settled(let ms), .screenChanged(let ms), .timedOut(let ms): return ms
        }
    }

    /// True when the response represents a UI state we believe in —
    /// either the loop reached multi-cycle stability, or the settle loop
    /// was preempted by a screen transition (the caller's existing
    /// repopulation pipeline takes over and produces a valid snapshot of
    /// the new screen). Only `.timedOut` returns false.
    var didSettleCleanly: Bool {
        switch self {
        case .settled, .screenChanged: return true
        case .timedOut: return false
        }
    }
}

// MARK: - TimelineKey

/// Stable identity for an `AccessibilityElement` across settle cycles, with
/// `value` excluded so that spinner-style value churn (same element, value
/// cycles) maps to the same key. `(label, identifier, frame)` is the
/// signal a screen-reader user can perceive without value updates.
struct TimelineKey: Hashable {
    let label: String?
    let identifier: String?
    let frameMinX: Double
    let frameMinY: Double
    let frameWidth: Double
    let frameHeight: Double
}

extension AccessibilityElement {
    var timelineKey: TimelineKey {
        let rect: CGRect
        if case .frame(let r) = shape {
            rect = r
        } else {
            rect = .zero
        }
        return TimelineKey(
            label: label,
            identifier: identifier,
            frameMinX: Double(rect.origin.x),
            frameMinY: Double(rect.origin.y),
            frameWidth: Double(rect.size.width),
            frameHeight: Double(rect.size.height)
        )
    }
}

// MARK: - SettleSession

/// Multi-cycle accessibility-tree settle loop with inline transient capture.
///
/// Polls the parsed AX tree at fixed intervals. Returns `.settled` after
/// `cyclesRequired` consecutive identical fingerprints — with elements
/// carrying `UIAccessibilityTraits.updatesFrequently` masked out so spinners
/// don't block settle. CALayer animations are *not* consulted: a UI is
/// settled from a screen-reader user's perspective once the AX tree stops
/// changing, regardless of ongoing visual motion (analog clocks, animated
/// gradients, Lottie loops).
///
/// During the loop, every observed `AccessibilityElement` is keyed by
/// `TimelineKey` and accumulated into `seenKeys` / `elementsByKey`. After
/// settle, the caller subtracts baseline ∪ final keys to compute transient
/// elements (those that came and went mid-action) — no separate timeline
/// class needed. Owns no state across calls.
@MainActor
struct SettleSession {

    /// Hardcoded knobs. Exposing these as configuration would invite
    /// "make settle faster/slower" footguns without buying real ergonomics
    /// for any agent. If a workload genuinely needs different timing, use
    /// `wait_for_idle` with an explicit timeout.
    static let cyclesRequired: Int = 3
    static let cycleIntervalMs: Int = 100
    static let timeoutMs: Int = 5_000

    let stash: TheStash
    let tripwire: TheTripwire

    /// Result of the loop, exposed so the caller can compute transients.
    struct Outcome {
        let outcome: SettleOutcome
        /// Every `(key, element)` pair observed in any cycle of the loop.
        /// Includes spinner cycles and other intermediate states.
        let elementsByKey: [TimelineKey: AccessibilityElement]
    }

    func run(start: CFAbsoluteTime) async -> Outcome {
        let startVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
        let cycleNs = UInt64(Self.cycleIntervalMs) * 1_000_000
        let deadline = start + Double(Self.timeoutMs) / 1000

        var elementsByKey: [TimelineKey: AccessibilityElement] = [:]
        var stableCycles = 0
        var previousFingerprint: Int?

        while CFAbsoluteTimeGetCurrent() < deadline {
            do {
                try await Task.sleep(nanoseconds: cycleNs)
            } catch {
                return Outcome(
                    outcome: .timedOut(timeMs: Self.elapsedMs(since: start)),
                    elementsByKey: elementsByKey
                )
            }

            let nowVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
            if nowVC != startVC {
                return Outcome(
                    outcome: .screenChanged(timeMs: Self.elapsedMs(since: start)),
                    elementsByKey: elementsByKey
                )
            }

            guard let parse = stash.parse() else { continue }
            for element in parse.elements {
                elementsByKey[element.timelineKey] = element
            }

            let fingerprint = Self.fingerprint(of: parse.elements)
            if let previousFingerprint, fingerprint == previousFingerprint {
                stableCycles += 1
                if stableCycles >= Self.cyclesRequired {
                    return Outcome(
                        outcome: .settled(timeMs: Self.elapsedMs(since: start)),
                        elementsByKey: elementsByKey
                    )
                }
            } else {
                stableCycles = 0
            }
            previousFingerprint = fingerprint
        }

        return Outcome(
            outcome: .timedOut(timeMs: Self.elapsedMs(since: start)),
            elementsByKey: elementsByKey
        )
    }

    /// Hash the parsed elements with `updatesFrequently`-masked values, so
    /// spinners don't block settle. `updatesFrequently` is the iOS
    /// accessibility contract for "I update constantly, ignore me" —
    /// respecting it is a11y-correct.
    private static func fingerprint(of elements: [AccessibilityElement]) -> Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for element in elements {
            hasher.combine(element.label)
            hasher.combine(element.identifier)
            hasher.combine(element.traits.rawValue)
            if case .frame(let rect) = element.shape {
                hasher.combine(rect.origin.x)
                hasher.combine(rect.origin.y)
                hasher.combine(rect.size.width)
                hasher.combine(rect.size.height)
            }
            if !element.traits.contains(.updatesFrequently) {
                hasher.combine(element.value)
            }
        }
        return hasher.finalize()
    }

    private static func elapsedMs(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
