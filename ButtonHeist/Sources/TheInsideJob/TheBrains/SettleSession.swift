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

    /// The loop's structured-concurrency context was cancelled (e.g. the
    /// session was torn down mid-action). Distinct from `.timedOut` so the
    /// caller can short-circuit the rest of the action pipeline rather than
    /// continue parsing/exploring on a dead session.
    case cancelled(timeMs: Int)

    var timeMs: Int {
        switch self {
        case .settled(let ms), .screenChanged(let ms), .timedOut(let ms), .cancelled(let ms):
            return ms
        }
    }

    /// True when the response represents a UI state we believe in —
    /// either the loop reached multi-cycle stability, or the settle loop
    /// was preempted by a screen transition (the caller's existing
    /// repopulation pipeline takes over and produces a valid snapshot of
    /// the new screen). `.timedOut` and `.cancelled` return false.
    var didSettleCleanly: Bool {
        switch self {
        case .settled, .screenChanged: return true
        case .timedOut, .cancelled: return false
        }
    }
}

// MARK: - TimelineKey

/// Stable identity for an `AccessibilityElement` across settle cycles.
///
/// `value` is excluded so spinner-style value churn (same element, value
/// cycles) maps to the same key. Frame is *also* excluded for elements
/// carrying `updatesFrequently` — analog clocks, animated gradients, and
/// other elements that translate every frame would otherwise produce a
/// new key per cycle and flood the transient set.
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
        let masked = traits.contains(.updatesFrequently)
        return TimelineKey(
            label: label,
            identifier: identifier,
            frameMinX: masked ? 0 : Double(rect.origin.x),
            frameMinY: masked ? 0 : Double(rect.origin.y),
            frameWidth: masked ? 0 : Double(rect.size.width),
            frameHeight: masked ? 0 : Double(rect.size.height)
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
/// The loop seeds `previousFingerprint` from a synchronous parse *before*
/// the first sleep, so a static screen settles after exactly
/// `cyclesRequired` cycles (300 ms with the default 3 × 100 ms), not
/// `cyclesRequired + 1`.
///
/// During the loop, every observed `AccessibilityElement` is keyed by
/// `TimelineKey` and accumulated into `elementsByKey`. After settle, the
/// caller subtracts baseline ∪ final keys to compute transient elements
/// (those that came and went mid-action) — no separate timeline class
/// needed. Owns no state across calls.
///
/// Dependencies are injected as closures so unit tests can drive the loop
/// against a scripted sequence of parse results without standing up a
/// live UIKit hierarchy.
@MainActor
struct SettleSession {

    /// Hardcoded; tests override via init.
    static let defaultCyclesRequired: Int = 3
    static let defaultCycleIntervalMs: Int = 100
    static let defaultTimeoutMs: Int = 5_000

    typealias ParseProvider = @MainActor () -> TheStash.ParseResult?
    typealias TopVCProvider = @MainActor () -> ObjectIdentifier?
    typealias Sleeper = @Sendable (UInt64) async throws -> Void

    let parseProvider: ParseProvider
    let topVCProvider: TopVCProvider
    let sleeper: Sleeper
    let cyclesRequired: Int
    let cycleIntervalMs: Int
    let timeoutMs: Int

    init(
        parseProvider: @escaping ParseProvider,
        topVCProvider: @escaping TopVCProvider,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        cyclesRequired: Int = SettleSession.defaultCyclesRequired,
        cycleIntervalMs: Int = SettleSession.defaultCycleIntervalMs,
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) {
        self.parseProvider = parseProvider
        self.topVCProvider = topVCProvider
        self.sleeper = sleeper
        self.cyclesRequired = cyclesRequired
        self.cycleIntervalMs = cycleIntervalMs
        self.timeoutMs = timeoutMs
    }

    /// Live wiring against the real stash/tripwire. The default `sleeper`
    /// is `Task.sleep(nanoseconds:)`, which throws `CancellationError`
    /// when the surrounding task is cancelled — that propagates to
    /// `SettleOutcome.cancelled`.
    static func live(stash: TheStash, tripwire: TheTripwire) -> SettleSession {
        SettleSession(
            parseProvider: { stash.parse() },
            topVCProvider: { tripwire.topmostViewController().map(ObjectIdentifier.init) }
        )
    }

    /// Result of the loop, exposed so the caller can compute transients.
    struct Outcome {
        let outcome: SettleOutcome
        /// Every `(key, element)` pair observed in any cycle of the loop.
        /// Includes spinner cycles and other intermediate states.
        let elementsByKey: [TimelineKey: AccessibilityElement]
    }

    func run(start: CFAbsoluteTime) async -> Outcome {
        let startVC = topVCProvider()
        let cycleNs = UInt64(cycleIntervalMs) * 1_000_000
        let deadline = start + Double(timeoutMs) / 1000

        var elementsByKey: [TimelineKey: AccessibilityElement] = [:]
        var stableCycles = 0

        // Seed the baseline fingerprint synchronously so the first
        // post-sleep parse can already count as stable cycle 1. Without
        // this seed, a static screen pays cyclesRequired+1 cycles.
        var previousFingerprint: Int? = {
            guard let initial = parseProvider() else { return nil }
            for element in initial.elements {
                elementsByKey[element.timelineKey] = element
            }
            return Self.fingerprint(of: initial.elements)
        }()

        while CFAbsoluteTimeGetCurrent() < deadline {
            do {
                try await sleeper(cycleNs)
            } catch is CancellationError {
                return Outcome(
                    outcome: .cancelled(timeMs: Self.elapsedMs(since: start)),
                    elementsByKey: elementsByKey
                )
            } catch {
                return Outcome(
                    outcome: .timedOut(timeMs: Self.elapsedMs(since: start)),
                    elementsByKey: elementsByKey
                )
            }

            let nowVC = topVCProvider()
            if nowVC != startVC {
                return Outcome(
                    outcome: .screenChanged(timeMs: Self.elapsedMs(since: start)),
                    elementsByKey: elementsByKey
                )
            }

            guard let parse = parseProvider() else { continue }
            for element in parse.elements {
                elementsByKey[element.timelineKey] = element
            }

            let fingerprint = Self.fingerprint(of: parse.elements)
            if let previousFingerprint, fingerprint == previousFingerprint {
                stableCycles += 1
                if stableCycles >= cyclesRequired {
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
    static func fingerprint(of elements: [AccessibilityElement]) -> Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for element in elements {
            hasher.combine(element.label)
            hasher.combine(element.identifier)
            hasher.combine(element.traits.rawValue)
            let masked = element.traits.contains(.updatesFrequently)
            if case .frame(let rect) = element.shape, !masked {
                hasher.combine(rect.origin.x)
                hasher.combine(rect.origin.y)
                hasher.combine(rect.size.width)
                hasher.combine(rect.size.height)
            }
            if !masked {
                hasher.combine(element.value)
            }
        }
        return hasher.finalize()
    }

    private static func elapsedMs(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }

    /// Compute the elements that appeared during settle but are absent from
    /// both baseline and final — the "came and went" set. The settle loop
    /// already accumulates every observed element into `seenByKey`, so this
    /// is a set subtraction plus a deterministic sort.
    ///
    /// `Dictionary` iteration order is not guaranteed across runs, so we
    /// sort by `(frameMinY, frameMinX, label, identifier)` — visually
    /// natural reading order. Stable output across runs is load-bearing
    /// for snapshot consumers (benchmark golden files, reproducible LLM
    /// outputs against the same flow).
    static func transientElements(
        seenByKey: [TimelineKey: AccessibilityElement],
        baseline: [AccessibilityElement],
        final: [AccessibilityElement]
    ) -> [AccessibilityElement] {
        if seenByKey.isEmpty { return [] }
        let baselineKeys = Set(baseline.map(\.timelineKey))
        let finalKeys = Set(final.map(\.timelineKey))
        let candidates = seenByKey.compactMap { key, element -> AccessibilityElement? in
            (baselineKeys.contains(key) || finalKeys.contains(key)) ? nil : element
        }
        return candidates.sorted { lhs, rhs in
            let lhsKey = lhs.timelineKey
            let rhsKey = rhs.timelineKey
            if lhsKey.frameMinY != rhsKey.frameMinY { return lhsKey.frameMinY < rhsKey.frameMinY }
            if lhsKey.frameMinX != rhsKey.frameMinX { return lhsKey.frameMinX < rhsKey.frameMinX }
            if (lhsKey.label ?? "") != (rhsKey.label ?? "") { return (lhsKey.label ?? "") < (rhsKey.label ?? "") }
            return (lhsKey.identifier ?? "") < (rhsKey.identifier ?? "")
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
