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

    /// Tripwire observed a cheap UIKit-side condition that should be checked.
    /// The caller should parse again and let the parsed accessibility
    /// signature classify the result.
    case tripwireTriggered(timeMs: Int)

    /// The hard timeout elapsed while the tree was still changing.
    case timedOut(timeMs: Int)

    /// The loop's structured-concurrency context was cancelled (e.g. the
    /// session was torn down mid-action). Distinct from `.timedOut` so the
    /// caller can short-circuit the rest of the action pipeline rather than
    /// continue parsing/exploring on a dead session.
    case cancelled(timeMs: Int)

    var timeMs: Int {
        switch self {
        case .settled(let ms), .tripwireTriggered(let ms), .timedOut(let ms), .cancelled(let ms):
            return ms
        }
    }

    /// True when the response represents a UI state we believe in —
    /// either the loop reached multi-cycle stability, or the settle loop
    /// was preempted because Tripwire triggered. The caller parses immediately,
    /// and the classifier may still return no change. `.timedOut` and
    /// `.cancelled` return false.
    var didSettleCleanly: Bool {
        switch self {
        case .settled, .tripwireTriggered: return true
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
            rect = r.cgRect
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
/// **Settle signal boundary.** SettleSession is the post-action correctness
/// path — it watches the AX tree because that is the user-visible truth for
/// a screen-reader user. `TheTripwire.waitForAllClear` watches CALayers and
/// is deliberately blind to the AX tree; the two cannot be unified because
/// "no layer motion" and "AX tree stable" disagree on every spinner-driven
/// loading state. `SettleSwipeLoopState` (Navigation.swift) is also AX-tree
/// driven but interleaves parse with frame yields and exposes a `moved`
/// latch — its termination is per-swipe, not per-action. See the comment on
/// `SettleSwipeLoopState` for the full four-implementation boundary.
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
///
/// `@MainActor` justification: drives a MainActor-bound parse loop and stores
/// `@MainActor`-typed provider closures.
@MainActor struct SettleSession { // swiftlint:disable:this agent_main_actor_value_type

    /// Number of consecutive identical-fingerprint cycles required before the
    /// AX tree is considered stable. Three is the smallest value that filters
    /// out the typical "one frame of churn between two stable states" pattern
    /// produced by UIKit animations finishing on a frame boundary, while
    /// keeping the best-case settle to `3 × cycleInterval` (~300 ms).
    static let defaultCyclesRequired: Int = 3

    /// Poll interval between AX-tree fingerprint checks. 100 ms is roughly
    /// six display frames at 60 Hz — long enough that a parse + fingerprint
    /// + sleep cycle stays well under one frame of main-actor budget on real
    /// devices, short enough that settle latency is dominated by the
    /// `cyclesRequired × interval` floor rather than per-cycle wait. This is
    /// the poll cadence VoiceOver itself uses for similar idle-checks, which
    /// is why agents driving the same AX surface feel "in sync" at this rate.
    static let defaultCycleIntervalMs: Int = 100

    /// Hard ceiling on how long the settle loop will wait for the AX tree
    /// to quiesce before giving up with `.timedOut`. 5 s is the longest
    /// any well-behaved iOS transition (push, modal, alert, tab switch)
    /// takes to settle in practice; anything longer is almost always a
    /// non-terminating animation (spinner not flagged `updatesFrequently`,
    /// a Lottie loop, a video) and the caller is better off accepting the
    /// last-seen snapshot than blocking the action pipeline further.
    static let defaultTimeoutMs: Int = 5_000

    typealias ParseProvider = @MainActor () -> Screen?
    typealias TopVCProvider = @MainActor () -> ObjectIdentifier?
    typealias TripwireSignalProvider = @MainActor () -> TheTripwire.TripwireSignal
    typealias Sleeper = @Sendable (UInt64) async throws -> Void

    let parseProvider: ParseProvider
    let tripwireSignalProvider: TripwireSignalProvider
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
        self.init(
            parseProvider: parseProvider,
            tripwireSignalProvider: {
                TheTripwire.TripwireSignal(
                    topmostVC: topVCProvider(),
                    navigation: .empty,
                    windowStack: .empty
                )
            },
            sleeper: sleeper,
            cyclesRequired: cyclesRequired,
            cycleIntervalMs: cycleIntervalMs,
            timeoutMs: timeoutMs
        )
    }

    init(
        parseProvider: @escaping ParseProvider,
        tripwireSignalProvider: @escaping TripwireSignalProvider,
        sleeper: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) },
        cyclesRequired: Int = SettleSession.defaultCyclesRequired,
        cycleIntervalMs: Int = SettleSession.defaultCycleIntervalMs,
        timeoutMs: Int = SettleSession.defaultTimeoutMs
    ) {
        self.parseProvider = parseProvider
        self.tripwireSignalProvider = tripwireSignalProvider
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
            tripwireSignalProvider: { tripwire.tripwireSignal() }
        )
    }

    /// Result of the loop, exposed so the caller can compute transients.
    struct Outcome {
        let outcome: SettleOutcome
        /// Every `(key, element)` pair observed in any cycle of the loop.
        /// Includes spinner cycles and other intermediate states.
        let elementsByKey: [TimelineKey: AccessibilityElement]
    }

    /// Run the settle loop.
    ///
    /// `baselineTopVC` is the topmost view controller captured *before* the
    /// action that triggered this settle — passed in explicitly so the
    /// caller owns the snapshot point and the loop never asks the
    /// provider for the baseline itself. This eliminates an ambiguity
    /// in scripted test seams (where the same closure was called once
    /// for the baseline and again per cycle) and makes the contract:
    /// "the provider answers `the current top VC` and nothing else."
    /// Production callers now use `run(start:baselineTripwireSignal:)`. This
    /// overload remains for tests and older call seams that only model VC
    /// identity.
    func run(start: CFAbsoluteTime, baselineTopVC: ObjectIdentifier?) async -> Outcome {
        await run(
            start: start,
            baselineTripwireSignal: TheTripwire.TripwireSignal(
                topmostVC: baselineTopVC,
                navigation: .empty,
                windowStack: .empty
            )
        )
    }

    /// Same loop as `run(start:baselineTopVC:)`, with the full tripwire signal.
    /// Production uses this path so visible window/navigation/key changes reset
    /// the settle baseline, then the loop proves the post-transition AX tree is
    /// stable before returning. The returned outcome still records whether a
    /// tripwire fired so callers can suppress transition transients.
    func run(start: CFAbsoluteTime, baselineTripwireSignal: TheTripwire.TripwireSignal) async -> Outcome {
        let cycleNs = UInt64(cycleIntervalMs) * 1_000_000
        let deadline = start + Double(timeoutMs) / 1000

        var elementsByKey: [TimelineKey: AccessibilityElement] = [:]
        var stableCycles = 0
        var tripwireBaseline = baselineTripwireSignal
        var observedTripwireTrigger = false

        // Seed the baseline fingerprint synchronously so the first
        // post-sleep parse can already count as stable cycle 1. Without
        // this seed, a static screen pays cyclesRequired+1 cycles.
        var previousFingerprint: Int? = {
            guard let initial = parseProvider() else { return nil }
            let initialElements = initial.hierarchy.sortedElements
            for element in initialElements {
                elementsByKey[element.timelineKey] = element
            }
            return Self.fingerprint(of: initialElements)
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

            let nowTripwireSignal = tripwireSignalProvider()
            if nowTripwireSignal != tripwireBaseline {
                observedTripwireTrigger = true
                tripwireBaseline = nowTripwireSignal
                stableCycles = 0
                guard let parse = parseProvider() else {
                    previousFingerprint = nil
                    continue
                }
                let parsedElements = parse.hierarchy.sortedElements
                for element in parsedElements {
                    elementsByKey[element.timelineKey] = element
                }
                previousFingerprint = Self.fingerprint(of: parsedElements)
                continue
            }

            guard let parse = parseProvider() else { continue }
            let parsedElements = parse.hierarchy.sortedElements
            for element in parsedElements {
                elementsByKey[element.timelineKey] = element
            }

            let fingerprint = Self.fingerprint(of: parsedElements)
            if let previousFingerprint, fingerprint == previousFingerprint {
                stableCycles += 1
                if stableCycles >= cyclesRequired {
                    return Outcome(
                        outcome: observedTripwireTrigger
                            ? .tripwireTriggered(timeMs: Self.elapsedMs(since: start))
                            : .settled(timeMs: Self.elapsedMs(since: start)),
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
